"""
tests/test_create_auth_challenge.py
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Isolated unit tests for the Cognito CreateAuthChallenge Lambda trigger.
"""

from __future__ import annotations

import importlib
import os

import pytest


def _reload_handler():
    """Reload the handler module so OTP_TEST_CODE/ENVIRONMENT env var overrides take effect."""
    import create_auth_challenge.handler as handler

    return importlib.reload(handler)


def _base_event(phone_number: str = "+27821234567") -> dict:
    return {
        "triggerSource": "CreateAuthChallenge_Authentication",
        "userName": phone_number,
        "request": {
            "userAttributes": {"phone_number": phone_number},
            "challengeName": "CUSTOM_CHALLENGE",
            "session": [],
        },
        "response": {
            "publicChallengeParameters": {},
            "privateChallengeParameters": {},
            "challengeMetadata": None,
        },
    }


def test_default_fixed_otp_code_is_issued(monkeypatch):
    """Verify the default fixed test code (123456) is used when no env override is set."""
    monkeypatch.delenv("OTP_TEST_CODE", raising=False)
    handler = _reload_handler()

    result = handler.lambda_handler(_base_event(), context=None)

    assert result["response"]["privateChallengeParameters"]["answer"] == "123456"


def test_otp_test_code_env_override_is_respected(monkeypatch):
    """Verify OTP_TEST_CODE env var overrides the default fixed test code."""
    monkeypatch.setenv("OTP_TEST_CODE", "999999")
    handler = _reload_handler()

    result = handler.lambda_handler(_base_event(), context=None)

    assert result["response"]["privateChallengeParameters"]["answer"] == "999999"

    # Restore the default for subsequent tests in this module.
    monkeypatch.delenv("OTP_TEST_CODE", raising=False)
    _reload_handler()


def test_public_challenge_parameters_include_phone_number(monkeypatch):
    """Verify the public challenge parameters echo back the phone number for the OTP screen."""
    monkeypatch.delenv("OTP_TEST_CODE", raising=False)
    handler = _reload_handler()

    result = handler.lambda_handler(_base_event("+27831234567"), context=None)

    assert result["response"]["publicChallengeParameters"]["phone_number"] == "+27831234567"


def test_private_challenge_parameters_are_never_exposed_publicly(monkeypatch):
    """Verify the OTP answer never leaks into publicChallengeParameters."""
    monkeypatch.delenv("OTP_TEST_CODE", raising=False)
    handler = _reload_handler()

    result = handler.lambda_handler(_base_event(), context=None)

    assert "answer" not in result["response"]["publicChallengeParameters"]


def test_fixed_otp_code_is_blocked_in_production(monkeypatch):
    """The fixed testing-phase code must never be issued when ENVIRONMENT=production."""
    monkeypatch.setenv("ENVIRONMENT", "production")
    handler = _reload_handler()

    with pytest.raises(RuntimeError):
        handler.lambda_handler(_base_event(), context=None)

    monkeypatch.delenv("ENVIRONMENT", raising=False)
    _reload_handler()


def test_fixed_otp_code_is_blocked_in_production_case_insensitively(monkeypatch):
    """The production check must not be bypassable via casing (e.g. "Production")."""
    monkeypatch.setenv("ENVIRONMENT", "Production")
    handler = _reload_handler()

    with pytest.raises(RuntimeError):
        handler.lambda_handler(_base_event(), context=None)

    monkeypatch.delenv("ENVIRONMENT", raising=False)
    _reload_handler()


def test_fixed_otp_code_is_allowed_outside_production(monkeypatch):
    """Non-production environments (staging, dev, or unset) may still use the fixed code."""
    monkeypatch.setenv("ENVIRONMENT", "staging")
    handler = _reload_handler()

    result = handler.lambda_handler(_base_event(), context=None)

    assert result["response"]["privateChallengeParameters"]["answer"] == "123456"

    monkeypatch.delenv("ENVIRONMENT", raising=False)
    _reload_handler()
