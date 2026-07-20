"""
kwella — Cognito Custom Auth: PreSignUp Lambda
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Auto-confirms the Cognito user created by the app's self-provisioning
SignUp call, which exists solely to create a user record for a
phone number Cognito has never seen before (see auth_notifier.dart's
requestOtp -> UserNotFoundException -> SignUp -> retry flow).

The password given to that SignUp call is never used to sign in — actual
identity verification happens immediately afterwards via the CUSTOM_AUTH OTP
challenge (DefineAuthChallenge/CreateAuthChallenge/VerifyAuthChallengeResponse).
This trigger auto-confirms the user and auto-verifies the phone number so
Cognito doesn't also require its own SMS confirmation code before the
CUSTOM_AUTH flow can proceed.

Governance compliance (KWELLA_CODE_GOVERNANCE.md):
  - Python 3.12 native syntax throughout.
  - No hardcoded secrets; no external service calls at all.
"""

from __future__ import annotations

import logging
from typing import Any

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Cognito PreSignUp trigger — auto-confirms and auto-verifies the phone number."""
    logger.info("Auto-confirming new user %s.", event.get("userName"))
    response = event["response"]
    response["autoConfirmUser"] = True
    response["autoVerifyPhone"] = True
    return event
