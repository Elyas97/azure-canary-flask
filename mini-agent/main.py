import logging
import uuid
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

import agent

log = logging.getLogger("app")
app = FastAPI(title="Mini insurance assistant")
STATIC = Path(__file__).parent / "static"


class Question(BaseModel):
    question: str = Field(min_length=1, max_length=500)
    thread_id: str | None = None


class Answer(BaseModel):
    answer: str
    outcome: str
    thread_id: str


@app.get("/")
def index():
    return FileResponse(STATIC / "index.html")

@app.get("/help", status_code=200)
def help():
    return {"message": "This is a mini insurance assistant. You can ask questions related to insurance, and the assistant will try to help you. If it cannot answer your question, it will hand you over to a colleague."}

@app.get("/health", status_code=200)
def health():
    return {"status": "ok"}


@app.post("/api/ask", response_model=Answer)
def ask(q: Question):
    tid = q.thread_id or str(uuid.uuid4())
    try:
        r = agent.ask(q.question, tid)
    except Exception:  # safe fallback: never leave the customer without an answer
        log.exception("agent failed")
        r = {"answer": "Something went wrong. I'll hand you over to a colleague.", "outcome": "error"}
    return Answer(answer=r["answer"], outcome=r["outcome"], thread_id=tid)
