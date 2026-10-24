import pytest

from app.config import Settings
from app.errors import AppError
from app.evaluate.budget import BudgetBook

S = Settings(_env_file=None)


@pytest.fixture
def clock():
    return [0.0]


@pytest.fixture
def book(clock):
    return BudgetBook(S, now=lambda: clock[0])


def test_bucket_capacity_then_refill(book, clock):
    for _ in range(5):
        book.take_select("t1")
    with pytest.raises(AppError) as e:
        book.take_select("t1")
    assert e.value.status == 429 and e.value.code == "rate_limited" and e.value.retryable is False
    clock[0] += 30
    book.take_select("t1")


def test_trips_are_independent(book):
    for _ in range(5):
        book.take_select("t1")
    book.take_select("t2")


def test_fast_hourly_cap(book, clock):
    for _ in range(100):
        book.take_select("t1")
        clock[0] += 30
    with pytest.raises(AppError):
        book.take_select("t1")  # 100 calls inside the last 3600 s


def test_rejected_select_spends_nothing(book, clock):
    for _ in range(5):
        book.take_select("t1")
    with pytest.raises(AppError):
        book.take_select("t1")
    clock[0] += 30
    book.take_select("t1")  # the rejected call did not take the refilled token


def test_describe_does_not_touch_bucket(book):
    for _ in range(5):
        book.take_select("t1")
    book.take_describe("t1")


def test_describe_hourly_cap(book):
    for _ in range(60):
        book.take_describe("t1")
    with pytest.raises(AppError):
        book.take_describe("t1")
