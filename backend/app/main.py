import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.config import get_settings
from app.errors import install_handlers
from app.evaluate.budget import BudgetBook
from app.evaluate.router import router as evaluate_router
from app.evaluate.service import Evaluator
from app.plan.router import router as plan_router
from app.plan.service import Planner, make_client

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    client = make_client(settings)
    app.state.planner = Planner(client, settings)
    app.state.evaluator = Evaluator(client, settings, BudgetBook(settings))
    yield
    await client.close()


app = FastAPI(title="Roamory backend", lifespan=lifespan)
install_handlers(app)
app.include_router(plan_router)
app.include_router(evaluate_router)


@app.get("/healthz")
async def healthz() -> dict:
    return {"ok": True}
