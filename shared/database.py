"""
Database connection management for Breezeway ETL pipeline.

Provides connection pooling and context managers for database operations.

Usage:
    from shared.database import DatabaseManager

    # Get connection
    conn = DatabaseManager.get_connection()

    # Use context manager
    with DatabaseManager.get_cursor() as cur:
        cur.execute("SELECT * FROM table")
        results = cur.fetchall()
"""

import psycopg2
from psycopg2 import pool
from contextlib import contextmanager
from dotenv import dotenv_values
import os
from typing import Optional


class DatabaseManager:
    """Manages database connections with pooling"""

    _connection_pool: Optional[pool.SimpleConnectionPool] = None
    _single_connection: Optional[psycopg2.extensions.connection] = None

    @classmethod
    def initialize_pool(cls, minconn: int = 1, maxconn: int = 10):
        """
        Initialize connection pool.

        Args:
            minconn: Minimum number of connections to maintain
            maxconn: Maximum number of connections allowed
        """
        if cls._connection_pool is None:
            env_path = os.path.join(os.path.dirname(__file__), '..', '.env')
            envs = dict(dotenv_values(env_path))

            if not envs:
                raise ValueError("Could not load .env file")

            url = (f"postgresql://{envs['USER']}:{envs['PASSWORD']}"
                   f"@{envs['HOST']}:{envs['PORT']}/{envs['DB']}?sslmode=require")

            cls._connection_pool = pool.SimpleConnectionPool(
                minconn,
                maxconn,
                url
            )

    @classmethod
    def get_connection(cls) -> psycopg2.extensions.connection:
        """
        Get a database connection (singleton pattern for simple use cases).

        Returns:
            psycopg2 connection object
        """
        if cls._single_connection is None or cls._single_connection.closed:
            env_path = os.path.join(os.path.dirname(__file__), '..', '.env')
            envs = dict(dotenv_values(env_path))

            if not envs:
                raise ValueError("Could not load .env file")

            url = (f"postgresql://{envs['USER']}:{envs['PASSWORD']}"
                   f"@{envs['HOST']}:{envs['PORT']}/{envs['DB']}?sslmode=require")

            cls._single_connection = psycopg2.connect(url)

        return cls._single_connection

    @classmethod
    @contextmanager
    def get_cursor(cls, commit: bool = True):
        """
        Context manager for database cursor with automatic commit/rollback.

        Args:
            commit: Whether to auto-commit on success (default: True)

        Yields:
            psycopg2 cursor object

        Example:
            with DatabaseManager.get_cursor() as cur:
                cur.execute("INSERT INTO table VALUES (%s)", (value,))
                # Auto-commits on exit
        """
        conn = cls.get_connection()
        cur = conn.cursor()
        try:
            yield cur
            if commit:
                conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            cur.close()

    @classmethod
    @contextmanager
    def get_pooled_connection(cls):
        """
        Context manager for pooled database connection.

        Yields:
            psycopg2 connection object from pool

        Example:
            with DatabaseManager.get_pooled_connection() as conn:
                cur = conn.cursor()
                cur.execute("SELECT * FROM table")
        """
        if cls._connection_pool is None:
            cls.initialize_pool()

        conn = cls._connection_pool.getconn()
        try:
            yield conn
        finally:
            cls._connection_pool.putconn(conn)

    @classmethod
    def close_all_connections(cls):
        """Close all connections and clean up pool"""
        if cls._single_connection and not cls._single_connection.closed:
            cls._single_connection.close()
            cls._single_connection = None

        if cls._connection_pool:
            cls._connection_pool.closeall()
            cls._connection_pool = None


# Convenience function for executing queries
def execute_query(query: str, params: tuple = None, fetch: bool = False):
    """
    Execute a SQL query with automatic connection handling.

    Args:
        query: SQL query string
        params: Query parameters (optional)
        fetch: Whether to fetch and return results (default: False)

    Returns:
        Query results if fetch=True, otherwise None

    Example:
        results = execute_query(
            "SELECT * FROM table WHERE id = %s",
            (123,),
            fetch=True
        )
    """
    with DatabaseManager.get_cursor() as cur:
        cur.execute(query, params)
        if fetch:
            return cur.fetchall()
        return None


if __name__ == "__main__":
    # Test database connection
    print("=== Testing Database Connection ===\n")

    try:
        # Test simple connection
        conn = DatabaseManager.get_connection()
        print("✓ Database connection successful")
        print(f"  Database: {conn.info.dbname}")
        print(f"  User: {conn.info.user}")
        print(f"  Host: {conn.info.host}:{conn.info.port}")

        # Test cursor context manager
        with DatabaseManager.get_cursor() as cur:
            cur.execute("SELECT version()")
            version = cur.fetchone()[0]
            print(f"\n✓ Query execution successful")
            print(f"  PostgreSQL version: {version[:50]}...")

        # Test table access
        with DatabaseManager.get_cursor() as cur:
            cur.execute("""
                SELECT COUNT(*) FROM information_schema.tables
                WHERE table_schema = 'api_integrations'
            """)
            count = cur.fetchone()[0]
            print(f"\n✓ Schema access successful")
            print(f"  Tables in api_integrations: {count}")

        print(f"\n✓ All tests passed!")

    except Exception as e:
        print(f"\n✗ Error: {e}")
        import traceback
        traceback.print_exc()
