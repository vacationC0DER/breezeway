-- ============================================================================
-- Migration 007: Add Task Comments Table
-- ============================================================================
-- Description: Creates table for storing task comments from Breezeway API
-- Endpoint: GET /task/{id}/comments
-- Date: 2025-11-04
-- ============================================================================

-- Create task_comments table
CREATE TABLE IF NOT EXISTS breezeway.task_comments (
    -- Primary key
    id BIGSERIAL PRIMARY KEY,

    -- Foreign keys
    task_pk BIGINT NOT NULL,
    region_code VARCHAR(32) NOT NULL,

    -- Comment data from API
    comment_id VARCHAR(64) NOT NULL,
    comment TEXT,
    author_name VARCHAR(255),
    author_id VARCHAR(64),
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,

    -- ETL tracking
    last_sync_time TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT fk_comment_task FOREIGN KEY (task_pk)
        REFERENCES breezeway.tasks(id) ON DELETE CASCADE,
    CONSTRAINT fk_comment_region FOREIGN KEY (region_code)
        REFERENCES breezeway.regions(region_code) ON DELETE CASCADE,
    CONSTRAINT uq_task_comment_natural_key UNIQUE (comment_id, region_code)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_task_comments_task_pk
    ON breezeway.task_comments(task_pk);
CREATE INDEX IF NOT EXISTS idx_task_comments_region
    ON breezeway.task_comments(region_code);
CREATE INDEX IF NOT EXISTS idx_task_comments_created_at
    ON breezeway.task_comments(created_at);
CREATE INDEX IF NOT EXISTS idx_task_comments_author
    ON breezeway.task_comments(author_id);

-- Add comment
COMMENT ON TABLE breezeway.task_comments IS 'Task comments from Breezeway API - GET /task/{id}/comments';
COMMENT ON COLUMN breezeway.task_comments.task_pk IS 'Foreign key to tasks.id';
COMMENT ON COLUMN breezeway.task_comments.comment_id IS 'Breezeway comment ID from API';
COMMENT ON COLUMN breezeway.task_comments.comment IS 'Comment text content';
COMMENT ON COLUMN breezeway.task_comments.author_name IS 'Name of comment author';
COMMENT ON COLUMN breezeway.task_comments.author_id IS 'Breezeway ID of comment author';

-- Grant permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON breezeway.task_comments TO breezeway;
GRANT USAGE, SELECT ON SEQUENCE breezeway.task_comments_id_seq TO breezeway;

-- Success message
DO $$
BEGIN
    RAISE NOTICE '✅ Migration 007 complete: task_comments table created';
END $$;
