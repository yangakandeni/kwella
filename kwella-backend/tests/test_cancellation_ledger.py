"""Unit tests for the hybrid late-cancellation transaction payload."""

from __future__ import annotations

from unittest.mock import patch

import botocore.exceptions
import pytest

from decimal import Decimal

from ledger_service.cancellation_handler import (
    CancellationLedgerPayload,
    build_cancellation_transact_items,
    build_debt_settlement_transact_items,
    process_cancellation,
)


def _payload() -> CancellationLedgerPayload:
    return CancellationLedgerPayload(
        rider_id="rider-1",
        driver_id="driver-1",
        trip_id="trip-1",
        amount="25.50",
        timestamp="2026-06-21T10:15:00Z",
        driver_in_transit_seconds=240,
    )


def test_build_cancellation_transact_items_uses_exact_single_table_keys():
    transact_items = build_cancellation_transact_items(_payload(), "kwella-core-test")

    assert transact_items[0]["Put"]["Item"]["PK"] == {"S": "USER#rider-1"}
    assert transact_items[0]["Put"]["Item"]["SK"] == {"S": "DEBT#trip-1"}
    assert transact_items[0]["Put"]["Item"]["status"] == {"S": "PENDING_SETTLEMENT"}
    assert transact_items[0]["Put"]["Item"]["reason"] == {"S": "LATE_CANCELLATION"}

    assert transact_items[1]["Put"]["Item"]["PK"] == {"S": "USER#driver-1"}
    assert transact_items[1]["Put"]["Item"]["SK"] == {"S": "LEDGER#2026-06-21T10:15:00Z"}
    assert transact_items[1]["Put"]["Item"]["platform_commission_rate"] == {"N": "0.00"}
    assert transact_items[1]["Put"]["Item"]["platform_commission_amount"] == {"N": "0.00"}

    # Third item: recouped-from-the-passenger suspension flag on the rider's
    # PROFILE record (README.md §3B Option B) — the same key the
    # auth_authorizer Lambda reads to block app access.
    assert transact_items[2]["Update"]["Key"]["PK"] == {"S": "USR#rider-1"}
    assert transact_items[2]["Update"]["Key"]["SK"] == {"S": "PROFILE"}
    assert transact_items[2]["Update"]["ExpressionAttributeValues"][":suspended"] == {"BOOL": True}
    assert transact_items[2]["Update"]["ExpressionAttributeValues"][":amount"] == {"N": "25.50"}


@pytest.mark.parametrize(
    "cancellation_reasons",
    [
        [{"Code": "ConditionalCheckFailed"}, {"Code": "None"}],
        [{"Code": "None"}, {"Code": "ConditionalCheckFailed"}],
    ],
)
def test_process_cancellation_rolls_back_when_either_transact_write_fails(cancellation_reasons):
    payload = _payload()
    client_error = botocore.exceptions.ClientError(
        {
            "Error": {
                "Code": "TransactionCanceledException",
                "Message": "Transaction cancelled",
            },
            "CancellationReasons": cancellation_reasons,
        },
        "TransactWriteItems",
    )

    with patch(
        "ledger_service.cancellation_handler.get_table",
        return_value=type("TableStub", (), {"name": "kwella-core-test"})(),
    ), patch(
        "ledger_service.cancellation_handler._dynamodb_client.transact_write_items",
        side_effect=client_error,
    ) as transact_write:
        with pytest.raises(botocore.exceptions.ClientError):
            process_cancellation(payload)

    transact_payload = transact_write.call_args.kwargs["TransactItems"]
    assert len(transact_payload) == 3
    assert transact_payload[0]["Put"]["Item"]["SK"] == {"S": "DEBT#trip-1"}
    assert transact_payload[1]["Put"]["Item"]["SK"] == {"S": "LEDGER#2026-06-21T10:15:00Z"}
    assert transact_payload[2]["Update"]["Key"]["SK"] == {"S": "PROFILE"}


# ---------------------------------------------------------------------------
# Debt settlement (recouped-from-the-passenger unlock — README.md §3B)
# ---------------------------------------------------------------------------

def test_build_debt_settlement_transact_items_targets_debt_and_profile_rows():
    transact_items = build_debt_settlement_transact_items(
        rider_id="rider-1",
        trip_id="trip-1",
        amount=Decimal("25.50"),
        table_name="kwella-core-test",
    )

    assert len(transact_items) == 2

    debt_update = transact_items[0]["Update"]
    assert debt_update["Key"]["PK"] == {"S": "USER#rider-1"}
    assert debt_update["Key"]["SK"] == {"S": "DEBT#trip-1"}
    assert debt_update["ExpressionAttributeValues"][":settled"] == {"S": "SETTLED"}
    assert debt_update["ExpressionAttributeValues"][":amount"] == {"N": "25.50"}

    profile_update = transact_items[1]["Update"]
    assert profile_update["Key"]["PK"] == {"S": "USR#rider-1"}
    assert profile_update["Key"]["SK"] == {"S": "PROFILE"}
    assert profile_update["ExpressionAttributeValues"][":amount"] == {"N": "25.50"}