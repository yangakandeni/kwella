"""Unit tests for the hybrid late-cancellation transaction payload."""

from __future__ import annotations

from unittest.mock import patch

import botocore.exceptions
import pytest

from ledger_service.cancellation_handler import (
    CancellationLedgerPayload,
    build_cancellation_transact_items,
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
    assert len(transact_payload) == 2
    assert transact_payload[0]["Put"]["Item"]["SK"] == {"S": "DEBT#trip-1"}
    assert transact_payload[1]["Put"]["Item"]["SK"] == {"S": "LEDGER#2026-06-21T10:15:00Z"}