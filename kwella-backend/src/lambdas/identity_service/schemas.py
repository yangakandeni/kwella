"""
src/lambdas/identity_service/schemas.py
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Data layer schema definitions for vehicle ownership mapping.
"""

from __future__ import annotations

from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, field_validator


class VehicleOwnership(BaseModel):
    """Pydantic model representing vehicle ownership mapping.

    Partition Key (PK): VEHICLE#<vehicle_id>
    Sort Key (SK): OWNERSHIP

    Attributes:
        owner_id: Identifier of the owner (can be DRIVER#<id> or FLEET#<id>).
        status: ACTIVE
    """

    model_config = ConfigDict(
        extra="forbid",
        strict=False,
    )

    owner_id: str = Field(
        ...,
        description="Owner profile identifier, prefixed with 'DRIVER#' or 'FLEET#'."
    )
    status: Literal["ACTIVE"] = Field(
        default="ACTIVE",
        description="Active status indicator for the vehicle association."
    )

    @field_validator("owner_id")
    @classmethod
    def validate_owner_prefix(cls, value: str) -> str:
        """Enforce owner_id prefix of DRIVER# or FLEET#."""
        if not (value.startswith("DRIVER#") or value.startswith("FLEET#")):
            raise ValueError(
                f"owner_id '{value}' must carry the 'DRIVER#' or 'FLEET#' prefix."
            )
        return value
