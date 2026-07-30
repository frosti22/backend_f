from fastapi import FastAPI

app = FastAPI(title="log.CKD ML Service")

@app.get("/health")
def health():
    return {"status": "ok", "service": "log-ckd-ml"}
