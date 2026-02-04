"""
Tests for API retry logic
"""

import pytest
from unittest.mock import Mock, patch
import requests


class TestApiRequestWithRetry:
    """Tests for api_request_with_retry function"""
    
    def test_successful_request(self):
        """Test successful request on first try"""
        from etl.etl_base import api_request_with_retry
        
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.raise_for_status = Mock()
        
        with patch("requests.get", return_value=mock_response) as mock_get:
            result = api_request_with_retry(
                "https://api.example.com/test",
                {"Authorization": "Bearer token"},
                timeout=30,
                max_retries=3,
                retry_delay=1
            )
            
            assert result == mock_response
            mock_get.assert_called_once()
            
    def test_retry_on_timeout(self):
        """Test retry on request timeout"""
        from etl.etl_base import api_request_with_retry
        
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.raise_for_status = Mock()
        
        # First call times out, second succeeds
        with patch("requests.get") as mock_get:
            mock_get.side_effect = [
                requests.exceptions.Timeout("Timeout"),
                mock_response
            ]
            
            with patch("time.sleep"):  # Skip actual sleep
                result = api_request_with_retry(
                    "https://api.example.com/test",
                    {"Authorization": "Bearer token"},
                    timeout=30,
                    max_retries=3,
                    retry_delay=1
                )
                
                assert result == mock_response
                assert mock_get.call_count == 2
                
    def test_retry_on_server_error(self):
        """Test retry on 500 server error"""
        from etl.etl_base import api_request_with_retry
        
        error_response = Mock()
        error_response.status_code = 500
        
        success_response = Mock()
        success_response.status_code = 200
        success_response.raise_for_status = Mock()
        
        with patch("requests.get") as mock_get:
            mock_get.side_effect = [error_response, success_response]
            
            with patch("time.sleep"):
                result = api_request_with_retry(
                    "https://api.example.com/test",
                    {"Authorization": "Bearer token"},
                    timeout=30,
                    max_retries=3,
                    retry_delay=1
                )
                
                assert result == success_response
                assert mock_get.call_count == 2
                
    def test_retry_on_rate_limit(self):
        """Test retry on 429 rate limit with Retry-After header"""
        from etl.etl_base import api_request_with_retry
        
        rate_limit_response = Mock()
        rate_limit_response.status_code = 429
        rate_limit_response.headers = {"Retry-After": "2"}
        
        success_response = Mock()
        success_response.status_code = 200
        success_response.raise_for_status = Mock()
        
        with patch("requests.get") as mock_get:
            mock_get.side_effect = [rate_limit_response, success_response]
            
            with patch("time.sleep") as mock_sleep:
                result = api_request_with_retry(
                    "https://api.example.com/test",
                    {"Authorization": "Bearer token"},
                    timeout=30,
                    max_retries=3,
                    retry_delay=1
                )
                
                assert result == success_response
                # Should use Retry-After value
                mock_sleep.assert_called_with(2)
                
    def test_all_retries_exhausted(self):
        """Test exception raised when all retries fail"""
        from etl.etl_base import api_request_with_retry
        
        with patch("requests.get") as mock_get:
            mock_get.side_effect = requests.exceptions.Timeout("Timeout")
            
            with patch("time.sleep"):
                with pytest.raises(requests.exceptions.Timeout):
                    api_request_with_retry(
                        "https://api.example.com/test",
                        {"Authorization": "Bearer token"},
                        timeout=30,
                        max_retries=3,
                        retry_delay=1
                    )
                    
                # Should have tried 3 times
                assert mock_get.call_count == 3
                
    def test_no_retry_on_client_error(self):
        """Test no retry on 4xx client errors (except 429)"""
        from etl.etl_base import api_request_with_retry
        
        error_response = Mock()
        error_response.status_code = 400
        error_response.raise_for_status = Mock(
            side_effect=requests.exceptions.HTTPError("400 Bad Request")
        )
        
        with patch("requests.get", return_value=error_response):
            with pytest.raises(requests.exceptions.HTTPError):
                api_request_with_retry(
                    "https://api.example.com/test",
                    {"Authorization": "Bearer token"},
                    timeout=30,
                    max_retries=3,
                    retry_delay=1
                )
