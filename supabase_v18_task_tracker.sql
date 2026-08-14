-- ============================================================================
-- Migration: schema v18 — task-tracker (Task absorbs Reminder)
-- Target: Supabase / Postgres
-- Pairs with: local Drift schemaVersion 17 -> 18
-- ============================================================================
--
-- ORDERING IS A HARD REQUIREMENT.
-- Apply this BEFORE shipping any client build that writes `status`. A client
-- that pushes a column the remote table does not have does not degrade — every
-- task push fails outright.
--
-- The whole script is wrapped in a transaction and every statement is
-- idempotent, so it is safe to re-run.
--
-- The physical table is deliberately still named `reminders`. Renaming it would
-- require a distributed migration against rows that older shipped clients are
-- still writing. Only the Dart symbols were renamed; the wire format did not
-- change. Do not "tidy" this later.
-- ============================================================================

begin;

-- ── reminders: task-tracker columns ─────────────────────────────────────────

-- `status` is the new source of truth for task state.
--
-- The DEFAULT is load-bearing, not cosmetic. PostgREST builds the INSERT column
-- list from the keys present in the payload, so a column omitted by an older
-- client is absent from the INSERT and Postgres applies the column DEFAULT.
-- Without `default 'todo'`, every task created on an older shipped build would
-- fail with a not-null violation.
alter table public.reminders
  add column if not exists status text not null default 'todo';

-- Recency marker for the status/is_completed compatibility gate.
-- Deliberately left NULL for pre-existing rows: NULL correctly means "no
-- v18-aware client has ever transitioned this task". Do NOT backfill it from
-- updated_at — that would invent a user decision that never happened.
alter table public.reminders
  add column if not exists status_changed_at timestamp with time zone;

-- Short-form Markdown body written on the task itself. Deep documentation lives
-- in the linked note (note_id below).
alter table public.reminders
  add column if not exists description text not null default '';

alter table public.reminders
  add column if not exists blocked_reason text;

-- Link to the task's primary documentation note.
--
-- NO FOREIGN KEY, deliberately. The app supports permanently deleting a note
-- (trash -> delete permanently). A real FK would let a task's optional link
-- veto a user emptying their own trash. The client resolves the link through
-- NoteRepository.getById and degrades the affordance when the note is in trash
-- or gone. Do not add `references public.notes(id)` here.
alter table public.reminders
  add column if not exists note_id uuid;

-- External reference seam (Jira / Notion). Present and synced, but unused:
-- integration itself is out of scope. These exist now so adding it later does
-- not require a migration against production rows.
alter table public.reminders
  add column if not exists external_provider text;
alter table public.reminders
  add column if not exists external_id text;
alter table public.reminders
  add column if not exists external_url text;
alter table public.reminders
  add column if not exists external_cached_title text;
alter table public.reminders
  add column if not exists external_last_synced_at timestamp with time zone;

-- NOTE: `status_pending_push` is intentionally ABSENT from this migration.
-- It is a local-only Drift column that records whether a pending write
-- originated from a status transition. It must never exist remotely, never be
-- pushed, and never be parsed on pull. Precedent: notes.is_ephemeral.

-- ── time_entries: link a tracked session to a task ──────────────────────────

-- No foreign key, for the same reason as note_id: a time entry must never be
-- able to block deleting a task. (Note that project_id on this table DOES carry
-- an FK — that is existing behavior and is not the pattern to copy here.)
alter table public.time_entries
  add column if not exists task_id uuid;

create index if not exists idx_time_entries_task_id
  on public.time_entries (task_id);

-- ── Backfill ────────────────────────────────────────────────────────────────

-- Derive `status` from the legacy `is_completed` boolean for existing rows.
--
-- This is REQUIRED, not optional. Without it every pre-existing completed task
-- sits remotely as status='todo' + is_completed=true, and the first v18 client
-- to pull them resolves against a state that says "not done". Completed tasks
-- would appear to reopen themselves.
--
-- Guarded on `status = 'todo'` (the column DEFAULT), not on `status is null`:
-- the column is NOT NULL, so an `is null` guard would match nothing and
-- silently do nothing. This form is idempotent — a row already moved to
-- 'doing' or 'blocked' no longer matches and is left alone.
update public.reminders
   set status = 'done'
 where is_completed = true
   and status = 'todo';

commit;

-- ============================================================================
-- Verify after applying — expected results in comments
-- ============================================================================
--
-- 1. Every column landed (expect 10 rows):
--
-- select column_name, data_type, is_nullable, column_default
--   from information_schema.columns
--  where table_schema = 'public' and table_name = 'reminders'
--    and column_name in ('status','status_changed_at','description',
--                        'blocked_reason','note_id','external_provider',
--                        'external_id','external_url','external_cached_title',
--                        'external_last_synced_at')
--  order by column_name;
--
-- 2. `status_pending_push` must NOT exist remotely (expect 0 rows):
--
-- select column_name from information_schema.columns
--  where table_schema = 'public' and table_name = 'reminders'
--    and column_name = 'status_pending_push';
--
-- 3. Backfill is consistent — no completed row left as 'todo' (expect 0):
--
-- select count(*) from public.reminders
--  where is_completed = true and status <> 'done';
--
-- 4. status_changed_at is still untouched for pre-existing rows (expect 0):
--
-- select count(*) from public.reminders where status_changed_at is not null;
--
-- 5. task_id landed on time_entries (expect 1 row):
--
-- select column_name, is_nullable from information_schema.columns
--  where table_schema = 'public' and table_name = 'time_entries'
--    and column_name = 'task_id';
--
-- ============================================================================
-- Rollback
-- ============================================================================
--
-- Dropping these columns loses any task state written since the migration.
-- Only do this if no v18 client has synced. There is no way to reconstruct
-- `status` for a task moved to 'doing' or 'blocked', because is_completed
-- cannot represent those states.
--
-- begin;
--   alter table public.time_entries drop column if exists task_id;
--   alter table public.reminders
--     drop column if exists status,
--     drop column if exists status_changed_at,
--     drop column if exists description,
--     drop column if exists blocked_reason,
--     drop column if exists note_id,
--     drop column if exists external_provider,
--     drop column if exists external_id,
--     drop column if exists external_url,
--     drop column if exists external_cached_title,
--     drop column if exists external_last_synced_at;
-- commit;
