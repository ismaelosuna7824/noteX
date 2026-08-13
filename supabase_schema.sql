-- Create the `notes` table
create table public.notes (
  id uuid primary key,
  user_id uuid references auth.users not null,
  title text not null default '',
  content text not null default '[]',
  background_image text,
  theme_id text,
  is_pinned boolean not null default false,
  created_at timestamp with time zone not null,
  updated_at timestamp with time zone not null,
  deleted_at timestamp with time zone,
  version integer not null default 1,
  sync_status text not null default 'synced'
);

-- Create the `projects` table
create table public.projects (
  id uuid primary key,
  user_id uuid references auth.users not null,
  name text not null,
  color_value bigint not null,
  created_at timestamp with time zone not null,
  updated_at timestamp with time zone not null,
  deleted_at timestamp with time zone,
  version integer not null default 1,
  sync_status text not null default 'synced'
);

-- Create the `time_entries` table
create table public.time_entries (
  id uuid primary key,
  user_id uuid references auth.users not null,
  description text not null default '',
  project_id uuid references public.projects(id),
  start_time timestamp with time zone not null,
  end_time timestamp with time zone,
  created_at timestamp with time zone not null,
  updated_at timestamp with time zone not null,
  deleted_at timestamp with time zone,
  version integer not null default 1,
  sync_status text not null default 'synced',
  -- v18 (task-tracker). No foreign key on purpose: a tracked session must never
  -- be able to block deleting the task it points at.
  task_id uuid
);

-- Create the `note_projects` table
create table public.note_projects (
  id uuid primary key,
  user_id uuid references auth.users not null,
  name text not null,
  color_value bigint not null,
  created_at timestamp with time zone not null,
  updated_at timestamp with time zone not null,
  deleted_at timestamp with time zone,
  version integer not null default 1,
  sync_status text not null default 'synced'
);

-- Add project_id to notes (must be after note_projects is created)
alter table public.notes add column project_id uuid references public.note_projects(id);

-- Create the `markdown_projects` table
create table public.markdown_projects (
  id uuid primary key,
  user_id uuid references auth.users not null,
  name text not null,
  color_value bigint not null,
  created_at timestamp with time zone not null,
  updated_at timestamp with time zone not null,
  deleted_at timestamp with time zone,
  version integer not null default 1,
  sync_status text not null default 'synced'
);

-- Create the `markdown_files` table
create table public.markdown_files (
  id uuid primary key,
  user_id uuid references auth.users not null,
  title text not null default '',
  content text not null default '',
  project_id uuid references public.markdown_projects(id) on delete cascade,
  created_at timestamp with time zone not null,
  updated_at timestamp with time zone not null,
  deleted_at timestamp with time zone,
  version integer not null default 1,
  sync_status text not null default 'synced'
);

-- Enable Row Level Security (RLS) on all tables so users can only access their own data
alter table public.notes enable row level security;
alter table public.projects enable row level security;
alter table public.time_entries enable row level security;
alter table public.note_projects enable row level security;
alter table public.markdown_projects enable row level security;
alter table public.markdown_files enable row level security;

-- Create Policies for `notes`
create policy "Users can view their own notes" on public.notes for select using (auth.uid() = user_id);
create policy "Users can insert their own notes" on public.notes for insert with check (auth.uid() = user_id);
create policy "Users can update their own notes" on public.notes for update using (auth.uid() = user_id);
create policy "Users can delete their own notes" on public.notes for delete using (auth.uid() = user_id);

-- Create Policies for `projects`
create policy "Users can view their own projects" on public.projects for select using (auth.uid() = user_id);
create policy "Users can insert their own projects" on public.projects for insert with check (auth.uid() = user_id);
create policy "Users can update their own projects" on public.projects for update using (auth.uid() = user_id);
create policy "Users can delete their own projects" on public.projects for delete using (auth.uid() = user_id);

-- Create Policies for `time_entries`
create policy "Users can view their own time entries" on public.time_entries for select using (auth.uid() = user_id);
create policy "Users can insert their own time entries" on public.time_entries for insert with check (auth.uid() = user_id);
create policy "Users can update their own time entries" on public.time_entries for update using (auth.uid() = user_id);
create policy "Users can delete their own time entries" on public.time_entries for delete using (auth.uid() = user_id);

-- Create Policies for `note_projects`
create policy "Users can view their own note projects" on public.note_projects for select using (auth.uid() = user_id);
create policy "Users can insert their own note projects" on public.note_projects for insert with check (auth.uid() = user_id);
create policy "Users can update their own note projects" on public.note_projects for update using (auth.uid() = user_id);
create policy "Users can delete their own note projects" on public.note_projects for delete using (auth.uid() = user_id);

-- Create Policies for `markdown_projects`
create policy "Users can view their own markdown projects" on public.markdown_projects for select using (auth.uid() = user_id);
create policy "Users can insert their own markdown projects" on public.markdown_projects for insert with check (auth.uid() = user_id);
create policy "Users can update their own markdown projects" on public.markdown_projects for update using (auth.uid() = user_id);
create policy "Users can delete their own markdown projects" on public.markdown_projects for delete using (auth.uid() = user_id);

-- Create Policies for `markdown_files`
create policy "Users can view their own markdown files" on public.markdown_files for select using (auth.uid() = user_id);
create policy "Users can insert their own markdown files" on public.markdown_files for insert with check (auth.uid() = user_id);
create policy "Users can update their own markdown files" on public.markdown_files for update using (auth.uid() = user_id);
create policy "Users can delete their own markdown files" on public.markdown_files for delete using (auth.uid() = user_id);


-- ── Indexes ──────────────────────────────────────────────────────────────────
-- user_id: required by RLS on every query
-- (user_id, updated_at): sync pull filters by updated_at > since
-- project_id: FK lookups when filtering by project

-- notes
create index idx_notes_user_id on public.notes (user_id);
create index idx_notes_user_updated on public.notes (user_id, updated_at);
create index idx_notes_project_id on public.notes (project_id);

-- note_projects
create index idx_note_projects_user_id on public.note_projects (user_id);
create index idx_note_projects_user_updated on public.note_projects (user_id, updated_at);

-- projects
create index idx_projects_user_id on public.projects (user_id);
create index idx_projects_user_updated on public.projects (user_id, updated_at);

-- time_entries
create index idx_time_entries_user_id on public.time_entries (user_id);
create index idx_time_entries_user_updated on public.time_entries (user_id, updated_at);
create index idx_time_entries_project_id on public.time_entries (project_id);
create index idx_time_entries_task_id on public.time_entries (task_id);

-- markdown_projects
create index idx_markdown_projects_user_id on public.markdown_projects (user_id);
create index idx_markdown_projects_user_updated on public.markdown_projects (user_id, updated_at);

-- markdown_files
create index idx_markdown_files_user_id on public.markdown_files (user_id);
create index idx_markdown_files_user_updated on public.markdown_files (user_id, updated_at);
create index idx_markdown_files_project_id on public.markdown_files (project_id);

-- ── Reminders ────────────────────────────────────────────────────────────────

-- Create the `reminders` table
create table public.reminders (
  id uuid primary key,
  user_id uuid references auth.users not null,
  title text not null default '',
  -- v19: relaxed from NOT NULL. A null row is a backlog task with no date.
  -- Apply via supabase_v19_backlog_task.sql — this file describes the TARGET
  -- schema and does not record whether a given environment has been migrated.
  -- Until the relaxation is applied, pushing a backlog task fails outright.
  scheduled_date timestamp with time zone,
  is_completed boolean not null default false,
  completed_at timestamp with time zone,
  created_at timestamp with time zone not null,
  updated_at timestamp with time zone not null,
  deleted_at timestamp with time zone,
  version integer not null default 1,
  sync_status text not null default 'synced',
  -- v18 (task-tracker). `status` is the source of truth for task state;
  -- `is_completed` above is kept as a derived, deprecated column so older
  -- shipped clients keep working. The 'todo' default is load-bearing: an older
  -- client omits `status` from its payload, so Postgres applies this default
  -- instead of rejecting the insert. `note_id` deliberately carries no foreign
  -- key, so permanently deleting a note is never blocked by a task linking to
  -- it. The local-only `status_pending_push` column has no counterpart here by
  -- design. See supabase_v18_task_tracker.sql.
  status text not null default 'todo',
  status_changed_at timestamp with time zone,
  description text not null default '',
  blocked_reason text,
  -- v18. DEPRECATED as of v20 — superseded by `note_ids` below, which
  -- corrects a design error: a task links to N notes, not one (decision
  -- architecture/task-note-linking-model). Kept, unused, rather than
  -- dropped — dropping it buys nothing and the local side keeps its own
  -- deprecated `note_id` column for the same reason. Not read or written
  -- by any v20+ client.
  note_id uuid,
  -- v20. A task's links to zero or more notes, JSON-encoded as text — the
  -- same shape the local Drift `noteIds` column and `TaskSupabaseMapper`
  -- use. NOT NULL / `'[]'` default for the same load-bearing-DEFAULT
  -- reason as `status` above. Apply via supabase_v20_task_notes.sql — THIS
  -- FILE DESCRIBES THE TARGET SCHEMA ONLY and does not record whether any
  -- environment has actually been migrated. Until the migration is
  -- applied, pushing `note_ids` fails outright.
  note_ids text not null default '[]',
  external_provider text,
  external_id text,
  external_url text,
  external_cached_title text,
  external_last_synced_at timestamp with time zone,
  -- v21. Links a task to one of the timer feature's projects — tracked
  -- time started from a task inherits it. Real foreign key (unlike
  -- note_id/note_ids): a project is only ever soft-deleted, never
  -- permanently removed, so this can never block a user's own delete
  -- action, matching `time_entries.project_id`'s existing convention. Apply
  -- via supabase_v21_task_project.sql — THIS FILE DESCRIBES THE TARGET
  -- SCHEMA ONLY and does not record whether any environment has actually
  -- been migrated. Until the migration is applied, pushing `project_id`
  -- fails outright.
  project_id uuid references public.projects(id)
);

-- Enable RLS
alter table public.reminders enable row level security;

-- RLS Policies
create policy "Users can view their own reminders" on public.reminders for select using (auth.uid() = user_id);
create policy "Users can insert their own reminders" on public.reminders for insert with check (auth.uid() = user_id);
create policy "Users can update their own reminders" on public.reminders for update using (auth.uid() = user_id);
create policy "Users can delete their own reminders" on public.reminders for delete using (auth.uid() = user_id);

-- Indexes
create index idx_reminders_user_id on public.reminders (user_id);
create index idx_reminders_user_updated on public.reminders (user_id, updated_at);
