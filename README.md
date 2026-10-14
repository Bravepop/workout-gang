# Workout Gang

A free site where friends run workout competitions: log your day, win weeks for your team, and end each season with awards and a Hall of Fame. Started as a Google Sheet; Seasons 1–7 of the original league are imported.

- **Site:** `index.html` + `config.js`, a static page served by GitHub Pages at `workoutgang.bravepop.app`.
- **Data and sign-in:** the same Supabase project as Movie Club. Workout Gang's tables and functions are all prefixed `wg_` (see `supabase/schema.sql`); the access rules keep each league visible only to its members.
- **Sign-in:** Google, or a username and password, shared with Movie Club. No emails are ever sent.

## How leagues work

- Anyone signed in can **start a league** (up to 5 each). They become its admin.
- The admin sends the league's **invite link** (gear icon → League settings). People sign in, open the link and join, either as a new name or by claiming a name already in the league (which keeps that name's past points). A league nobody has joined yet, such as the imported one, makes its first joiner admin.
- Someone who played under two names (the old spreadsheet had a few) can be merged: League settings → **Merge into…** on the extra name moves its seasons and points to the other.
- **Members** log their own days in the current season: steps + workout, walk / bodyweight / gym, or points typed in, depending on the season's scoring. **Admins** can fix anyone's days, and run seasons from the **Manage** tab: rules, scoring, teams, players, awards, starting and finishing seasons.
- Tabs: Scoreboard (team score and personal leaderboard), Log a day, Sheet (the old spreadsheet grid), Weekly (team points and MVP per week), Hall of Fame.

Limits that keep the shared free database comfortable: 60 members per league, 20 leagues per person, 100 seasons per league, 30,000 logged days per season.

## One-time setup

All of this happens in the existing Movie Club accounts; there's no new Supabase project or Google Cloud project.

1. **Database.** Supabase → Movie Club's project → **SQL Editor → New query**: paste all of `supabase/schema.sql` and click **Run**.
2. **Import the original league** (once): run `private/league-import.sql` the same way. The last line prints the invite code. The file isn't in git (it holds everyone's history); rebuild it with `python tools/make_import.py private/spreadsheet-export.json > private/league-import.sql` if needed.
3. **Sign-in addresses.** Supabase → **Authentication → URL Configuration → Redirect URLs**: add `https://workoutgang.bravepop.app/**` and `http://127.0.0.1:5192/**` (local testing). Leave the Site URL as Movie Club's.
4. **Publish.** Push this folder to the `Bravepop/workout-gang` GitHub repo and turn on **Settings → Pages** (deploy from `main`, root folder). The `CNAME` file sets the custom domain.
5. **Domain.** Cloudflare DNS for `bravepop.app`: add a `CNAME` record `workoutgang` → `bravepop.github.io` (DNS only, grey cloud). Then tick **Enforce HTTPS** in the repo's Pages settings once GitHub has issued the certificate.
6. **Contact address.** Cloudflare → Email Routing: forward `workoutgang@bravepop.app` (listed on the privacy page) to your inbox.

## Running it

**The site says the database is unreachable.** Free Supabase projects pause after a week with no visits. Open the Supabase dashboard and click **Restore project** (visits to Movie Club or Workout Gang both keep it awake).

**Local testing:** `python -m http.server 5192 --bind 127.0.0.1`, then open `http://127.0.0.1:5192/`.

**Icons and link preview** are drawn by `tools/make_icons.py`.
