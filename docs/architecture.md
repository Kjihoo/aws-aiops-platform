# 아키텍처 개요

team4-aiops 플랫폼 아키텍처와 데이터 수집 레이어 설계 문서.

## 도메인

샘플 이커머스 워크로드 (도메인 디테일은 평가 대상 아님 — 어떤 워크로드든 운영 자동화 가능함을 보이는 샘플).

## 레포 디렉터리

- `infrastructure/`: Terraform IaC (bootstrap, environments/dev, modules)
- `apps/`: 샘플 이커머스 마이크로서비스 (api-gateway, data-ingestion, query-service, frontend)
- `platform/`: 운영 플랫폼 (Lambda, Glue, Grafana 대시보드)
- `docs/`: 아키텍처, runbook, ADR

## 전체 흐름

```
이커머스 워크로드
  (CloudFront / ALB / ECS Fargate / RDS / NAT / IAM)
        │
        ▼  수집 (6 sources)
  CW(Metrics·Logs·Alarm) · Cost Explorer / CUR · Config · Tagging API · Resource Checker Lambda
        │
        ▼  저장
  S3 Data Lake (raw → cleansed → aggregated) + DynamoDB
        │
        ▼  분석·활용
  Glue · Athena · Grafana · QuickSight · Bedrock Agent · Report Generator Lambda
        │
        ▼
  Slack / SES (알림·리포트)
```

## 운영 데이터 수집 레이어 (W4 범위)

### 수집 소스 6종

| 소스 | 수집 대상 | 주기 | 1차 저장지 |
|---|---|---|---|
| CloudWatch Metrics | ALB(요청수/응답시간/4xx·5xx), ECS(CPU/Mem/태스크수), RDS(연결/IOPS/Latency), CloudFront, NAT | 1~5분 | S3 raw + CW |
| CloudWatch Logs | ECS Sample API, Lambda 로그 | 실시간 | CW Logs → S3 |
| CloudWatch Alarm | 임계 초과 이벤트 (5xx>5%, CPU>80% 등) | 이벤트 | DynamoDB `alarm_history` |
| Cost Explorer + CUR | 서비스별·일자별 비용, 증감률, 태그별 비용 | CE 일1회 / CUR AWS 자동 | S3 `raw/cost-explorer`, `raw/cur`, DynamoDB `cost_summary` |
| AWS Config | 리소스 구성 스냅샷, 규칙 위반 (Public S3, 22번 오픈, 백업 미설정 등) | 변경 발생 시 | S3 + Config 콘솔 |
| Resource Tagging API + Resource Checker Lambda | 태그 누락 / 미사용 EBS·EIP·Snapshot·중지 EC2 | 일1회 또는 주1회 | DynamoDB `check_results`, S3 history |

### 저장 구조

**S3 Data Lake** (`s3://team4-aiops-data-lake/`)
- `raw/`: 수집 그대로 (수집 시점 보존)
- `cleansed/`: 스키마 통일, 시간대 통일, 결측 처리
- `aggregated/`: 시간별·일별·서비스별 롤업

**DynamoDB** (Bedrock Agent 빠른 조회용)
- `resource_inventory` — 리소스 최신 상태
- `alarm_history` — 최근 알람 이력
- `cost_summary` — 일·월 비용 요약
- `check_results` — 태그/미사용 리소스 점검 결과

### 임계치·알람 기본값

| 알람 | 조건 |
|---|---|
| ALB 5xx 에러율 | 5분 평균 5% 초과 |
| ALB TargetResponseTime | 2초 초과 |
| ECS CPU/Memory | 80% 초과 |
| RDS CPU | 80% 초과 |
| RDS DatabaseConnections | 임계치 초과 (인스턴스 크기별) |
| TargetGroup HealthyHostCount | 1 미만 |
| NAT Gateway | PacketDrop 발생 |

알람 → SNS → Lambda → Slack Webhook 흐름.

### 필수 태그 규칙

`Project`, `Environment`, `Owner`, `CostCenter`, `Service` — Tag Checker Lambda 가 일1회 점검 후 누락 시 DynamoDB 기록 + Slack 알림.

## W4 제작 우선순위 (8주 일정 기준 현실적 분할)

W4 한 주에 전체를 만드는 건 무리. 우선순위:

| 우선 | 항목 | 비고 |
|---|---|---|
| 🟢 필수 | CW Metrics 수집 + S3 raw 적재 + Glue Crawler + Athena 쿼리 | 평가 Data 25% 핵심 |
| 🟢 필수 | Cost Explorer 일1회 Lambda + DynamoDB 저장 | Bedrock Agent 비용 질의 데모용 |
| 🟢 필수 | Resource Checker Lambda 1개 (미사용 EBS·EIP만) | 데모 임팩트 큼 |
| 🟡 권장 | CUR S3 → Athena 연동 | QuickSight 비용 대시보드용 (W5) |
| 🟡 권장 | AWS Config + 태그 점검 Lambda | 보안 리포트용 |
| 🔴 보류 | aggregated 레이어 ETL 풀세트 | W5와 묶음 |

## Bedrock Agent 질의 → 조회 매핑

| 질문 | 1차 조회 대상 |
|---|---|
| 이번 달 비용 급증 서비스? | Cost Explorer / CUR via Athena |
| 어제 5xx 원인 분석? | CW Logs + Alarm History (DynamoDB) |
| 태그 누락 리소스? | DynamoDB `check_results` |
| 미사용 리소스 (낭비)? | Resource Checker 결과 |
| ECS 상태 요약? | CW Metrics |
| 월간 운영 리포트 생성? | Athena (CW + Cost Summary 조합) |

## 핵심 한 문장

CloudWatch·Cost Explorer·CUR·AWS Config·Tagging API·Checker Lambda로 성능·로그·비용·구성·낭비 리소스를 수집해, S3 Data Lake와 DynamoDB에 저장하고, Grafana·QuickSight·Bedrock Agent·자동 리포트가 동일한 데이터 소스를 공유하도록 설계한 통합 수집 레이어.
