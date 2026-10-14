-- Workout Gang: tables, access rules, league management and live updates.
-- Runs in the same Supabase project as Movie Club, so sign-in (Google and username accounts,
-- recovery codes) is shared. Every Workout Gang object is prefixed wg_ and touches nothing of Movie Club's.
-- Run once in the SQL editor.
--
-- Everything belongs to a league. Only a league's members can see or change anything in it.
-- Inside a league, members are identified by name; every key and reference carries the league id.

/* ---------------------------------------------------------------- tables */

create table public.wg_leagues (
  id           uuid primary key default gen_random_uuid(),
  slug         text not null unique check (slug ~ '^[a-z0-9-]{3,48}$'),
  name         text not null check (char_length(btrim(name)) between 1 and 60),
  invite_code  text not null unique default substr(replace(gen_random_uuid()::text, '-', ''), 1, 12),
  created_by   uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now()
);

-- A member is a name in a league. user_id links the name to a login; it is empty for a name the
-- admin added (or an old player from before the site) that nobody has claimed yet.
create table public.wg_members (
  league_id   uuid not null references public.wg_leagues (id) on delete cascade,
  name        text not null check (char_length(btrim(name)) between 1 and 30),
  user_id     uuid references auth.users (id) on delete set null,
  role        text not null default 'member' check (role in ('admin', 'member')),
  created_at  timestamptz not null default now(),
  primary key (league_id, name),
  unique (league_id, user_id)
);

-- A season: its scoring rules, teams and end-of-season awards.
--   scoring: steps  = 1 point per 10k steps (up to 3) + 3 for a workout
--            tiers  = walk 1, bodyweight 2, gym 3
--            manual = points typed in directly
--            legacy = only final standings are kept (roster.final_points)
--   teams:   [{"id": "red", "name": "Red Team", "color": "#d6453d"}, ...]
--   awards:  [{"title": "Most Points", "winner": "Jack"}, ...]
create table public.wg_seasons (
  id           uuid primary key default gen_random_uuid(),
  league_id    uuid not null references public.wg_leagues (id) on delete cascade,
  num          int not null check (num between 1 and 999),
  name         text not null check (char_length(btrim(name)) between 1 and 80),
  status       text not null default 'active' check (status in ('active', 'finished')),
  start_date   date,
  end_date     date check (end_date is null or start_date is null or end_date >= start_date),
  scoring      text not null default 'steps' check (scoring in ('steps', 'tiers', 'manual', 'legacy')),
  max_per_day  numeric(5,1) check (max_per_day is null or max_per_day > 0),
  goal         numeric(8,1) check (goal is null or goal > 0),
  rules        text check (char_length(rules) <= 4000),
  teams        jsonb not null default '[]' check (jsonb_typeof(teams) = 'array' and pg_column_size(teams) < 8000),
  awards       jsonb not null default '[]' check (jsonb_typeof(awards) = 'array' and pg_column_size(awards) < 16000),
  created_at   timestamptz not null default now()
);
create index on public.wg_seasons (league_id);

-- Who plays in a season, and on which team. final_points is only for legacy seasons.
create table public.wg_roster (
  season_id     uuid not null references public.wg_seasons (id) on delete cascade,
  league_id     uuid not null,
  member        text not null,
  team          text not null check (char_length(team) <= 40),
  position      int not null default 0,
  final_points  numeric(8,1),
  primary key (season_id, member),
  foreign key (league_id, member) references public.wg_members (league_id, name) on update cascade on delete cascade
);
create index on public.wg_roster (league_id);

-- One row per person per day. Clearing a day sets it to 0 rather than deleting the row, because live
-- updates can't deliver filtered deletes; pages treat 0 as an empty day.
-- detail keeps the calculator's breakdown ({"steps": 12500, "workout": true} or {"walk": true, "gym": true}).
create table public.wg_days (
  season_id   uuid not null references public.wg_seasons (id) on delete cascade,
  league_id   uuid not null,
  member      text not null,
  day         date not null,
  points      numeric(4,1) not null check (points >= 0 and points <= 100),
  detail      jsonb check (detail is null or pg_column_size(detail) < 500),
  updated_at  timestamptz not null default now(),
  primary key (season_id, member, day),
  foreign key (league_id, member) references public.wg_members (league_id, name) on update cascade on delete cascade
);
create index on public.wg_days (league_id);

/* ---------------------------------------------------------------- limits */

-- Keeps one person or league from filling up the shared free database.
create function public.wg_enforce_limits() returns trigger
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if tg_table_name = 'wg_leagues' then
    select count(*) into n from wg_leagues where created_by = new.created_by;
    if n >= 5 then raise exception 'You can start up to 5 leagues.' using errcode = 'P0001'; end if;
  elsif tg_table_name = 'wg_members' then
    if tg_op = 'INSERT' then
      select count(*) into n from wg_members where league_id = new.league_id;
      if n >= 60 then raise exception 'A league can have up to 60 members.' using errcode = 'P0001'; end if;
    end if;
    if new.user_id is not null and (tg_op = 'INSERT' or old.user_id is distinct from new.user_id) then
      select count(*) into n from wg_members where user_id = new.user_id;
      if n >= 20 then raise exception 'You can be in up to 20 leagues.' using errcode = 'P0001'; end if;
    end if;
  elsif tg_table_name = 'wg_seasons' then
    select count(*) into n from wg_seasons where league_id = new.league_id;
    if n >= 100 then raise exception 'A league can have up to 100 seasons.' using errcode = 'P0001'; end if;
  elsif tg_table_name = 'wg_days' then
    select count(*) into n from wg_days where season_id = new.season_id;
    if n >= 30000 then raise exception 'This season is full (30,000 logged days).' using errcode = 'P0001'; end if;
  end if;
  return new;
end;
$$;
create trigger wg_leagues_limit before insert on public.wg_leagues for each row execute function public.wg_enforce_limits();
create trigger wg_members_limit before insert or update of user_id on public.wg_members for each row execute function public.wg_enforce_limits();
create trigger wg_seasons_limit before insert on public.wg_seasons for each row execute function public.wg_enforce_limits();
create trigger wg_days_limit    before insert on public.wg_days    for each row execute function public.wg_enforce_limits();

/* ---------------------------------------------------------------- who am I */

create function public.wg_is_member(l uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from wg_members where league_id = l and user_id = auth.uid())
$$;
create function public.wg_is_admin(l uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from wg_members where league_id = l and user_id = auth.uid() and role = 'admin')
$$;
create function public.wg_my_name(l uuid) returns text
language sql stable security definer set search_path = public as $$
  select name from wg_members where league_id = l and user_id = auth.uid()
$$;
-- Can this person log points for `who` in this season? Members log their own days in a current,
-- day-by-day season they play in; admins can fix anyone's days in any day-by-day season.
create function public.wg_can_log(s uuid, l uuid, who text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from wg_seasons se join wg_roster r on r.season_id = se.id and r.member = who
    where se.id = s and se.league_id = l and se.scoring <> 'legacy'
      and (wg_is_admin(l) or (se.status = 'active' and who = wg_my_name(l)))
  )
$$;

/* ---------------------------------------------------------------- access rules */

alter table public.wg_leagues enable row level security;
alter table public.wg_members enable row level security;
alter table public.wg_seasons enable row level security;
alter table public.wg_roster  enable row level security;
alter table public.wg_days    enable row level security;

create policy "Members see their league" on public.wg_leagues for select to authenticated using (public.wg_is_member(id));
create policy "Members see members"      on public.wg_members for select to authenticated using (public.wg_is_member(league_id));
create policy "Members see seasons"      on public.wg_seasons for select to authenticated using (public.wg_is_member(league_id));
create policy "Members see rosters"      on public.wg_roster  for select to authenticated using (public.wg_is_member(league_id));
create policy "Members see days"         on public.wg_days    for select to authenticated using (public.wg_is_member(league_id));

-- Admins run seasons and rosters directly. League and member changes go through the functions below.
create policy "Admins add seasons"    on public.wg_seasons for insert to authenticated with check (public.wg_is_admin(league_id));
create policy "Admins edit seasons"   on public.wg_seasons for update to authenticated using (public.wg_is_admin(league_id)) with check (public.wg_is_admin(league_id));
create policy "Admins delete seasons" on public.wg_seasons for delete to authenticated using (public.wg_is_admin(league_id));
create policy "Admins add to rosters" on public.wg_roster for insert to authenticated
  with check (public.wg_is_admin(league_id) and exists (select 1 from public.wg_seasons s where s.id = season_id and s.league_id = wg_roster.league_id));
create policy "Admins edit rosters"   on public.wg_roster for update to authenticated using (public.wg_is_admin(league_id)) with check (public.wg_is_admin(league_id));
create policy "Admins trim rosters"   on public.wg_roster for delete to authenticated using (public.wg_is_admin(league_id));

-- Points: your own days in the current season; admins can fix anyone's.
create policy "Log points"    on public.wg_days for insert to authenticated with check (public.wg_can_log(season_id, league_id, member));
create policy "Change points" on public.wg_days for update to authenticated
  using (public.wg_can_log(season_id, league_id, member)) with check (public.wg_can_log(season_id, league_id, member));
create policy "Clear points"  on public.wg_days for delete to authenticated using (public.wg_can_log(season_id, league_id, member));

revoke all on public.wg_leagues, public.wg_members, public.wg_seasons, public.wg_roster, public.wg_days from anon;
grant select on public.wg_leagues, public.wg_members, public.wg_seasons, public.wg_roster, public.wg_days to authenticated;
grant insert, update, delete on public.wg_seasons, public.wg_roster, public.wg_days to authenticated;

-- Keep the stamp honest.
create function public.wg_touch() returns trigger
language plpgsql as $$ begin new.updated_at := now(); return new; end; $$;
create trigger wg_days_touch before update on public.wg_days for each row execute function public.wg_touch();

/* ---------------------------------------------------------------- always an admin */

-- A name that loses its login (someone leaves, is removed, or deletes their Bravepop account) stops
-- being an admin. If that leaves a league without an admin, whoever joined earliest takes over.
create function public.wg_unlink_role() returns trigger
language plpgsql as $$
begin
  if new.user_id is null then new.role := 'member'; end if;
  return new;
end;
$$;
create trigger wg_members_unlink before update of user_id on public.wg_members for each row execute function public.wg_unlink_role();

create function public.wg_keep_an_admin() returns trigger
language plpgsql security definer set search_path = public as $$
declare heir text;
begin
  if not exists (select 1 from wg_members where league_id = new.league_id and role = 'admin') then
    select name into heir from wg_members where league_id = new.league_id and user_id is not null order by created_at, name limit 1;
    if heir is not null then update wg_members set role = 'admin' where league_id = new.league_id and name = heir; end if;
  end if;
  return null;
end;
$$;
create trigger wg_members_keep_admin after update of user_id, role on public.wg_members for each row execute function public.wg_keep_an_admin();

/* ---------------------------------------------------------------- leagues: start and join */

create function public.wg_make_slug(n text) returns text
language sql volatile set search_path = public as $$
  select coalesce(nullif(left(trim(both '-' from regexp_replace(lower(n), '[^a-z0-9]+', '-', 'g')), 32), ''), 'league')
    || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6)
$$;

-- Start a league. The creator is its admin. Returns {id, slug}.
create function public.wg_create_league(league_name text, my_name text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l uuid; s text;
begin
  if auth.uid() is null then raise exception 'Sign in first.' using errcode = 'P0001'; end if;
  s := wg_make_slug(league_name);
  insert into wg_leagues (slug, name, created_by) values (s, btrim(league_name), auth.uid()) returning id into l;
  insert into wg_members (league_id, name, user_id, role) values (l, btrim(my_name), auth.uid(), 'admin');
  return jsonb_build_object('id', l, 'slug', s);
end;
$$;

-- What the invite page shows before joining: the league's name and the names nobody has claimed.
create function public.wg_invite_preview(code text)
returns table (league_name text, slug text, already_member boolean, open_names text[], member_count int)
language sql stable security definer set search_path = public as $$
  select l.name, l.slug,
         exists (select 1 from wg_members m where m.league_id = l.id and m.user_id = auth.uid()),
         coalesce(array(select m.name from wg_members m where m.league_id = l.id and m.user_id is null order by m.name), '{}'),
         (select count(*)::int from wg_members m where m.league_id = l.id)
  from wg_leagues l
  where l.invite_code = code and auth.uid() is not null
$$;

-- Join with an invite code, as a new name or by claiming a name already in the league (which keeps
-- its points). A league that has nobody signed in yet (an imported one) makes its first joiner admin.
create function public.wg_join_league(code text, as_name text) returns text
language plpgsql security definer set search_path = public as $$
declare l wg_leagues; claimed int; first_in boolean;
begin
  if auth.uid() is null then raise exception 'Sign in first.' using errcode = 'P0001'; end if;
  select * into l from wg_leagues where invite_code = code;
  if l.id is null then raise exception 'That invite link has expired. Ask the league for a new one.' using errcode = 'P0001'; end if;
  if exists (select 1 from wg_members where league_id = l.id and user_id = auth.uid()) then return l.slug; end if;
  first_in := not exists (select 1 from wg_members where league_id = l.id and user_id is not null);
  update wg_members set user_id = auth.uid() where league_id = l.id and name = btrim(as_name) and user_id is null;
  get diagnostics claimed = row_count;
  if claimed = 0 then
    if exists (select 1 from wg_members where league_id = l.id and lower(name) = lower(btrim(as_name))) then
      raise exception 'Someone in the league already has that name. Pick another.' using errcode = 'P0001';
    end if;
    insert into wg_members (league_id, name, user_id) values (l.id, btrim(as_name), auth.uid());
  end if;
  if first_in then update wg_members set role = 'admin' where league_id = l.id and user_id = auth.uid(); end if;
  return l.slug;
end;
$$;

-- Leave a league. Your name and points stay (unclaimed) so the league's history is intact.
-- The last admin has to hand over first, unless nobody else has joined, in which case the league is deleted.
create function public.wg_leave_league(l uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me wg_members;
begin
  select * into me from wg_members where league_id = l and user_id = auth.uid();
  if me.name is null then return; end if;
  if me.role = 'admin' and not exists (select 1 from wg_members where league_id = l and role = 'admin' and name <> me.name) then
    if exists (select 1 from wg_members where league_id = l and user_id is not null and name <> me.name) then
      raise exception 'Make someone else an admin before you leave.' using errcode = 'P0001';
    end if;
    delete from wg_leagues where id = l;
    return;
  end if;
  update wg_members set user_id = null where league_id = l and name = me.name;
end;
$$;

/* ---------------------------------------------------------------- admin tools */

create function public.wg_require_admin(l uuid) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not wg_is_admin(l) then raise exception 'Only league admins can do that.' using errcode = '42501'; end if;
end;
$$;

create function public.wg_admin_rename_league(l uuid, new_name text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform wg_require_admin(l);
  update wg_leagues set name = btrim(new_name) where id = l;
end;
$$;

create function public.wg_admin_invite_code(l uuid) returns text
language sql stable security definer set search_path = public as $$
  select invite_code from wg_leagues where id = l and wg_is_admin(l)
$$;

-- A new invite link; the old one stops working.
create function public.wg_admin_new_invite(l uuid) returns text
language plpgsql security definer set search_path = public as $$
declare code text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
begin
  perform wg_require_admin(l);
  update wg_leagues set invite_code = code where id = l;
  return code;
end;
$$;

-- Add a name for someone who hasn't joined yet; they claim it from the invite page.
create function public.wg_admin_add_member(l uuid, new_name text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform wg_require_admin(l);
  if exists (select 1 from wg_members where league_id = l and lower(name) = lower(btrim(new_name))) then
    raise exception 'Someone in the league already has that name.' using errcode = 'P0001';
  end if;
  insert into wg_members (league_id, name) values (l, btrim(new_name));
end;
$$;

-- Rename a member everywhere (rosters and points follow through the foreign keys).
create function public.wg_admin_rename_member(l uuid, old_name text, new_name text) returns void
language plpgsql security definer set search_path = public as $$
declare n text := btrim(new_name);
begin
  perform wg_require_admin(l);
  if lower(n) <> lower(old_name) and exists (select 1 from wg_members where league_id = l and lower(name) = lower(n)) then
    raise exception 'Someone in the league already has that name.' using errcode = 'P0001';
  end if;
  update wg_members set name = n where league_id = l and name = old_name;
end;
$$;

create function public.wg_admin_set_role(l uuid, who text, new_role text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform wg_require_admin(l);
  if new_role = 'member' and not exists (select 1 from wg_members where league_id = l and role = 'admin' and name <> who) then
    raise exception 'A league needs at least one admin.' using errcode = 'P0001';
  end if;
  if new_role = 'admin' and not exists (select 1 from wg_members where league_id = l and name = who and user_id is not null) then
    raise exception 'Only someone who has joined can be an admin.' using errcode = 'P0001';
  end if;
  update wg_members set role = new_role where league_id = l and name = who;
end;
$$;

-- Remove someone. keep_history = their name and points stay, unlinked from their login (it can be
-- claimed again from the invite page); otherwise everything of theirs goes.
create function public.wg_admin_remove_member(l uuid, who text, keep_history boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform wg_require_admin(l);
  if who = wg_my_name(l) then raise exception 'To remove yourself, leave the league instead.' using errcode = 'P0001'; end if;
  if keep_history then
    update wg_members set user_id = null where league_id = l and name = who;
  else
    delete from wg_members where league_id = l and name = who;
  end if;
end;
$$;

-- Delete the league and everything in it.
create function public.wg_admin_delete_league(l uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform wg_require_admin(l);
  delete from wg_leagues where id = l;
end;
$$;

/* ---------------------------------------------------------------- function permissions */

-- Internal helpers stay private; trigger functions are never called directly.
revoke execute on function public.wg_enforce_limits(), public.wg_touch(), public.wg_unlink_role(),
  public.wg_keep_an_admin(), public.wg_make_slug(text), public.wg_require_admin(uuid) from public, anon, authenticated;
revoke execute on function public.wg_is_member(uuid), public.wg_is_admin(uuid), public.wg_my_name(uuid),
  public.wg_can_log(uuid, uuid, text), public.wg_create_league(text, text), public.wg_invite_preview(text),
  public.wg_join_league(text, text), public.wg_leave_league(uuid), public.wg_admin_rename_league(uuid, text),
  public.wg_admin_invite_code(uuid), public.wg_admin_new_invite(uuid), public.wg_admin_add_member(uuid, text),
  public.wg_admin_rename_member(uuid, text, text), public.wg_admin_set_role(uuid, text, text),
  public.wg_admin_remove_member(uuid, text, boolean), public.wg_admin_delete_league(uuid) from public, anon;
grant execute on function public.wg_is_member(uuid), public.wg_is_admin(uuid), public.wg_my_name(uuid),
  public.wg_can_log(uuid, uuid, text), public.wg_create_league(text, text), public.wg_invite_preview(text),
  public.wg_join_league(text, text), public.wg_leave_league(uuid), public.wg_admin_rename_league(uuid, text),
  public.wg_admin_invite_code(uuid), public.wg_admin_new_invite(uuid), public.wg_admin_add_member(uuid, text),
  public.wg_admin_rename_member(uuid, text, text), public.wg_admin_set_role(uuid, text, text),
  public.wg_admin_remove_member(uuid, text, boolean), public.wg_admin_delete_league(uuid) to authenticated;

/* ---------------------------------------------------------------- live updates */

-- Open pages refresh when anything in their league changes. Realtime applies the access rules above,
-- so people only hear about their own leagues.
alter publication supabase_realtime add table
  public.wg_leagues, public.wg_members, public.wg_seasons, public.wg_roster, public.wg_days;
