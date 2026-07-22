-- ============================================================
-- MED-EL CI Middle East — Service Pool Tracker
-- Supabase / PostgreSQL schema
-- Run this in the Supabase SQL editor (one shot, idempotent-ish).
-- ============================================================

-- ---------- Reference tables ----------

create table if not exists countries (
  code        text primary key,          -- 'KSA', 'EGY', ...
  name        text not null,
  name_ar     text,
  active      boolean not null default true
);

insert into countries (code, name, name_ar) values
  ('KSA','Saudi Arabia','المملكة العربية السعودية'),
  ('EGY','Egypt','مصر'),
  ('UAE','United Arab Emirates','الإمارات'),
  ('QAT','Qatar','قطر'),
  ('BHR','Bahrain','البحرين'),
  ('LBN','Lebanon','لبنان'),
  ('KWT','Kuwait','الكويت'),
  ('SDN','Sudan','السودان'),
  ('SYR','Syria','سوريا')
on conflict (code) do nothing;

create table if not exists device_models (
  code        text primary key,
  name        text not null,
  family      text not null,            -- 'Audio Processor' | 'Accessory' | 'Bone Conduction'
  sort_order  int not null default 0,
  active      boolean not null default true
);

insert into device_models (code, name, family, sort_order) values
  ('SONNET1','SONNET 1','Audio Processor',10),
  ('SONNET2','SONNET 2','Audio Processor',20),
  ('SONNET3','SONNET 3','Audio Processor',30),
  ('RONDO1','RONDO 1','Audio Processor',40),
  ('RONDO2','RONDO 2','Audio Processor',50),
  ('RONDO3','RONDO 3','Audio Processor',60),
  ('OPUS2','OPUS 2','Audio Processor',70),
  ('DLBASE','DL Base Part','Accessory',80),
  ('SAMBA2','SAMBA 2','Bone Conduction',90),
  ('ADHEAR','ADHEAR','Bone Conduction',100)
on conflict (code) do nothing;

-- ---------- Users ----------
-- One user per country. Linked to Supabase auth.users.
-- role: 'country' (sees own country only) | 'regional' (sees everything)

create table if not exists profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  full_name     text,
  email         text,
  country_code  text references countries(code),
  role          text not null default 'country'
                check (role in ('country','regional')),
  created_at    timestamptz not null default now()
);

-- Auto-create a profile row on signup
create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name', new.email))
  on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();


-- ---------- Core: individual pool devices ----------
-- Each row = one physical loaner unit sitting in (or belonging to) a country pool.

create table if not exists pool_devices (
  id             uuid primary key default gen_random_uuid(),
  serial_number  text not null,
  model_code     text not null references device_models(code),
  country_code   text not null references countries(code),
  status         text not null default 'available'
                 check (status in ('available','issued','at_service','in_transit','retired')),
  added_on       date not null default current_date,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (serial_number, model_code)
);

create index if not exists idx_pool_devices_country on pool_devices(country_code);
create index if not exists idx_pool_devices_status  on pool_devices(status);

-- ---------- Movements: the audit trail ----------
-- Every meaningful event in a device's life. This is what the
-- "sent to Austria / returned" reporting is built from.

create table if not exists movements (
  id             uuid primary key default gen_random_uuid(),
  device_id      uuid not null references pool_devices(id) on delete cascade,
  country_code   text not null references countries(code),
  event_type     text not null check (event_type in (
                   'added_to_pool',      -- unit entered the country pool
                   'issued_to_patient',  -- swapped onto a patient
                   'returned_by_patient',
                   'sent_to_austria',    -- shipped for service
                   'returned_from_austria',
                   'transferred_out',
                   'transferred_in',
                   'retired')),
  event_date     date not null default current_date,
  patient_ref    text,                  -- MRN / internal ref only, no names
  rma_number     text,                  -- MED-EL service / RMA reference
  counterpart_country text references countries(code), -- for transfers
  note           text,
  created_by     uuid references profiles(id) default auth.uid(),
  created_at     timestamptz not null default now()
);

create index if not exists idx_movements_device on movements(device_id);
create index if not exists idx_movements_date   on movements(country_code, event_date);
create index if not exists idx_movements_type   on movements(event_type, event_date);

-- Keep pool_devices.status in sync with the latest movement
create or replace function apply_movement_status()
returns trigger language plpgsql as $$
begin
  update pool_devices set
    status = case new.event_type
      when 'added_to_pool'          then 'available'
      when 'issued_to_patient'      then 'issued'
      when 'returned_by_patient'    then 'available'
      when 'sent_to_austria'        then 'at_service'
      when 'returned_from_austria'  then 'available'
      when 'transferred_out'        then 'in_transit'
      when 'transferred_in'         then 'available'
      when 'retired'                then 'retired'
      else status end,
    country_code = case
      when new.event_type = 'transferred_out' and new.counterpart_country is not null
        then new.counterpart_country
      else country_code end,
    updated_at = now()
  where id = new.device_id;
  return new;
end; $$;

drop trigger if exists trg_apply_movement_status on movements;
create trigger trg_apply_movement_status
  after insert on movements
  for each row execute function apply_movement_status();

-- ---------- Shortage events ----------
-- The headline feature: a patient needed a replacement and the pool
-- could not cover it. Logged even if resolved later.

create table if not exists shortage_events (
  id              uuid primary key default gen_random_uuid(),
  country_code    text not null references countries(code),
  model_code      text not null references device_models(code),
  occurred_on     date not null default current_date,
  units_needed    int not null default 1 check (units_needed > 0),
  patient_ref     text,
  urgency         text not null default 'routine'
                  check (urgency in ('routine','urgent','critical')),
  reason          text not null default 'no_stock'
                  check (reason in ('no_stock','all_at_service','wrong_variant','pending_shipment','other')),
  wait_days       int,                   -- how long the patient waited
  resolved_on     date,
  resolution      text,                  -- e.g. 'borrowed from UAE', 'new stock arrived'
  note            text,
  created_by      uuid references profiles(id) default auth.uid(),
  created_at      timestamptz not null default now()
);

create index if not exists idx_shortage_country_date on shortage_events(country_code, occurred_on);
create index if not exists idx_shortage_model on shortage_events(model_code);

-- ---------- Reporting views ----------

-- Current stock per country per model, broken out by status
create or replace view v_stock_matrix as
select
  c.code as country_code,
  c.name as country_name,
  m.code as model_code,
  m.name as model_name,
  count(d.id) filter (where d.status = 'available')  as available,
  count(d.id) filter (where d.status = 'issued')     as issued,
  count(d.id) filter (where d.status = 'at_service') as at_service,
  count(d.id) filter (where d.status = 'in_transit') as in_transit,
  count(d.id) filter (where d.status <> 'retired')   as total_active
from countries c
cross join device_models m
left join pool_devices d
  on d.country_code = c.code and d.model_code = m.code
where c.active and m.active
group by c.code, c.name, m.code, m.name, m.sort_order
order by c.name, m.sort_order;

-- How many units each country has swapped onto patients
create or replace view v_replacements_by_country as
select
  country_code,
  date_trunc('month', event_date)::date as month,
  count(*) as replacements
from movements
where event_type = 'issued_to_patient'
group by 1,2;

-- Austria service turnaround: pairs each dispatch with its return
create or replace view v_service_turnaround as
select
  s.device_id,
  d.serial_number,
  d.model_code,
  s.country_code,
  s.rma_number,
  s.event_date as sent_on,
  r.event_date as returned_on,
  (r.event_date - s.event_date) as turnaround_days
from movements s
join pool_devices d on d.id = s.device_id
left join lateral (
  select m2.event_date
  from movements m2
  where m2.device_id = s.device_id
    and m2.event_type = 'returned_from_austria'
    and m2.event_date >= s.event_date
  order by m2.event_date
  limit 1
) r on true
where s.event_type = 'sent_to_austria';

-- Shortage seasonality: which month of the year hurts most
create or replace view v_shortage_seasonality as
select
  country_code,
  model_code,
  extract(month from occurred_on)::int as month_num,
  to_char(occurred_on, 'Mon')          as month_name,
  extract(year from occurred_on)::int  as year,
  count(*)                              as events,
  sum(units_needed)                     as units_short,
  round(avg(wait_days)::numeric, 1)     as avg_wait_days
from shortage_events
group by 1,2,3,4,5;


-- ============================================================
-- AFTER RUNNING: create your 9 users in Supabase Auth, then:
--   update profiles set country_code='KSA', role='country'
--     where email='ksa@example.com';
--   update profiles set role='regional' where email='you@example.com';
-- ============================================================
