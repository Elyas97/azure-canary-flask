# Mini insurance assistant

A small LLM agent with a web UI, built to practise production patterns for agentic apps.

**Stack:** Python, FastAPI, Pydantic, pytest, LangGraph, Langfuse (optional tracing)

## How it works

`guardrail -> retrieve -> generate -> verify`, built as a LangGraph `StateGraph`:

- **Guardrail:** blocks prompt injection, other customers' data and off-topic requests.
- **Retrieve:** looks up the knowledge base. No context found means a human handover.
- **Generate:** answers using only the retrieved context.
- **Verify:** a grounding check. An unsupported answer becomes a handover instead of a guess.
- State is kept per `thread_id` with a checkpointer. API errors fall back to a safe message.

## Run

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env        # add OPENAI_API_KEY (and Langfuse keys if you want traces)
uvicorn main:app --reload   # open http://127.0.0.1:8000
```

## Test

```bash
pytest -m "not eval"   # fast API tests, no LLM calls
pytest -m eval         # eval suite: outcome checks + LLM-as-judge (needs a key)
```

## Evals

`tests/test_evals.py` is a test set that runs as a regression suite. Outcomes
(answered / handover / blocked) are checked deterministically, and an LLM judge
checks the facts in answers. Change a prompt, re-run, compare.

## Results log

| Change | Pass rate |
|---|---|
| Baseline | _fill in_ |

## Next steps

- Replace the keyword lookup with embeddings and a vector store (Qdrant)
- Real human-in-the-loop with LangGraph `interrupt()`
- Make retrieval an LLM-called tool
- Dockerfile and CI pipeline
