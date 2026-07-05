"""
kwella — Cognito Custom Auth: VerifyAuthChallengeResponse Lambda
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Verifies the OTP code entered by the user against the code issued by
CreateAuthChallenge for the phone-number + OTP passwordless sign-in flow.

Governance compliance (KWELLA_CODE_GOVERNANCE.md):
  - Python 3.12 native syntax throughout.
  - No hardcoded secrets; the comparison is against the challenge-scoped
    privateChallengeParameters set by CreateAuthChallenge, not a stored secret.
"""

from __future__ import annotations

import logging
from typing import Any

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Cognito VerifyAuthChallengeResponse trigger — checks the submitted OTP."""
    request = event["request"]
    response = event["response"]

    expected = request.get("privateChallengeParameters", {}).get("answer")
    submitted = request.get("challengeAnswer")

    is_correct = expected is not None and submitted == expected
    logger.info("OTP verification result: %s", is_correct)

    response["answerCorrect"] = is_correct
    return event
