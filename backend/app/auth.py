import hmac
from typing import Annotated

from fastapi import Depends, Header

from app.config import Settings, get_settings
from app.errors import AppError


def require_app_token(
    settings: Annotated[Settings, Depends(get_settings)],
    authorization: Annotated[str | None, Header()] = None,
) -> None:
    """Bearer APP_TOKEN check (contracts/README.md, Auth). An unset APP_TOKEN rejects everything."""
    scheme, _, token = (authorization or "").partition(" ")
    if not settings.APP_TOKEN or scheme.lower() != "bearer" or not hmac.compare_digest(token, settings.APP_TOKEN):
        raise AppError(401, "unauthorized", "missing or invalid bearer token")
