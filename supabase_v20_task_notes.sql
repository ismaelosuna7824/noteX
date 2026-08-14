-- ============================================================================
-- Migration: schema v20 — task-to-notes becomes one-to-many (`note_ids`)
-- Target: Supabase / Postgres
-- Pairs with: local Drift schemaVersion 19 -> 20
-- ============================================================================
--
-- FOR HUMAN REVIEW. NOT APPLIED. This script has not been run against any
-- Supabase environment and this file does not claim otherwise — see
-- supabase_schema.sql, which was previously (incorrectly) marked as already
-- applied for a different migration; that mistake is not repeated here.
--
-- ORDERING IS A HARD REQUIREMENT, same shape as v18/v19.
-- Apply this BEFORE shipping any client build that pushes `note_ids`. A
-- client that pushes a column the remote table does not have does not
-- degrade — the write fails outright.
--
-- Corrects a design error, not a missing feature (decision
-- architecture/task-note-linking-model): a task links to N notes — its
-- accumulating "mini documentation" — not one. `note_id` (v18) modelled a
-- single nullable link; every downstream phase implemented that faithfully
-- before the user caught it. This migration supersedes it with a JSON-array
-- text column, deliberately NOT a join table — it travels the same sync
-- path every other task field already uses, instead of introducing a new
-- synced entity with its own push/pull/merge rules, in the layer that
-- produced this project's two known pre-existing sync defects (dead
-- `incrementVersion()`, the full-row clobber in `supabase_sync_adapter.dart`).
--
-- NO BACKWARD-COMPATIBILITY BURDEN: `feat/task-tracker` (and therefore
-- `note_id`, `status`, and every other v18/v19 column) has never shipped in
-- a released build — this branch is unmerged. No released client reads or
-- writes `note_id`, so there is no dual-write and nothing to protect here.
--
-- The whole script is wrapped in a transaction and every statement is
-- idempotent, so it is safe to re-run.
-- ============================================================================

begin;

-- `note_ids` — JSON array of note ids, encoded as text (the same shape the
-- local Drift column and TaskSupabaseMapper use — see
-- `lib/domain/entities/task.dart` and `lib/infrastructure/supabase/
-- task_supabase_mapper.dart`). Deliberately `text`, not `jsonb`: this
-- column is never queried by shape on the server side ("which tasks link
-- to this note" is an accepted-as-a-scan concern, not in scope here), so
-- there is no benefit to jsonb's parsed storage, only added type surface.
--
-- NOT NULL with a `'[]'` default so a client omitting the key (an older,
-- pre-v20 unreleased build) gets "no links" from the column DEFAULT rather
-- than a not-null violation — same load-bearing-DEFAULT reasoning as
-- `status` in supabase_v18_task_tracker.sql.
alter table public.reminders
  add column if not exists note_ids text not null default '[]';

-- `note_id` (v18) is DEPRECATED by this migration, not dropped. Dropping it
-- would need a full column rewrite for no benefit — the local side keeps it
-- for the exact same reason (SQLite has no cheap `DROP COLUMN` history here
-- either). It is simply no longer read or written by any client from v20
-- onward.

-- ── Backfill ────────────────────────────────────────────────────────────────
--
-- Seeds `note_ids` from the deprecated `note_id` for any row that already
-- has a single link, so an existing link is not silently lost the first
-- time a v20 client pulls that row. Guarded on `note_ids = '[]'` (the
-- column DEFAULT), not `note_ids is null` — the column is NOT NULL, so an
-- `is null` guard would silently match nothing. This form is idempotent: a
-- row already backfilled (or one a client has already written real links
-- to) no longer matches `= '[]'` and is left alone on re-run.
--
-- `to_json(note_id::text)` produces a correctly quoted/escaped JSON string
-- (e.g. `"550e8400-e29b-41d4-a716-446655440000"`); wrapping it in `[...]`
-- is therefore safe even though this is plain string concatenation, unlike
-- building the array by hand from an un-escaped value.
update public.reminders
   set note_ids = '[' || to_json(note_id::text)::text || ']'
 where note_id is not null
   and note_ids = '[]';

commit;

-- ============================================================================
-- Verify after applying — expected results in comments
-- ============================================================================
--
-- 1. The column landed (expect 1 row, is_nullable = 'NO', column_default =
--    '''[]''::text'):
--
-- select column_name, data_type, is_nullable, column_default
--   from information_schema.columns
--  where table_schema = 'public' and table_name = 'reminders'
--    and column_name = 'note_ids';
--
-- 2. Every row with a legacy `note_id` was backfilled (expect 0 — no row
--    left with a real note_id but an empty note_ids array):
--
-- select count(*) from public.reminders
--  where note_id is not null and note_ids = '[]';
--
-- 3. No existing row's `note_ids` is malformed JSON (expect 0):
--
-- select count(*) from public.reminders
--  where note_ids is not null and note_ids::jsonb is null;
-- -- (the cast itself throws on malformed JSON rather than returning a row,
-- -- so a non-error result from this query is itself the check)
--
-- ============================================================================
-- Rollback
-- ============================================================================
--
-- CAVEAT: dropping `note_ids` loses any SECOND+ link a task has accumulated
-- since this migration — the deprecated `note_id` column only ever held the
-- first one, and was never updated after v20 clients stopped writing it.
-- This is cheaper than the v18/v19 rollbacks (there is no way to reconstruct
-- `status`), but it is still a real, one-directional data loss for any task
-- linked to more than one note post-migration. Check first:
--
-- select count(*) from public.reminders
--  where jsonb_array_length(note_ids::jsonb) > 1;
-- -- if this is not 0, export those tasks' note_ids before rolling back —
-- -- there is no way to recover them from note_id afterward.
--
-- begin;
--   alter table public.reminders drop column if exists note_ids;
-- commit;
-- ============================================================================
