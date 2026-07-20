"""
tests/test_pre_sign_up.py
~~~~~~~~~~~~~~~~~~~~~~~~~~
Isolated unit tests for the Cognito PreSignUp Lambda trigger.
"""

from __future__ import annotations


def _base_event(phone_number: str = "+27821234567") -> dict:
    return {
        "triggerSource": "PreSignUp_SignUp",
        "userName": phone_number,
        "request": {
            "userAttributes": {"phone_number": phone_number},
        },
        "response": {
            "autoConfirmUser": False,
            "autoVerifyPhone": False,
            "autoVerifyEmail": False,
        },
    }


def test_auto_confirms_new_user():
    """The user created by the app's self-provisioning SignUp call must be
    auto-confirmed — the real identity check happens via the CUSTOM_AUTH OTP
    challenge immediately afterwards, not Cognito's own confirmation code."""
    import pre_sign_up.handler as handler

    result = handler.lambda_handler(_base_event(), context=None)

    assert result["response"]["autoConfirmUser"] is True


def test_auto_verifies_phone_number():
    """The phone number must be auto-verified so the CUSTOM_AUTH flow can
    proceed immediately without Cognito requiring its own SMS verification."""
    import pre_sign_up.handler as handler

    result = handler.lambda_handler(_base_event(), context=None)

    assert result["response"]["autoVerifyPhone"] is True
