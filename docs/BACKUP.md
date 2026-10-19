# Backups and restore notes

## Policy

- Database backups are owned by Supabase (PITR/automated backups depend on the selected plan). Enable them in the project and periodically export a `pg_dump` from a trusted environment.
- Before each SQL migration, create a timestamped dump and record its checksum and storage location. Never put dumps, service-role keys, or `.env` in this repository.
- The Phase 2 migration creates one-time private snapshots before organization backfill at `private.upgrade_backup_*`; these are rollback aids, not a substitute for a full database backup.

## Restore

1. Restore a database dump into a separate recovery project first.
2. Verify organizations, memberships, cash closures, payroll movements, transactions, audit events, and third-party service dates.
3. Only after review, schedule a maintenance window and restore the intended production snapshot through Supabase-supported tooling.
4. Keep the current project intact until the restored instance is confirmed.

## Application

Preserve the previous deployment artifact before publishing. A frontend rollback does not undo applied SQL. SQL rollback scripts under `supabase/rollbacks/` intentionally avoid deleting production records; use a verified database restore for a full rollback.
