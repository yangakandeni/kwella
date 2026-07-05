"""
kwella — Cognito Custom Auth: CreateAuthChallenge Lambda
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Issues the OTP challenge for the phone-number + OTP passwordless sign-in flow.

**Testing-phase behavior**: issues a FIXED one-time code (default "123456",
overridable via the OTP_TEST_CODE environment variable) instead of generating
a random code and delivering it over SNS SMS. Swapping in real SMS delivery
later only requires changing this Lambda — no other part of the sign-in flow
(app or the other two Cognito triggers) needs to change.

Governance compliance (KWELLA_CODE_GOVERNANCE.md):
  - Python 3.12 native syntax throughout.
  - No hardcoded secrets — the test code is a placeholder value, not a
    credential, and is overridable via environment variable.
"""

from __future__ import annotations

import logging
import os
from typing import Any

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

OTP_TEST_CODE = os.environ.get("OTP_TEST_CODE", "123456")


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Cognito CreateAuthChallenge trigger — issues the OTP challenge parameters."""
    request = event["request"]
    response = event["response"]

    phone_number = request.get("userAttributes", {}).get("phone_number", "")
    logger.info("Issuing OTP challenge for %s (testing-phase fixed code).", phone_number)

    response["publicChallengeParameters"] = {"phone_number": phone_number}
    response["privateChallengeParameters"] = {"answer": OTP_TEST_CODE}
    response["challengeMetadata"] = "TEST_FIXED_OTP"
    return event
