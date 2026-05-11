-- =============================================================================
-- NPUPS / WorkForce — Edit-Lock Schema
-- =============================================================================
-- Short-lived collaborative locks that prevent two users from editing the same
-- record simultaneously. The Flutter client (lib/services/edit_lock_service.dart)
-- calls the REST endpoints listed below; a missed heartbeat causes the lock to
-- expire on its own so a crashed browser tab never leaves a record stuck.
--
-- Endpoint contract (implemented by the backend):
--   POST   /api/edit-locks/acquire           { entity_type, entity_id }
--                                            -> 200 lock on success
--                                            -> 409 lock if held by another user
--   POST   /api/edit-locks/{lock_id}/heartbeat
--                                            -> 204
--   DELETE /api/edit-locks/{lock_id}         -> 204 (holder only)
--   DELETE /api/edit-locks/{lock_id}/force   -> 204 (System Admin only)
--   GET    /api/edit-locks?entity_type=&entity_id=
--                                            -> { lock } or null
--
-- WebSocket / SSE: emit { kind: "lock_acquired"|"lock_released"|"lock_heartbeat", lock }
-- on /ws/edit-locks so connected clients keep their UI in sync.
--
-- Run order:   psql -f db/edit_locks_schema.sql   (after rbac_schema + domain_schema)
-- Target:      PostgreSQL 14+
-- Idempotent:  yes — uses DROP ... IF EXISTS at the top.
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

DROP TABLE IF EXISTS edit_locks_history CASCADE;
DROP TABLE IF EXISTS edit_locks         CASCADE;

-- -----------------------------------------------------------------------------
-- edit_locks
-- -----------------------------------------------------------------------------
-- One row per active lock. A unique constraint on (entity_type, entity_id)
-- ensures only one live lock per record. When the holder releases or the row
-- expires, it is moved to edit_locks_history (see trigger below).
-- -----------------------------------------------------------------------------
CREATE TABLE edit_locks (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),

    entity_type   TEXT        NOT NULL,
    entity_id     TEXT        NOT NULL,

    holder_id     TEXT        NOT NULL,           -- app_users.id (text, eg. USR-009)
    holder_name   TEXT        NOT NULL,
    holder_role   TEXT        NOT NULL,

    acquired_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at    TIMESTAMPTZ NOT NULL,           -- last heartbeat + TTL
    last_heartbeat_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- One live lock per record.
    CONSTRAINT edit_locks_unique_per_entity UNIQUE (entity_type, entity_id)
);

CREATE INDEX idx_edit_locks_holder       ON edit_locks (holder_id);
CREATE INDEX idx_edit_locks_expires_at   ON edit_locks (expires_at);
CREATE INDEX idx_edit_locks_entity       ON edit_locks (entity_type, entity_id);

COMMENT ON TABLE  edit_locks IS
    'Collaborative edit lock. Exactly one live row per (entity_type, entity_id).';
COMMENT ON COLUMN edit_locks.expires_at IS
    'Hard expiry. Backend cron / pre-acquire sweep deletes rows where expires_at < NOW().';

-- -----------------------------------------------------------------------------
-- edit_locks_history
-- -----------------------------------------------------------------------------
-- Append-only record of every released or expired lock. Useful when the audit
-- chain needs to answer "who held the lock between 14:02 and 14:08?".
-- -----------------------------------------------------------------------------
CREATE TABLE edit_locks_history (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    lock_id         UUID        NOT NULL,
    entity_type     TEXT        NOT NULL,
    entity_id       TEXT        NOT NULL,
    holder_id       TEXT        NOT NULL,
    holder_name     TEXT        NOT NULL,
    holder_role     TEXT        NOT NULL,
    acquired_at     TIMESTAMPTZ NOT NULL,
    released_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- 'released' = holder released cleanly
    -- 'expired'  = heartbeat timed out
    -- 'forced'   = System Admin force-released; the admin's id is recorded
    release_reason  TEXT        NOT NULL CHECK (release_reason IN ('released','expired','forced')),
    forced_by_id    TEXT,
    forced_by_name  TEXT
);

CREATE INDEX idx_edit_locks_history_entity   ON edit_locks_history (entity_type, entity_id);
CREATE INDEX idx_edit_locks_history_holder   ON edit_locks_history (holder_id);
CREATE INDEX idx_edit_locks_history_released ON edit_locks_history (released_at);

-- -----------------------------------------------------------------------------
-- Sweeper helpers
-- -----------------------------------------------------------------------------
-- Idempotent: callable from the backend's acquire path *and* from a cron job
-- once per minute. Moves expired rows into edit_locks_history.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION sweep_expired_edit_locks() RETURNS INT AS $$
DECLARE
    moved_count INT;
BEGIN
    WITH expired AS (
        DELETE FROM edit_locks
         WHERE expires_at < NOW()
        RETURNING *
    )
    INSERT INTO edit_locks_history (
        lock_id, entity_type, entity_id,
        holder_id, holder_name, holder_role,
        acquired_at, released_at, release_reason
    )
    SELECT id, entity_type, entity_id,
           holder_id, holder_name, holder_role,
           acquired_at, NOW(), 'expired'
      FROM expired;

    GET DIAGNOSTICS moved_count = ROW_COUNT;
    RETURN moved_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION sweep_expired_edit_locks() IS
    'Move every expired row from edit_locks into edit_locks_history. Safe to call concurrently.';

-- -----------------------------------------------------------------------------
-- View: lock_holder_summary
-- -----------------------------------------------------------------------------
-- Convenience view for the "who is editing X right now?" admin screen.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW lock_holder_summary AS
SELECT
    el.entity_type,
    el.entity_id,
    el.holder_id,
    el.holder_name,
    el.holder_role,
    el.acquired_at,
    el.expires_at,
    el.last_heartbeat_at,
    GREATEST(0, EXTRACT(EPOCH FROM (el.expires_at - NOW())))::INT AS seconds_remaining
  FROM edit_locks el
 WHERE el.expires_at > NOW();

COMMIT;
