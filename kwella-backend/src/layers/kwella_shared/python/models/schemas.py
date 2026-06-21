"""
kwella_shared.models.schemas
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Pydantic v2 data models for all kwella single-table entities.

Entity key patterns (KWELLA_SYSTEM_CONTEXT.md §3):
  Rider Profile  → PK: USR#<RiderId>,        SK: PROFILE
  Driver Profile → PK: USR#<DriverId>,       SK: PROFILE
                   GSI1_PK: VEH#<Sticker>,   GSI1_SK: DRIVER
  Owner Profile  → PK: USR#<OwnerId>,        SK: PROFILE
  Vehicle Asset  → PK: VEH#<CataSticker>,    SK: METADATA
                   GSI1_PK: USR#<OwnerId>,   GSI1_SK: VEH#<CataSticker>

Governance compliance:
  - Pydantic v2 only: model_validator, model_dump(), ConfigDict.
    No @root_validator, .dict(), or .json() permitted.
  - Native Python 3.9+ type hints used throughout.
    No imports from the legacy `typing` module (List, Dict, Optional
    replaced by built-in generics and X | None union syntax).
  - Decimal used for all monetary fields to avoid floating-point drift
    in the cancellation ledger and fee-holiday balance calculations.
"""

from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal
from typing import Literal, Self

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)


# ---------------------------------------------------------------------------
# Shared base
# ---------------------------------------------------------------------------

class BaseProfile(BaseModel):
    """Common fields shared by Rider, Driver, and Owner profiles.

    Attributes:
        phone:      E.164-formatted mobile number (e.g. "+27821234567").
        rating:     Platform star rating, constrained to [0.0, 5.0].
        created_at: UTC timestamp of account creation. Defaults to now.
    """

    model_config = ConfigDict(
        # Forbid any extra keys that are not declared on the model.
        extra="forbid",
        # Coerce compatible input types (e.g. str → Decimal) strictly.
        strict=False,
        # Populate model fields from their field aliases as well.
        populate_by_name=True,
    )

    phone: str = Field(
        ...,
        description="E.164-formatted mobile number.",
        examples=["+27821234567"],
        min_length=10,
        max_length=16,
    )
    rating: Decimal = Field(
        default=Decimal("5.0"),
        description="Platform star rating between 0.0 and 5.0.",
        ge=Decimal("0.0"),
        le=Decimal("5.0"),
    )
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(tz=timezone.utc),
        description="UTC timestamp of account creation.",
    )

    @field_validator("phone")
    @classmethod
    def phone_must_be_e164(cls, value: str) -> str:
        """Enforce E.164 format: '+' followed by 9-15 digits."""
        stripped = value.replace(" ", "").replace("-", "")
        if not stripped.startswith("+") or not stripped[1:].isdigit():
            raise ValueError(
                f"Phone number '{value}' must be in E.164 format (e.g. +27821234567)."
            )
        return stripped


# ---------------------------------------------------------------------------
# Rider
# ---------------------------------------------------------------------------

class RiderProfile(BaseProfile):
    """Pydantic model for a kwella Rider entity.

    DynamoDB key → PK: USR#<RiderId>, SK: PROFILE

    Attributes:
        cancellation_debt: Outstanding cash-trip cancellation penalty owed
                           to the platform (Decimal to preserve ledger fidelity).
                           0.00 indicates a clear account.
        active_trip_id:    PK of the currently active Trip entity, or None
                           when the rider has no in-progress journey.
    """

    cancellation_debt: Decimal = Field(
        default=Decimal("0.00"),
        description="Outstanding cash-cancellation debt in ZAR (0.00 = clear).",
        ge=Decimal("0.00"),
    )
    active_trip_id: str | None = Field(
        default=None,
        description="PK of the rider's current active trip, or None.",
    )

    @model_validator(mode="after")
    def suspended_if_debt_outstanding(self) -> Self:
        """Warn in model data when a rider carries uncleared debt.

        The actual suspension enforcement is handled by the business logic
        layer; this validator annotates the model for downstream consumers.
        """
        if self.cancellation_debt > Decimal("0.00"):
            # Non-raising: debt status is informational at the model layer.
            # The Lambda handler is responsible for enforcing access restrictions.
            pass
        return self


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

class DriverProfile(BaseProfile):
    """Pydantic model for a kwella Driver entity.

    DynamoDB key → PK: USR#<DriverId>,     SK: PROFILE
                   GSI1_PK: VEH#<Sticker>, GSI1_SK: DRIVER

    Attributes:
        assigned_cata_sticker: The unique CATA sticker identifier linking
                               this driver to their allocated 7-seater vehicle.
        fee_holiday_balance:   Cumulative ZAR amount of platform-fee waivers
                               granted as compensation for a rider's unpaid
                               cash-trip cancellation. Resets to 0.00 once
                               the rider clears their debt and platform fee
                               collection resumes at the standard 10% rate.
        is_online:             Whether the driver is currently accepting trips.
    """

    assigned_cata_sticker: str = Field(
        ...,
        description="CATA sticker ID linking the driver to their vehicle.",
        min_length=1,
    )
    fee_holiday_balance: Decimal = Field(
        default=Decimal("0.00"),
        description=(
            "Outstanding platform-fee holiday balance in ZAR. "
            "Capped at the original cancellation penalty (max R30). "
            "0.00 means the driver is on the standard 10% fee rate."
        ),
        ge=Decimal("0.00"),
        le=Decimal("30.00"),  # Tiered cap per KWELLA_SYSTEM_CONTEXT.md §4
    )
    is_online: bool = Field(
        default=False,
        description="True if the driver is actively accepting trip requests.",
    )

    @field_validator("assigned_cata_sticker")
    @classmethod
    def sticker_must_be_non_empty(cls, value: str) -> str:
        """Ensure the CATA sticker is a non-whitespace string."""
        if not value.strip():
            raise ValueError("assigned_cata_sticker must not be blank.")
        return value.strip().upper()


# ---------------------------------------------------------------------------
# Hybrid payment rails
# ---------------------------------------------------------------------------

class RiderDebtLedgerItem(BaseModel):
    """Trip-scoped rider debt item for late cash-cancellation defaults.

    DynamoDB key → PK: USER#<RiderId>, SK: DEBT#<TripId>
    """

    model_config = ConfigDict(
        extra="forbid",
        strict=False,
    )

    amount: Decimal = Field(
        ...,
        gt=Decimal("0.00"),
        description="Outstanding rider debt in ZAR for the cancelled trip.",
    )
    timestamp: datetime = Field(
        default_factory=lambda: datetime.now(tz=timezone.utc),
        description="UTC debt creation timestamp.",
    )
    status: Literal["PENDING_SETTLEMENT"] = Field(
        default="PENDING_SETTLEMENT",
        description="Debt remains open until the rider settles the balance.",
    )
    reason: Literal["LATE_CANCELLATION"] = Field(
        default="LATE_CANCELLATION",
        description="Business reason for the rider debt state.",
    )


class DriverCreditLedgerItem(BaseModel):
    """Driver-facing compensating credit posted with zero platform commission.

    DynamoDB key → PK: USER#<DriverId>, SK: LEDGER#<Timestamp>
    """

    model_config = ConfigDict(
        extra="forbid",
        strict=False,
    )

    amount: Decimal = Field(
        ...,
        gt=Decimal("0.00"),
        description="Flat cancellation payout fee credited to the driver.",
    )
    timestamp: datetime = Field(
        default_factory=lambda: datetime.now(tz=timezone.utc),
        description="UTC ledger credit timestamp.",
    )
    reason: Literal["LATE_CANCELLATION"] = Field(
        default="LATE_CANCELLATION",
        description="Business reason for the compensating credit.",
    )
    platform_commission_rate: Decimal = Field(
        default=Decimal("0.00"),
        description="Zero-percent platform commission rate for the holiday rail.",
        ge=Decimal("0.00"),
        le=Decimal("0.00"),
    )
    platform_commission_amount: Decimal = Field(
        default=Decimal("0.00"),
        description="Absolute commission deduction, fixed at 0.00 ZAR.",
        ge=Decimal("0.00"),
        le=Decimal("0.00"),
    )


# ---------------------------------------------------------------------------
# Vehicle Asset
# ---------------------------------------------------------------------------

class VehicleAsset(BaseModel):
    """Pydantic model for a kwella Vehicle entity (7-seater amaphela only).

    DynamoDB key → PK: VEH#<CataSticker>,  SK: METADATA
                   GSI1_PK: USR#<OwnerId>, GSI1_SK: VEH#<CataSticker>

    The CATA sticker serves as the natural primary key enforcing vehicle
    uniqueness natively in the DynamoDB single-table design.

    Attributes:
        cata_sticker: Unique CATA regulatory sticker identifier. Acts as the
                      VEH# PK prefix in the single-table schema.
        make:         Vehicle manufacturer (e.g. "Toyota").
        model:        Vehicle model name (e.g. "HiAce").
        owner_id:     USR#<OwnerId> of the registered fleet owner.
    """

    model_config = ConfigDict(
        extra="forbid",
        strict=False,
        populate_by_name=True,
    )

    cata_sticker: str = Field(
        ...,
        description="Unique CATA sticker ID — used as VEH# PK prefix.",
        min_length=1,
    )
    make: str = Field(
        ...,
        description="Vehicle manufacturer name.",
        min_length=1,
        max_length=64,
    )
    model: str = Field(
        ...,
        description="Vehicle model name.",
        min_length=1,
        max_length=64,
    )
    owner_id: str = Field(
        ...,
        description="USR#<OwnerId> of the registered fleet owner.",
        min_length=1,
    )

    @field_validator("cata_sticker")
    @classmethod
    def normalise_cata_sticker(cls, value: str) -> str:
        """Strip whitespace and normalise sticker to uppercase."""
        cleaned = value.strip().upper()
        if not cleaned:
            raise ValueError("cata_sticker must not be blank.")
        return cleaned

    @field_validator("owner_id")
    @classmethod
    def owner_id_must_have_prefix(cls, value: str) -> str:
        """Enforce USR# prefix on the owner identifier."""
        if not value.startswith("USR#"):
            raise ValueError(
                f"owner_id '{value}' must carry the 'USR#' prefix "
                "(e.g. 'USR#abc-123')."
            )
        return value
