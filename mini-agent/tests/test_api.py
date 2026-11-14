from fastapi.testclient import TestClient

import main

client = TestClient(main.app)


def test_rejects_empty_question():
    assert client.post("/api/ask", json={"question": ""}).status_code == 422


def test_returns_answer(monkeypatch):
    monkeypatch.setattr(main.agent, "ask", lambda q, t: {"answer": "stub", "outcome": "answered"})
    r = client.post("/api/ask", json={"question": "refund?"})
    assert r.status_code == 200
    assert r.json()["answer"] == "stub" and r.json()["thread_id"]


def test_agent_failure_falls_back_safely(monkeypatch):
    def boom(q, t):
        raise RuntimeError("llm down")
    monkeypatch.setattr(main.agent, "ask", boom)
    r = client.post("/api/ask", json={"question": "refund?"})
    assert r.status_code == 200 and r.json()["outcome"] == "error"


def test_serves_html():
    assert "Insurance assistant" in client.get("/").text
