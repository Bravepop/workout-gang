-- Merge two names in a league into one (for someone who played under different names).
-- Run once in the SQL editor after schema.sql; schema.sql already includes it for new setups.

-- Everything of from_name's (seasons, points, final standings, login, admin role) moves to into_name,
-- then from_name is removed. Refused when both names played the same season, or both have joined.
create function public.wg_admin_merge_member(l uuid, from_name text, into_name text) returns void
language plpgsql security definer set search_path = public as $$
declare a wg_members; b wg_members; clash int;
begin
  perform wg_require_admin(l);
  if from_name = into_name then raise exception 'Pick two different names.' using errcode = 'P0001'; end if;
  select * into a from wg_members where league_id = l and name = from_name;
  select * into b from wg_members where league_id = l and name = into_name;
  if a.name is null or b.name is null then raise exception 'One of those names is gone. Refresh and try again.' using errcode = 'P0001'; end if;
  if a.user_id is not null and b.user_id is not null then
    raise exception '% and % have both joined with their own accounts. Remove one of them first (keeping their points), then merge.', from_name, into_name using errcode = 'P0001';
  end if;
  select s.num into clash from wg_roster r1 join wg_roster r2 on r2.season_id = r1.season_id and r2.member = into_name
    join wg_seasons s on s.id = r1.season_id
    where r1.league_id = l and r1.member = from_name order by s.num limit 1;
  if clash is not null then
    raise exception '% and % both played in Season %, so they can''t be merged.', from_name, into_name, clash using errcode = 'P0001';
  end if;
  update wg_roster set member = into_name where league_id = l and member = from_name;
  update wg_days set member = into_name where league_id = l and member = from_name;
  if a.user_id is not null then
    -- Hand over the admin role first, so the league never looks admin-less in between.
    if a.role = 'admin' then update wg_members set role = 'admin' where league_id = l and name = into_name; end if;
    update wg_members set user_id = null where league_id = l and name = from_name;
    update wg_members set user_id = a.user_id where league_id = l and name = into_name;
  end if;
  delete from wg_members where league_id = l and name = from_name;
end;
$$;
revoke execute on function public.wg_admin_merge_member(uuid, text, text) from public, anon;
grant execute on function public.wg_admin_merge_member(uuid, text, text) to authenticated;
