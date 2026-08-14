-- ============================================================================
-- Pending remote migrations: v19, v20, v21 — apply in one pass
-- Target: Supabase / Postgres
-- ============================================================================
--
-- CONVENIENCE SCRIPT. It is exactly the contents of, in order:
--   supabase_v19_backlog_task.sql   (nullable scheduled_date — backlog)
--   supabase_v20_task_notes.sql     (note_ids — one task, many notes)
--   supabase_v21_task_project.sql   (project_id — task links to a timer project)
--
-- Those three files remain the per-version record and carry the full reasoning
-- for each statement. Read them if you want the why; run this if you just want
-- the remote schema caught up. Running this INSTEAD of them is fine — every
-- statement here is identical and idempotent. Running this AFTER any of them
-- is also fine, for the same reason.
--
-- v18 is NOT included: it was already applied and verified in production.
--
-- WHY THIS IS URGENT ONCE YOU SIGN IN.
-- The client already pushes `note_ids` on every task write, and will push
-- `project_id` too. A client pushing a column the remote table does not have
-- does not degrade — the push fails outright. While the app is signed out no
-- sync runs, so nothing is broken today. The moment you sign in without these
-- applied, no task syncs at all.
--
-- The whole script is one transaction: it either all lands or none of it does.
-- ============================================================================

begin;

-- ── v19 — scheduled_date becomes nullable (backlog tasks) ───────────────────
--
-- A null row is a task with no date, living in the backlog. Note that a null
-- scheduled_date can never satisfy the "pending today" predicate, because a
-- comparison against NULL evaluates to NULL rather than true — the backlog
-- stays out of the daily list without any special-casing.
alter table public.reminders
  alter column scheduled_date drop not null;

-- ── v20 — note_ids: one task, many notes ───────────────────────────────────
--
-- The DEFAULT is load-bearing, not cosmetic: PostgREST builds the INSERT
-- column list from the keys present in the payload, so a column omitted by a
-- client is absent from the INSERT and Postgres applies this default instead
-- of raising a not-null violation.
alter table public.reminders
  add column if not exists note_ids text not null default '[]';

-- Carry the single v18 `note_id` into the new list. `note_id` is DEPRECATED by
-- this migration but deliberately NOT dropped — dropping a column would be a
-- destructive change for a field this migration is still reading from.
--
-- `to_json(...)::text` does the quoting and escaping, so this is safe despite
-- being string concatenation.
--
-- Idempotent: guarded on `note_ids = '[]'`, so a row already migrated (or one
-- a client has since added a second note to) is left alone on a re-run.
update public.reminders
   set note_ids = '[' || to_json(note_id::text)::text || ']'
 where note_id is not null
   and note_ids = '[]';

-- ── v21 — project_id: a task belongs to a timer project ────────────────────
--
-- This one DOES carry a real foreign key, unlike note_id/note_ids/task_id, and
-- the asymmetry is deliberate rather than an oversight. Notes can be deleted
-- permanently from the trash, so an FK there would let a task's optional link
-- veto a user emptying their own trash. Projects are only ever soft-deleted —
-- `DeleteProjectUseCase` marks them deleted and the hard-delete path is
-- unreachable from the app — so the FK can never block a user action. It also
-- matches `time_entries.project_id`, which has always had one.
alter table public.reminders
  add column if not exists project_id uuid references public.projects(id);

commit;

-- ============================================================================
-- Verify after applying — expected results in comments
-- ============================================================================
--
-- 1. scheduled_date is nullable (expect is_nullable = YES):
--
-- select column_name, is_nullable from information_schema.columns
--  where table_schema = 'public' and table_name = 'reminders'
--    and column_name = 'scheduled_date';
--
-- 2. Both new columns landed (expect 2 rows; note_ids default '[]'::text,
--    project_id nullable):
--
-- select column_name, data_type, is_nullable, column_default
--   from information_schema.columns
--  where table_schema = 'public' and table_name = 'reminders'
--    and column_name in ('note_ids', 'project_id')
--  order by column_name;
--
-- 3. Every previously-linked note survived into the list (expect 0):
--
-- select count(*) from public.reminders
--  where note_id is not null and note_ids = '[]';
--
-- 4. No note_ids row is malformed — every value parses as a JSON array
--    (expect 0):
--
-- select count(*) from public.reminders
--  where json_typeof(note_ids::json) <> 'array';
--
-- 5. The project_id foreign key exists (expect 1 row, referencing projects):
--
-- select tc.constraint_name, ccu.table_name as references_table
--   from information_schema.table_constraints tc
--   join information_schema.constraint_column_usage ccu
--     on ccu.constraint_name = tc.constraint_name
--  where tc.table_name = 'reminders' and tc.constraint_type = 'FOREIGN KEY';
--
-- ============================================================================
-- Rollback
-- ============================================================================
--
-- Only safe while no v19+ client has synced. Dropping note_ids loses every
-- link beyond the first (note_id only ever held one). Restoring NOT NULL on
-- scheduled_date FAILS while any backlog task exists — give those a date or
-- delete them first.
--
-- begin;
--   alter table public.reminders drop column if exists project_id;
--   alter table public.reminders drop column if exists note_ids;
--   -- fails if any row has a null scheduled_date:
--   alter table public.reminders alter column scheduled_date set not null;
-- commit;
