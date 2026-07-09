-- ============================================================
-- MVerse — Supabase Database Schema
-- Run this entire file in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- ── PROFILES (one row per user, created automatically on signup) ──────────
create table if not exists public.profiles (
  id          uuid references auth.users on delete cascade primary key,
  username    text unique not null,
  avatar      text default '🎮',
  created_at  timestamptz default now()
);

-- ── GAME SAVES (3 slots per game per user) ────────────────────────────────
create table if not exists public.game_saves (
  id           uuid default gen_random_uuid() primary key,
  user_id      uuid references auth.users on delete cascade not null,
  game_id      integer not null,
  slot         integer not null default 0 check (slot between 0 and 2),
  score        integer default 0,
  level        integer default 1,
  play_time_ms bigint  default 0,
  extra_data   jsonb   default '{}'::jsonb,
  saved_at     timestamptz default now(),
  unique (user_id, game_id, slot)
);

-- ── GAME HISTORY (every session visit) ───────────────────────────────────
create table if not exists public.game_history (
  id         uuid default gen_random_uuid() primary key,
  user_id    uuid references auth.users on delete cascade not null,
  game_id    integer not null,
  played_at  timestamptz default now(),
  score      integer default 0,
  level      integer default 1,
  duration_ms bigint default 0
);

-- ── FAVORITES ─────────────────────────────────────────────────────────────
create table if not exists public.favorites (
  id         uuid default gen_random_uuid() primary key,
  user_id    uuid references auth.users on delete cascade not null,
  game_id    integer not null,
  created_at timestamptz default now(),
  unique (user_id, game_id)
);

-- ── REVIEWS ───────────────────────────────────────────────────────────────
create table if not exists public.reviews (
  id         uuid default gen_random_uuid() primary key,
  user_id    uuid references auth.users on delete cascade not null,
  game_id    integer not null,
  rating     integer not null check (rating between 1 and 5),
  body       text not null,
  helpful    integer default 0,
  created_at timestamptz default now(),
  unique (user_id, game_id)
);

-- ── COMMENTS ──────────────────────────────────────────────────────────────
create table if not exists public.comments (
  id         uuid default gen_random_uuid() primary key,
  user_id    uuid references auth.users on delete cascade not null,
  game_id    integer not null,
  parent_id  uuid references public.comments(id) on delete cascade,
  body       text not null,
  likes      integer default 0,
  created_at timestamptz default now()
);

-- ============================================================
-- ROW LEVEL SECURITY — users only touch their own data
-- ============================================================
alter table public.profiles     enable row level security;
alter table public.game_saves   enable row level security;
alter table public.game_history enable row level security;
alter table public.favorites    enable row level security;
alter table public.reviews      enable row level security;
alter table public.comments     enable row level security;

-- profiles
create policy "profiles: own read"   on public.profiles for select using (auth.uid() = id);
create policy "profiles: own insert" on public.profiles for insert with check (auth.uid() = id);
create policy "profiles: own update" on public.profiles for update using (auth.uid() = id);

-- game_saves
create policy "saves: own all" on public.game_saves for all using (auth.uid() = user_id);

-- game_history
create policy "history: own all" on public.game_history for all using (auth.uid() = user_id);

-- favorites
create policy "favs: own all" on public.favorites for all using (auth.uid() = user_id);

-- reviews (anyone can read, own user can write)
create policy "reviews: public read"  on public.reviews for select using (true);
create policy "reviews: own write"    on public.reviews for insert with check (auth.uid() = user_id);
create policy "reviews: own update"   on public.reviews for update using (auth.uid() = user_id);
create policy "reviews: own delete"   on public.reviews for delete using (auth.uid() = user_id);

-- comments (anyone can read, own user can write)
create policy "comments: public read" on public.comments for select using (true);
create policy "comments: own write"   on public.comments for insert with check (auth.uid() = user_id);
create policy "comments: own delete"  on public.comments for delete using (auth.uid() = user_id);

-- ============================================================
-- TRIGGER — auto-create profile row when a user signs up
-- ============================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username, avatar)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
    coalesce(new.raw_user_meta_data->>'avatar', '🎮')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============================================================
-- INDEXES for fast queries
-- ============================================================
create index if not exists idx_saves_user_game   on public.game_saves   (user_id, game_id);
create index if not exists idx_history_user       on public.game_history (user_id, played_at desc);
create index if not exists idx_favs_user          on public.favorites    (user_id);
create index if not exists idx_reviews_game       on public.reviews      (game_id);
create index if not exists idx_comments_game      on public.comments     (game_id, created_at desc);

-- Done! All tables, policies, trigger and indexes are set up.
