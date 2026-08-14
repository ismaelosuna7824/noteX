-- ============================================================================
-- Migration: schema v19 — nullable scheduled_date (backlog task support)
-- Target: Supabase / Postgres
-- Pairs with: local Drift schemaVersion 18 -> 19
-- ============================================================================
--
-- ORDERING IS A HARD REQUIREMENT.
-- Apply this BEFORE shipping any client build that can write a null
-- `scheduled_date` (a task with no date, living only in the backlog — see
-- design D5 / spec #561 "create a task with no schedule"). A client that
-- pushes null against a NOT NULL column does not degrade — the write fails
-- outright.
--
-- The whole script is wrapped in a transaction. The single ALTER statement
-- is naturally idempotent — dropping a constraint that is already absent is
-- a no-op in Postgres, not an error — so it is safe to re-run.
--
-- This migration relaxes a constraint; it does not add anything. Unlike
-- supabase_v18_task_tracker.sql, there is no `add column if not exists`
-- guard here because there is no new column, and no backfill because
-- existing rows already satisfy "not null" and need no rewriting.
-- ============================================================================

begin;

-- `scheduled_date` becomes nullable. NULL means the task has no date and
-- lives only in the backlog — never in the daily list. The local (Drift)
-- side enforces this exclusion structurally: a `<=` comparison against NULL
-- evaluates to NULL/false in SQL, so a backlog row can never satisfy the
-- "pending today" predicate without special-casing it. See design D5.
alter table public.reminders
  alter column scheduled_date drop not null;

commit;

-- ============================================================================
-- Verify after applying — expected results in comments
-- ============================================================================
--
-- 1. The column is now nullable (expect is_nullable = 'YES'):
--
-- select column_name, is_nullable
--   from information_schema.columns
--  where table_schema = 'public' and table_name = 'reminders'
--    and column_name = 'scheduled_date';
--
-- 2. No existing row was changed by this migration (expect 0 — this
--    statement only relaxes a constraint, it never rewrites data):
--
-- select count(*) from public.reminders where scheduled_date is null;
--
-- ============================================================================
-- Rollback
-- ============================================================================
--
-- CAVEAT: this is only safe if no row has been written with a null
-- `scheduled_date` since the migration was applied. Restoring NOT NULL
-- while any row is null fails outright, and there is no non-destructive way
-- to invent a date for a task the user deliberately left in the backlog —
-- picking one (e.g. `now()`) would silently pull it out of the backlog and
-- into the daily list, which is a data-meaning change, not a schema
-- rollback. Check first:
--
-- select count(*) from public.reminders where scheduled_date is null;
-- -- if this is not 0, resolve those rows (e.g. assign a date, or hold off
-- -- on rollback) before restoring the constraint.
--
-- begin;
--   alter table public.reminders
--     alter column scheduled_date set not null;
-- commit;
-- ============================================================================
