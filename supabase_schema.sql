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
  sync_status text not null default 'synced'
);

-- Enable Row Level Security (RLS) on all tables so users can only access their own data
alter table public.notes enable row level security;
alter table public.projects enable row level security;
alter table public.time_entries enable row level security;

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
