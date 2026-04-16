"""Tests for auth_manager timeout behavior"""

import pytest
from unittest.mock import patch, MagicMock
import requests


def test_refresh_token_has_timeout():
    """Verify _refresh_token passes timeout to requests.post"""
    from shared.auth_manager import TokenManager

    mgr = TokenManager.__new__(TokenManager)
    mgr.region_code = "test"
    mgr.auth_url = "https://api.breezeway.io/public/auth/v1"
    mgr.conn = MagicMock()
    mgr.cur = MagicMock()

    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "access_token": "new_token",
        "refresh_token": "new_refresh",
        "expires_in": 86400,
    }

    with patch("shared.auth_manager.requests.post", return_value=mock_response) as mock_post:
        mgr._refresh_token("old_refresh_token")
        _, kwargs = mock_post.call_args
        assert "timeout" in kwargs, "requests.post must be called with timeout"
        assert kwargs["timeout"] == 30


def test_generate_new_tokens_has_timeout():
    """Verify _generate_new_tokens passes timeout to requests.post"""
    from shared.auth_manager import TokenManager

    mgr = TokenManager.__new__(TokenManager)
    mgr.region_code = "test"
    mgr.auth_url = "https://api.breezeway.io/public/auth/v1"
    mgr.conn = MagicMock()
    mgr.cur = MagicMock()

    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "access_token": "new_token",
        "refresh_token": "new_refresh",
        "expires_in": 86400,
    }

    with patch("shared.auth_manager.requests.post", return_value=mock_response) as mock_post:
        mgr._generate_new_tokens("client_id", "client_secret")
        _, kwargs = mock_post.call_args
        assert "timeout" in kwargs, "requests.post must be called with timeout"
        assert kwargs["timeout"] == 30
