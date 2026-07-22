# MED-EL CI Service Pool — Middle East

Tracks loaner/service-pool audio processors across the nine Middle East branches:
stock on hand, replacements given to patients, units sent to Austria for service,
and **shortage events** — so you can see which model runs out, in which country,
and at what time of year.

**Countries:** KSA · Egypt · UAE · Qatar · Bahrain · Lebanon · Kuwait · Sudan · Syria
**Devices:** SONNET 1/2/3 · RONDO 1/2/3 · OPUS 2 · DL Base Part · SAMBA 2 · ADHEAR

## Project structure

```
public/
  index.html           full SPA (no build step)
backend/
  package.json         Node.js scheduled jobs for Render
  server.js            shortage alerts, service delay checks, monthly reports
supabase/
  schema.sql           full database schema, RLS, triggers, views
firebase.json          Firebase Hosting config
.env.example           environment variable template
.gitignore
README.md
```

## Setup

### 1. Supabase
1. Create a project at [supabase.com](https://supabase.com)
2. SQL Editor → paste `supabase/schema.sql` → Run
3. Authentication → Users → create one user per country + one regional admin
4. Assign each user their country:

```sql
update profiles set country_code='KSA', role='country' where email='ksa@...';
update profiles set country_code='EGY', role='country' where email='egypt@...';
update profiles set role='regional' where email='you@...';
```

### 2. Firebase Hosting
```bash
npm i -g firebase-tools
firebase login
firebase init hosting    # public dir: public, single-page app: No
firebase deploy
```

### 3. Render Backend (optional, for alerts)
1. Create a new Web Service on [render.com](https://render.com)
2. Set root directory to `backend`
3. Add environment variables from `.env.example`
4. Deploy

The backend runs scheduled jobs:
- **Daily 08:00 AST** — checks for countries with zero available units
- **Weekly Mon 09:00 AST** — flags units at Austria service > 30 days
- **Monthly 1st 10:00 AST** — shortage summary report

## Data model

- `pool_devices` — one row per physical unit
- `movements` — append-only audit trail (issued, sent to Austria, returned, etc.)
- `shortage_events` — patient couldn't be served, logged separately from stock

Views:
| View | Answers |
|------|---------|
| `v_stock_matrix` | how many of each model remain per country |
| `v_replacements_by_country` | how many devices changed per month |
| `v_service_turnaround` | when each unit went to Austria and came back |
| `v_shortage_seasonality` | which month shortages cluster in |
