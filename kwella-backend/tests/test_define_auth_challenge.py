"""
tests/test_define_auth_challenge.py
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Isolated unit tests for the Cognito DefineAuthChallenge Lambda trigger.
"""

from __future__ import annotations

from typing import Any


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _base_event(session: list[dict[str, Any]]) -> dict[str, Any]:
    """Build a minimal DefineAuthChallenge trigger event with the given session history."""
    return {
        "triggerSource": "DefineAuthChallenge_Authentication",
        "userName": "+27821234567",
        "request": {
            "userAttributes": {"phone_number": "+27821234567"},
            "session": session,
        },
        "response": {
            "challengeName": None,
            "issueTokens": False,
            "failAuthentication": False,
        },
    }


# ---------------------------------------------------------------------------
# Initial challenge tests
# ---------------------------------------------------------------------------

def test_empty_session_issues_custom_challenge():
    """Verify a brand-new sign-in attempt (no prior session) issues a CUSTOM_CHALLENGE."""
    import define_auth_challenge.handler as handler

    event = _base_event([])
    result = handler.lambda_handler(event, context=None)

    assert result["response"]["challengeName"] == "CUSTOM_CHALLENGE"
    assert result["response"]["issueTokens"] is False
    assert result["response"]["failAuthentication"] is False


# ---------------------------------------------------------------------------
# Correct answer tests
# ---------------------------------------------------------------------------

def test_correct_answer_issues_tokens():
    """Verify a correctly-answered CUSTOM_CHALLENGE results in tokens being issued."""
    import define_auth_challenge.handler as handler

    session = [{"challengeName": "CUSTOM_CHALLENGE", "challengeResult": True, "challengeMetadata": "TEST_FIXED_OTP"}]
    event = _base_event(session)
    result = handler.lambda_handler(event, context=None)

    assert result["response"]["issueTokens"] is True
    assert result["response"]["failAuthentication"] is False


# ---------------------------------------------------------------------------
# Incorrect answer / retry tests
# ---------------------------------------------------------------------------

def test_single_incorrect_answer_reissues_challenge():
    """Verify one incorrect attempt re-issues CUSTOM_CHALLENGE rather than failing."""
    import define_auth_challenge.handler as handler

    session = [{"challengeName": "CUSTOM_CHALLENGE", "challengeResult": False, "challengeMetadata": "TEST_FIXED_OTP"}]
    event = _base_event(session)
    result = handler.lambda_handler(event, context=None)

    assert result["response"]["challengeName"] == "CUSTOM_CHALLENGE"
    assert result["response"]["issueTokens"] is False
    assert result["response"]["failAuthentication"] is False


def test_two_incorrect_answers_still_reissues_challenge():
    """Verify two incorrect attempts still allow a retry (below the failure threshold)."""
    import define_auth_challenge.handler as handler

    session = [
        {"challengeName": "CUSTOM_CHALLENGE", "challengeResult": False, "challengeMetadata": "TEST_FIXED_OTP"},
        {"challengeName": "CUSTOM_CHALLENGE", "challengeResult": False, "challengeMetadata": "TEST_FIXED_OTP"},
    ]
    event = _base_event(session)
    result = handler.lambda_handler(event, context=None)

    assert result["response"]["challengeName"] == "CUSTOM_CHALLENGE"
    assert result["response"]["failAuthentication"] is False


def test_three_incorrect_answers_fails_authentication():
    """Verify three incorrect attempts locks the user out for this sign-in attempt."""
    import define_auth_challenge.handler as handler

    session = [
        {"challengeName": "CUSTOM_CHALLENGE", "challengeResult": False, "challengeMetadata": "TEST_FIXED_OTP"},
        {"challengeName": "CUSTOM_CHALLENGE", "challengeResult": False, "challengeMetadata": "TEST_FIXED_OTP"},
        {"challengeName": "CUSTOM_CHALLENGE", "challengeResult": False, "challengeMetadata": "TEST_FIXED_OTP"},
    ]
    event = _base_event(session)
    result = handler.lambda_handler(event, context=None)

    assert result["response"]["failAuthentication"] is True
    assert result["response"]["issueTokens"] is False
