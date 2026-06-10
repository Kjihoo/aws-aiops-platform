// Static JSON 방식 — Lambda 공개 호출 없이 S3에서 직접 가져옴
const DATA_URL = "./data.json";

let resourceChart = null;
let hourlyChart = null;
let cachedData = null;
let currentQueryIdx = 0;

// ── 현재 시각 ───────────────────────────────────────────────────────────────
function updateNow() {
  const now = new Date();
  const gen = cachedData?.generatedAt ? new Date(cachedData.generatedAt) : null;
  document.getElementById("now").textContent = gen
    ? `현재 ${now.toLocaleString("ko-KR")} · 데이터 생성 ${gen.toLocaleString("ko-KR")}`
    : now.toLocaleString("ko-KR");
}
setInterval(updateNow, 1000);
updateNow();

// ── 데이터 로드 ────────────────────────────────────────────────────────────
async function loadData() {
  try {
    const res = await fetch(`${DATA_URL}?t=${Date.now()}`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    cachedData = await res.json();
    renderAll();
  } catch (e) {
    console.error("data.json load error:", e);
  }
}

function renderAll() {
  renderSummary();
  renderLogAnalysis();
  renderHourlyChart();
  renderResourceCheck();
  renderReports();
  renderAthena();
  renderChatSample();
}

// ── 1. 오늘 요약 ────────────────────────────────────────────────────────────
// 우선순위: 모니터링#3의 operatorMetrics → 우리 summary fallback
function renderSummary() {
  const s = cachedData?.summary || {};
  const op = s.operatorMetrics; // 모니터링#3 데이터 (있으면)
  const src = s.operatorMetricsSource || "none";

  // 출처 배지 (HTML 카드 헤더 옆에 자동 표시)
  const srcEl = document.getElementById("summary-source");
  if (srcEl) {
    srcEl.textContent = src === "monitoring-team" ? "출처: 모니터링#3 실데이터" : "출처: 데이터 없음";
    srcEl.className = src === "monitoring-team"
      ? "text-xs text-emerald-600 ml-2"
      : "text-xs text-slate-400 ml-2";
  }

  const pick = (a, b) => (a !== undefined && a !== null && a !== "" ? a : b);
  const total   = pick(op?.totalOrders,      s.totalOrders);
  const failure = pick(op?.failureRate,      s.failureRate);
  const avg     = pick(op?.avgResponseTimeMs, s.avgResponseTimeMs);
  const alarm   = pick(op?.currentAlarmCount, s.currentAlarmCount);

  document.getElementById("card-total").textContent =
    total != null ? Number(total).toLocaleString() : "-";
  document.getElementById("card-failure").textContent =
    failure != null ? `${(Number(failure) * (Number(failure) <= 1 ? 100 : 1)).toFixed(1)}%` : "-";
  document.getElementById("card-avg").textContent =
    avg != null ? `${avg}ms` : "-";
  document.getElementById("card-alarm").textContent = alarm != null ? alarm : "-";
}

// ── 2. 리소스 점검 ──────────────────────────────────────────────────────────
function renderResourceCheck() {
  const r = cachedData?.resourceCheck || { byType: {}, items: [], total: 0 };

  const ctx = document.getElementById("resource-chart").getContext("2d");
  if (resourceChart) resourceChart.destroy();
  resourceChart = new Chart(ctx, {
    type: "doughnut",
    data: {
      labels: Object.keys(r.byType),
      datasets: [
        {
          data: Object.values(r.byType),
          backgroundColor: ["#ef4444", "#f59e0b", "#3b82f6", "#10b981", "#8b5cf6"],
        },
      ],
    },
    options: {
      plugins: {
        legend: { position: "bottom" },
        title: { display: true, text: `총 ${r.total}건` },
      },
    },
  });

  const tbody = document.getElementById("resource-tbody");
  tbody.innerHTML = "";
  (r.items || []).slice(0, 10).forEach((it) => {
    const tr = document.createElement("tr");
    tr.className = "border-b";
    tr.innerHTML = `
      <td class="p-2"><span class="px-2 py-1 bg-slate-200 text-xs rounded">${it.checkType || "-"}</span></td>
      <td class="p-2 font-mono text-xs">${it.resourceType || "-"} ${it.resourceId || ""}</td>
      <td class="p-2 text-xs">${it.reason || "-"}</td>
    `;
    tbody.appendChild(tr);
  });
}

// ── 3. Athena 쿼리 (미리 정한 4개를 페이지네이션) ───────────────────────────
function renderAthena() {
  showQuery(currentQueryIdx);
}

function showQuery(idx) {
  const queries = cachedData?.athenaQueries || [];
  if (queries.length === 0) return;
  currentQueryIdx = ((idx % queries.length) + queries.length) % queries.length;
  const q = queries[currentQueryIdx];

  document.getElementById("sql-label").textContent = `[${currentQueryIdx + 1}/${queries.length}] ${q.label}`;
  document.getElementById("sql-input").value = q.sql || "";

  const status = document.getElementById("sql-status");
  if (q.error) {
    status.textContent = `❌ ${q.error}`;
    status.className = "text-sm text-red-600";
    document.getElementById("sql-result").innerHTML = "";
    return;
  }

  status.textContent = `✅ ${q.rowCount}건`;
  status.className = "text-sm text-emerald-600";

  const headers = q.headers || [];
  const rows = q.rows || [];
  document.getElementById("sql-result").innerHTML = rows.length === 0
    ? '<tr><td class="p-2 text-slate-500">결과 없음</td></tr>'
    : `
      <thead class="bg-slate-100">
        <tr>${headers.map((h) => `<th class="text-left p-2 text-xs">${h}</th>`).join("")}</tr>
      </thead>
      <tbody>
        ${rows.map((r) => `<tr class="border-b">${headers.map((h) => `<td class="p-2 text-xs font-mono">${r[h] ?? ""}</td>`).join("")}</tr>`).join("")}
      </tbody>
    `;
}

function nextQuery() { showQuery(currentQueryIdx + 1); }
function prevQuery() { showQuery(currentQueryIdx - 1); }

// ── 1-B. 로그 분석 카드 ────────────────────────────────────────────────────
function renderLogAnalysis() {
  const s = cachedData?.summary || {};
  const total = s.totalLogEvents ?? 0;
  document.getElementById("card-log-events").textContent = total.toLocaleString();
  document.getElementById("card-log-error-rate").textContent =
    s.errorRate != null ? `${Number(s.errorRate).toFixed(2)}%` : "-";
  document.getElementById("card-log-peak").textContent = s.peakHour || "-";

  const streamEl = document.getElementById("card-log-top-stream");
  const pctEl    = document.getElementById("card-log-top-stream-pct");
  if (s.topErrorStream && s.topErrorStream !== "N/A") {
    streamEl.textContent = s.topErrorStream;
    streamEl.title       = s.topErrorStream;
    pctEl.textContent    = `에러율 ${Number(s.topErrorPct || 0).toFixed(2)}%`;
  } else {
    streamEl.textContent = "-";
    pctEl.textContent    = "-";
  }
}

// ── 1-C. 시간대별 트렌드 차트 ─────────────────────────────────────────────
function renderHourlyChart() {
  const c = cachedData?.hourlyChart || { labels: [], totals: [], errors: [] };
  const ctx = document.getElementById("hourly-chart").getContext("2d");
  if (hourlyChart) hourlyChart.destroy();
  hourlyChart = new Chart(ctx, {
    type: "bar",
    data: {
      labels: c.labels,
      datasets: [
        { label: "총 이벤트",  data: c.totals, backgroundColor: "#3b82f6" },
        { label: "에러 이벤트", data: c.errors, backgroundColor: "#ef4444" },
      ],
    },
    options: {
      responsive: true,
      plugins: {
        legend: { position: "bottom" },
        title:  { display: true, text: `시간대별 추이 (${c.rowCount || 0}개 시간 구간)` },
      },
      scales: { y: { beginAtZero: true } },
    },
  });
}

// ── 3-B. 자동 리포트 목록 ──────────────────────────────────────────────────
function renderReports() {
  const reports = cachedData?.reports || [];
  const tbody = document.getElementById("reports-tbody");
  tbody.innerHTML = "";
  if (reports.length === 0 || reports[0]?.error) {
    tbody.innerHTML = `<tr><td colspan="4" class="p-2 text-slate-500 text-xs">리포트 없음${reports[0]?.error ? ` (${reports[0].error})` : ""}</td></tr>`;
    return;
  }
  reports.forEach((r) => {
    const tr = document.createElement("tr");
    tr.className = "border-b hover:bg-slate-50";
    tr.innerHTML = `
      <td class="p-2 font-mono text-xs">${r.reportDate || "-"}</td>
      <td class="p-2"><span class="px-2 py-1 bg-blue-100 text-blue-700 text-xs rounded">${r.reportType || "-"}</span></td>
      <td class="p-2 text-xs">${r.title || "-"}</td>
      <td class="p-2 font-mono text-xs text-slate-500 truncate max-w-md" title="${r.s3Url || ""}">${(r.s3Url || "").replace("s3://", "")}</td>
    `;
    tbody.appendChild(tr);
  });
}

// ── 4. 채팅 샘플 ────────────────────────────────────────────────────────────
function renderChatSample() {
  const samples = cachedData?.chatSamples || [];
  const log = document.getElementById("chat-log");
  log.innerHTML = "";
  samples.forEach((s) => {
    appendChat("user", s.question);
    appendChat("assistant", s.answer);
  });
}

function appendChat(role, content) {
  const log = document.getElementById("chat-log");
  const div = document.createElement("div");
  div.className = role === "user" ? "flex justify-end" : "flex justify-start";
  div.innerHTML = `
    <div class="${role === "user" ? "bg-purple-100" : "bg-slate-100"} px-4 py-2 rounded-lg max-w-3xl whitespace-pre-wrap">
      ${content}
    </div>
  `;
  log.appendChild(div);
  log.scrollTop = log.scrollHeight;
}

// 초기 + 1분마다 새로고침 (data.json은 EventBridge가 5분마다 갱신)
loadData();
setInterval(loadData, 60 * 1000);
