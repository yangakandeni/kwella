"""
kwella — Cognito Custom Auth: DefineAuthChallenge Lambda
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Decides the next step in the phone-number + OTP passwordless sign-in flow.

Key behaviors:
  1. No prior session -> issue a CUSTOM_CHALLENGE (the OTP prompt).
  2. Last challenge answered correctly -> issue tokens (sign-in complete).
  3. Three or more incorrect CUSTOM_CHALLENGE attempts -> fail authentication.
  4. Otherwise -> re-issue a CUSTOM_CHALLENGE so the user can retry the code.

Governance compliance (KWELLA_CODE_GOVERNANCE.md):
  - Python 3.12 native syntax throughout.
  - No hardcoded secrets; no external service calls at all.
"""

from __future__ import annotations

import logging
from typing import Any

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

_MAX_ATTEMPTS = 3


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Cognito DefineAuthChallenge trigger — decides challengeName/issueTokens/failAuthentication."""
    session = event["request"].get("session") or []
    response = event["response"]

    if not session:
        logger.info("No prior session — issuing initial CUSTOM_CHALLENGE.")
        response["challengeName"] = "CUSTOM_CHALLENGE"
        response["issueTokens"] = False
        response["failAuthentication"] = False
        return event

    last_attempt = session[-1]
    if last_attempt.get("challengeName") == "CUSTOM_CHALLENGE" and last_attempt.get("challengeResult") is True:
        logger.info("Most recent CUSTOM_CHALLENGE was answered correctly — issuing tokens.")
        response["issueTokens"] = True
        response["failAuthentication"] = False
        return event

    wrong_attempts = sum(
        1
        for attempt in session
        if attempt.get("challengeName") == "CUSTOM_CHALLENGE" and attempt.get("challengeResult") is False
    )
    if wrong_attempts >= _MAX_ATTEMPTS:
        logger.warning("Reached %d incorrect OTP attempts — failing authentication.", wrong_attempts)
        response["issueTokens"] = False
        response["failAuthentication"] = True
        return event

    logger.info("Incorrect OTP attempt %d/%d — re-issuing CUSTOM_CHALLENGE.", wrong_attempts, _MAX_ATTEMPTS)
    response["challengeName"] = "CUSTOM_CHALLENGE"
    response["issueTokens"] = False
    response["failAuthentication"] = False
    return event
