# Database Access for Jaime - Data Engineer

## Connection Credentials

**Database Server:** 82.25.90.53
**Port:** 5432
**Database Name:** breezeway
**Username:** jaime
**Password:** vtR3VPfano2Egehz

---

## Power BI Connection Instructions

### Method 1: PostgreSQL Connector (Recommended)

1. Open Power BI Desktop
2. Click **Get Data** > **More**
3. Search for and select **PostgreSQL database**
4. Click **Connect**
5. In the PostgreSQL database dialog:
   - **Server:** 82.25.90.53
   - **Database:** breezeway
   - Click **Advanced options** and add this connection string parameter:
     ```
     sslmode=disable
     ```
   - Or leave Advanced options empty (server is configured to allow non-SSL connections for your user)
6. Click **OK**
7. Select **DirectQuery** or **Import** mode
8. When prompted for credentials:
   - Select **Database** authentication
   - **User name:** jaime
   - **Password:** vtR3VPfano2Egehz
9. Click **Connect**

**Note:** SSL is disabled for your connection to avoid certificate validation errors. The connection is still password-protected.

### Method 2: ODBC Connection

If you prefer ODBC:
1. Download PostgreSQL ODBC driver from: https://www.postgresql.org/ftp/odbc/versions/
2. Configure ODBC DSN with the credentials above
3. In Power BI: **Get Data** > **ODBC** > Select your DSN

---

## Access Permissions Summary

### What Jaime CAN Do:
- **SELECT (Read)** all tables across all schemas:
  - `public` schema
  - `breezeway` schema (18 tables: properties, tasks, reservations, etc.)
  - `analytics` schema
  - `api_integrations` schema
- **CREATE** new tables in the `jaime_workspace` schema
- **Full control** over tables created in `jaime_workspace`
- Run any SELECT queries and analysis

### What Jaime CANNOT Do:
- **ALTER** existing tables (cannot modify structure)
- **UPDATE/INSERT/DELETE** data in existing tables
- **DROP** existing tables
- **CREATE** tables outside of `jaime_workspace` schema
- Modify other users' permissions

---

## Available Schemas and Tables

### breezeway Schema (Main Operational Data)
- properties
- tasks
- task_assignments
- task_comments
- task_photos
- task_requirements
- task_tags
- reservations
- reservation_guests
- people
- supplies
- tags
- property_photos
- property_photos_backup
- regions
- api_tokens
- etl_sync_log

### api_integrations Schema
- listings

### analytics Schema
- (Currently empty - available for analytics tables)

### jaime_workspace Schema
- **Your personal workspace** - create any tables/views here

---

## Example Queries for Power BI

### Query All Properties
```sql
SELECT * FROM breezeway.properties;
```

### Query Tasks with Assignments
```sql
SELECT
    t.id,
    t.title,
    t.status,
    t.due_date,
    ta.assignee_id,
    p.name as assignee_name
FROM breezeway.tasks t
LEFT JOIN breezeway.task_assignments ta ON t.id = ta.task_id
LEFT JOIN breezeway.people p ON ta.assignee_id = p.id;
```

### Create Your Own Analysis Table
```sql
CREATE TABLE jaime_workspace.task_performance_metrics AS
SELECT
    DATE_TRUNC('month', completed_at) as month,
    COUNT(*) as tasks_completed,
    AVG(EXTRACT(EPOCH FROM (completed_at - created_at))/3600) as avg_hours_to_complete
FROM breezeway.tasks
WHERE completed_at IS NOT NULL
GROUP BY DATE_TRUNC('month', completed_at);
```

---

## Security Notes

1. **Password Security:** Store this password securely (use password manager). Do not share publicly.
2. **Network Access:** Connection is allowed from any IP. Ensure you're on a secure network.
3. **SSL/TLS:** SSL is disabled for your connection to avoid certificate validation issues. The connection is still password-protected with SCRAM-SHA-256 authentication. For additional security, consider connecting via VPN or SSH tunnel.
4. **Workspace Isolation:** Your `jaime_workspace` schema is private to you for development/staging tables.
5. **Read-Only Protection:** You cannot modify production data - only read it and create your own analysis tables.

---

## Troubleshooting

### SSL Certificate Error (FIXED)
If you get "remote certificate is invalid" error:
- **Solution 1:** In Power BI Advanced options, add: `sslmode=disable`
- **Solution 2:** Simply leave Advanced options empty - the server is configured to accept non-SSL connections for your user
- The server configuration has been updated to allow `hostnossl` connections for your account

### Cannot connect from Power BI
- Verify firewall allows outbound connections on port 5432
- Confirm server IP: 82.25.90.53
- Check credentials are entered exactly as shown
- Ensure you're using the correct port: 5432 (not 5433 or other)

### "Permission denied" errors
- You can only modify tables in `jaime_workspace` schema
- Use SELECT for existing tables
- Create new tables in `jaime_workspace` schema

### Need additional permissions?
- Contact the database administrator
- Specify which tables/schemas need additional access

---

## Connection Test (Command Line)

To test connection from command line:
```bash
# With password prompt
PGSSLMODE=disable psql -h 82.25.90.53 -U jaime -d breezeway
# Enter password when prompted: vtR3VPfano2Egehz

# Or with password in command (for scripts)
PGPASSWORD='vtR3VPfano2Egehz' PGSSLMODE=disable psql -h 82.25.90.53 -U jaime -d breezeway -c "SELECT COUNT(*) FROM breezeway.properties;"
```

---

**Created:** 2025-12-18
**Contact:** Database Administrator for questions or issues
