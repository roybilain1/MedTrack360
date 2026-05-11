BEGIN;

DROP INDEX IF EXISTS idx_audit_change_log_request;
DROP INDEX IF EXISTS idx_audit_change_log_entity;
DROP INDEX IF EXISTS idx_audit_change_log_pharmacy_created;
DROP TABLE IF EXISTS audit_change_log;

COMMIT;
