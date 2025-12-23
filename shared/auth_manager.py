"""
Authentication Manager for Breezeway API

Handles OAuth2 token generation, refresh, and caching.
Tokens are stored in the database and automatically refreshed when needed.

Usage:
    from shared.auth_manager import TokenManager

    token_mgr = TokenManager('nashville')
    access_token = token_mgr.get_valid_token()
"""

import requests
import psycopg2
from datetime import datetime, timedelta
from dotenv import dotenv_values
import time
import os
from typing import Optional


class TokenManager:
    """Manages OAuth2 tokens for Breezeway API with auto-refresh capability"""

    def __init__(self, region_code: str):
        """
        Initialize TokenManager for a specific region.

        Args:
            region_code: Region identifier (e.g., 'nashville', 'austin')
        """
        self.region_code = region_code
        self.auth_url = "https://api.breezeway.io/public/auth/v1"
        self.conn = None
        self.cur = None
        self._connect_db()

    def _connect_db(self):
        """Establish database connection"""
        try:
            # Try to load from .env file
            env_path = os.path.join(os.path.dirname(__file__), '..', '.env')
            envs = dict(dotenv_values(env_path))

            if not envs:
                raise ValueError("Could not load .env file")

            url = (f"postgresql://{envs['USER']}:{envs['PASSWORD']}"
                   f"@{envs['HOST']}:{envs['PORT']}/{envs['DB']}?sslmode=require")

            self.conn = psycopg2.connect(url)
            self.cur = self.conn.cursor()

        except Exception as e:
            raise Exception(f"Failed to connect to database: {e}")

    def get_company_id(self) -> int:
        """
        Get company_id for this region from database.

        Returns:
            int: Company ID

        Raises:
            Exception: If company_id not found
        """
        self.cur.execute("""
            SELECT company_id
            FROM breezeway.api_tokens
            WHERE region_code = %s
        """, (self.region_code,))

        result = self.cur.fetchone()
        if not result or not result[0]:
            raise ValueError(
                f"No company_id found for region: {self.region_code}. "
                f"Update api_tokens table with company_id."
            )

        return result[0]

    def get_valid_token(self) -> str:
        """
        Get a valid access token, automatically refreshing if needed.

        Returns:
            str: Valid access token

        Raises:
            Exception: If token generation/refresh fails
        """
        # Check if we have a valid token in database
        self.cur.execute("""
            SELECT access_token, token_expires_at, refresh_token,
                   client_id, client_secret
            FROM breezeway.api_tokens
            WHERE region_code = %s
        """, (self.region_code,))

        result = self.cur.fetchone()
        if not result:
            raise ValueError(
                f"No credentials found for region: {self.region_code}. "
                f"Run phase1_setup.sql to initialize credentials."
            )

        access_token, expires_at, refresh_token, client_id, client_secret = result

        # Check if token is still valid (with 5-minute buffer)
        if access_token and expires_at:
            if datetime.now() < expires_at - timedelta(minutes=5):
                print(f"✓ Using cached token for {self.region_code}")
                return access_token

        # Token expired or missing, need to refresh
        print(f"⟳ Token expired for {self.region_code}, refreshing...")

        if refresh_token:
            # Try to refresh
            try:
                return self._refresh_token(refresh_token)
            except Exception as e:
                print(f"⚠ Refresh failed: {e}, generating new tokens...")

        # Generate new tokens
        return self._generate_new_tokens(client_id, client_secret)

    def _refresh_token(self, refresh_token: str) -> str:
        """
        Refresh access token using refresh token.

        Args:
            refresh_token: Current refresh token

        Returns:
            str: New access token
        """
        url = f"{self.auth_url}/refresh"
        headers = {
            "accept": "application/json",
            "Authorization": f"JWT {refresh_token}"
        }

        response = requests.post(url, headers=headers)

        # Handle rate limiting
        if response.status_code == 429:
            retry_after = int(response.headers.get('Retry-After', 60))
            print(f"⏳ Rate limited, waiting {retry_after} seconds...")
            time.sleep(retry_after)
            response = requests.post(url, headers=headers)

        if response.status_code != 200:
            raise Exception(
                f"Token refresh failed: {response.status_code} - {response.text}"
            )

        tokens = response.json()

        # Update database
        self.cur.execute("""
            UPDATE breezeway.api_tokens SET
                access_token = %s,
                refresh_token = %s,
                token_expires_at = %s,
                last_refreshed_at = CURRENT_TIMESTAMP,
                updated_at = CURRENT_TIMESTAMP,
                last_error = NULL
            WHERE region_code = %s
        """, (
            tokens['access_token'],
            tokens['refresh_token'],
            datetime.now() + timedelta(hours=24),
            self.region_code
        ))
        self.conn.commit()

        print(f"✓ Token refreshed for {self.region_code}")
        return tokens['access_token']

    def _generate_new_tokens(self, client_id: str, client_secret: str) -> str:
        """
        Generate new tokens from client credentials.

        Args:
            client_id: OAuth2 client ID
            client_secret: OAuth2 client secret

        Returns:
            str: New access token
        """
        url = f"{self.auth_url}/"
        headers = {
            "accept": "application/json",
            "content-type": "application/json"
        }
        data = {
            "client_id": client_id,
            "client_secret": client_secret
        }

        response = requests.post(url, headers=headers, json=data)

        # Handle rate limiting
        if response.status_code == 429:
            retry_after = int(response.headers.get('Retry-After', 60))
            print(f"⏳ Rate limited, waiting {retry_after} seconds...")
            time.sleep(retry_after)
            response = requests.post(url, headers=headers, json=data)

        if response.status_code != 200:
            error_msg = f"Token generation failed: {response.status_code} - {response.text}"

            # Log error to database
            self.cur.execute("""
                UPDATE breezeway.api_tokens SET
                    last_error = %s,
                    updated_at = CURRENT_TIMESTAMP
                WHERE region_code = %s
            """, (error_msg, self.region_code))
            self.conn.commit()

            raise Exception(error_msg)

        tokens = response.json()

        # Update database
        self.cur.execute("""
            UPDATE breezeway.api_tokens SET
                access_token = %s,
                refresh_token = %s,
                token_expires_at = %s,
                last_refreshed_at = CURRENT_TIMESTAMP,
                token_generation_count = token_generation_count + 1,
                updated_at = CURRENT_TIMESTAMP,
                last_error = NULL
            WHERE region_code = %s
        """, (
            tokens['access_token'],
            tokens['refresh_token'],
            datetime.now() + timedelta(hours=24),
            self.region_code
        ))
        self.conn.commit()

        print(f"✓ New tokens generated for {self.region_code}")
        return tokens['access_token']

    def __del__(self):
        """Clean up database connection"""
        if self.cur:
            self.cur.close()
        if self.conn:
            self.conn.close()


# Convenience function for quick token retrieval
def get_token(region_code: str) -> str:
    """
    Quick helper to get a valid token for a region.

    Args:
        region_code: Region identifier

    Returns:
        str: Valid access token
    """
    manager = TokenManager(region_code)
    return manager.get_valid_token()


if __name__ == "__main__":
    # Test token manager
    import sys

    if len(sys.argv) < 2:
        print("Usage: python auth_manager.py <region_code>")
        print("Example: python auth_manager.py nashville")
        sys.exit(1)

    region = sys.argv[1]

    try:
        token = get_token(region)
        print(f"\n✓ Successfully retrieved token for {region}")
        print(f"Token (first 50 chars): {token[:50]}...")
    except Exception as e:
        print(f"\n✗ Error: {e}")
        sys.exit(1)
