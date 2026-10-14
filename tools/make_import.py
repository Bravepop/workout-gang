"""Builds private/league-import.sql from the spreadsheet export (seed_local.json).

Usage: python tools/make_import.py <seed_local.json> > private/league-import.sql
"""
import json, sys, uuid

seed = json.load(open(sys.argv[1], encoding="utf-8"))
q = lambda s: "null" if s is None else "'" + str(s).replace("'", "''") + "'"
num = lambda n: "null" if n is None else repr(float(n)).rstrip("0").rstrip(".")
league = str(uuid.uuid4())
out = ["-- Imports the original Workout Gang spreadsheet (Seasons 1-7) as one league.",
       "-- Run once in the Supabase SQL editor, after supabase/schema.sql. Nobody is signed in to it yet:",
       "-- the first person to open the invite link (shown at the end) becomes its admin.",
       "begin;",
       f"insert into wg_leagues (id, slug, name) values ('{league}', 'workout-gang-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6), 'Workout Gang');"]

seasons = sorted(seed["seasons"].items(), key=lambda kv: kv[1]["num"])
names = []
for _, s in seasons:
    for p in s["players"]:
        if p["name"] not in names:
            names.append(p["name"])
out.append("insert into wg_members (league_id, name) values\n  " + ",\n  ".join(f"('{league}', {q(n)})" for n in names) + ";")

for key, s in seasons:
    sid = str(uuid.uuid4())
    status = "active" if s["status"] == "active" else "finished"
    out.append(
        "insert into wg_seasons (id, league_id, num, name, status, start_date, end_date, scoring, max_per_day, goal, rules, teams, awards) values ("
        f"'{sid}', '{league}', {s['num']}, {q(s['name'])}, '{status}', {q(s.get('start'))}, {q(s.get('end'))}, '{s['scoring']}', "
        f"{num(s.get('maxPerDay'))}, {num(s.get('goal'))}, {q(s.get('rules'))}, {q(json.dumps(s['teams']))}::jsonb, {q(json.dumps(s.get('awards', [])))}::jsonb);")
    legacy = s.get("legacyPoints") or {}
    rows = [f"('{sid}', '{league}', {q(p['name'])}, {q(p['team'])}, {i}, {num(legacy.get(p['id'])) if s['scoring'] == 'legacy' else 'null'})"
            for i, p in enumerate(s["players"])]
    out.append("insert into wg_roster (season_id, league_id, member, team, position, final_points) values\n  " + ",\n  ".join(rows) + ";")
    days = []
    for p in s["players"]:
        e = seed["entries"].get(f"{key}__{p['id']}")
        for d, v in sorted((e or {}).get("days", {}).items()):
            days.append(f"('{sid}', '{league}', {q(p['name'])}, '{d}', {num(v)})")
    if days:
        out.append("insert into wg_days (season_id, league_id, member, day, points) values\n  " + ",\n  ".join(days) + ";")

out.append("commit;")
out.append(f"-- The invite link is https://workoutgang.bravepop.app/?join=<invite_code>\nselect slug, invite_code from wg_leagues where id = '{league}';")
sys.stdout.reconfigure(encoding="utf-8")
print("\n".join(out))
