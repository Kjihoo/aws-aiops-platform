"""
Lambda Entry Point

호출 형식:
  {"input": "오늘 미사용 리소스 알려줘"}

응답:
  {
    "answer": "...한국어 답변...",
    "trace": [메시지 1, 메시지 2, ...]  # 디버깅용 단계별 추적
  }
"""

from langchain_core.messages import HumanMessage

from graph import GRAPH


def _serialize_message(msg):
    """LangChain Message를 JSON 가능한 dict로 변환"""
    msg_type = msg.__class__.__name__
    content = getattr(msg, "content", None)

    # content가 list (multimodal) 이면 텍스트만 추출
    if isinstance(content, list):
        text_parts = []
        for part in content:
            if isinstance(part, dict) and "text" in part:
                text_parts.append(part["text"])
            elif isinstance(part, str):
                text_parts.append(part)
        content = "\n".join(text_parts) if text_parts else None

    tool_calls = getattr(msg, "tool_calls", None)
    serialized = {
        "type": msg_type,
        "content": content[:1000] if isinstance(content, str) else content,
    }
    if tool_calls:
        serialized["tool_calls"] = [
            {"name": tc.get("name"), "args": tc.get("args", {})}
            for tc in tool_calls
        ]
    return serialized


def handler(event, context):
    user_input = event.get("input", "")
    if not user_input:
        return {"error": "input 필드 필수. 예: {\"input\":\"오늘 미사용 리소스 알려줘\"}"}

    try:
        # V2: recursion_limit=16 → 도구 호출 최대 약 8 라운드 (reasoning ↔ tools)
        result = GRAPH.invoke(
            {"messages": [HumanMessage(content=user_input)]},
            config={"recursion_limit": 16},
        )
    except Exception as e:
        return {"error": str(e), "errorType": type(e).__name__}

    messages = result.get("messages", [])
    final = messages[-1] if messages else None

    # 최종 답변 추출
    answer = ""
    if final:
        content = getattr(final, "content", "")
        if isinstance(content, list):
            for part in content:
                if isinstance(part, dict) and "text" in part:
                    answer += part["text"]
                elif isinstance(part, str):
                    answer += part
        else:
            answer = content

    return {
        "answer": answer,
        "trace": [_serialize_message(m) for m in messages],
    }
