"""
tests/test_verify_auth_challenge_response.py
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Isolated unit tests for the Cognito VerifyAuthChallengeResponse Lambda trigger.
"""

from __future__ import annotations


def _base_event(expected_answer: str, submitted_answer: str) -> dict:
    return {
        "triggerSource": "VerifyAuthChallengeResponse_Authentication",
        "userName": "+27821234567",
        "request": {
            "userAttributes": {"phone_number": "+27821234567"},
            "privateChallengeParameters": {"answer": expected_answer},
            "challengeAnswer": submitted_answer,
        },
        "response": {
            "answerCorrect": False,
        },
    }


def test_matching_answer_is_correct():
    """Verify a submitted code matching the private challenge answer is accepted."""
    import verify_auth_challenge_response.handler as handler

    event = _base_event(expected_answer="123456", submitted_answer="123456")
    result = handler.lambda_handler(event, context=None)

    assert result["response"]["answerCorrect"] is True


def test_non_matching_answer_is_incorrect():
    """Verify a submitted code that doesn't match the private challenge answer is rejected."""
    import verify_auth_challenge_response.handler as handler

    event = _base_event(expected_answer="123456", submitted_answer="000000")
    result = handler.lambda_handler(event, context=None)

    assert result["response"]["answerCorrect"] is False


def test_missing_private_challenge_parameters_is_incorrect():
    """Verify a missing expected answer fails closed rather than raising."""
    import verify_auth_challenge_response.handler as handler

    event = {
        "request": {
            "userAttributes": {"phone_number": "+27821234567"},
            "privateChallengeParameters": {},
            "challengeAnswer": "123456",
        },
        "response": {"answerCorrect": False},
    }
    result = handler.lambda_handler(event, context=None)

    assert result["response"]["answerCorrect"] is False
