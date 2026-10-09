-- =====================================================================
-- Finanzas ZV · v5 · Tablas y políticas RLS para Supabase
-- ---------------------------------------------------------------------
-- Cómo usarlo: Supabase → SQL Editor → New query → pegar todo → Run.
-- Es idempotente: se puede ejecutar más de una vez sin perder datos.
--   · No borra tablas ni filas.
--   · Las tablas que ya existen (fo_*) solo reciben las columnas que falten.
--   · Las políticas nuevas se SUMAN a las que ya tengas (las políticas
--     permisivas de PostgreSQL se combinan con OR). Revisa al final si
--     alguna política antigua es demasiado abierta (por ejemplo «true»).
-- No contiene ninguna clave: la app usa la clave publicable que ya está
-- en index.html y el token de sesión de cada usuario.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 0. Quién puede ver y escribir los datos financieros
-- ---------------------------------------------------------------------
-- Lista cerrada de correos autorizados. Se llena con los usuarios que ya
-- existen en Authentication → Users. Un usuario que se registre después
-- NO tendrá acceso hasta que lo agregues aquí a mano.
create table if not exists public.zv_allowed_users (
  email     text primary key,
  added_at  timestamptz not null default now()
);
alter table public.zv_allowed_users enable row level security;   -- sin políticas: no se lee desde la API
revoke all on public.zv_allowed_users from anon, authenticated;

insert into public.zv_allowed_users (email)
values ('luiszeav@gmail.com'), ('arturo.zea@gmail.com')
on conflict (email) do nothing;

insert into public.zv_allowed_users (email)
select lower(email) from auth.users where email is not null
on conflict (email) do nothing;

-- Para agregar a alguien más adelante:
--   insert into public.zv_allowed_users (email) values ('correo@dominio.com');
-- Para quitar acceso:
--   delete from public.zv_allowed_users where email = 'correo@dominio.com';

create or replace function public.zv_is_member()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.zv_allowed_users u
    where u.email = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
revoke all on function public.zv_is_member() from public, anon;
grant execute on function public.zv_is_member() to authenticated;

-- ---------------------------------------------------------------------
-- 1. Family Office (tablas existentes): crear si faltan + columnas nuevas
-- ---------------------------------------------------------------------
create table if not exists public.fo_entities (
  id    text primary key,
  name  text not null,
  type  text
);

create table if not exists public.fo_bank_accounts (
  id               text primary key,
  entity_id        text,
  name             text not null,
  bank             text,
  initial_balance  numeric(14,2) not null default 0,
  currency         text not null default 'USD'
);
alter table public.fo_bank_accounts add column if not exists type        text;
alter table public.fo_bank_accounts add column if not exists notes       text;
alter table public.fo_bank_accounts add column if not exists demo        boolean not null default false;
alter table public.fo_bank_accounts add column if not exists created_at  timestamptz default now();
alter table public.fo_bank_accounts add column if not exists updated_at  timestamptz default now();

create table if not exists public.fo_journal_entries (
  id                      text primary key,
  date                    date not null,
  entity_id               text,
  account_id              text,
  type                    text not null,
  category                text,
  concept                 text not null,
  amount                  numeric(14,2) not null,
  status                  text not null default 'Ejecutado',
  destination_account_id  text,
  reference               text
);
alter table public.fo_journal_entries add column if not exists beneficiary   text;
alter table public.fo_journal_entries add column if not exists dist_concept  text;
alter table public.fo_journal_entries add column if not exists demo          boolean not null default false;
alter table public.fo_journal_entries add column if not exists created_at    timestamptz default now();
alter table public.fo_journal_entries add column if not exists updated_at    timestamptz default now();

-- Inversiones: hasta v4 solo recibía borrados; v5 envía altas y cambios.
create table if not exists public.fo_investments (
  id  text primary key
);
alter table public.fo_investments add column if not exists entity_id      text;
alter table public.fo_investments add column if not exists name           text;
alter table public.fo_investments add column if not exists status         text;
alter table public.fo_investments add column if not exists start_date     date;
alter table public.fo_investments add column if not exists expected_date  date;
alter table public.fo_investments add column if not exists capital        numeric(14,2) not null default 0;
alter table public.fo_investments add column if not exists returned       numeric(14,2) not null default 0;
alter table public.fo_investments add column if not exists projected_pct  numeric(9,2);
alter table public.fo_investments add column if not exists notes          text;
alter table public.fo_investments add column if not exists demo           boolean not null default false;
alter table public.fo_investments add column if not exists created_at     timestamptz default now();
alter table public.fo_investments add column if not exists updated_at     timestamptz default now();

-- ---------------------------------------------------------------------
-- 2. Finanzas ZV (motor financiero de la consultora) — antes solo en localStorage
-- ---------------------------------------------------------------------
create table if not exists public.zv_fixed_costs (
  id          text primary key,
  name        text not null,
  category    text not null default 'Otros',
  amount      numeric(14,2) not null default 0 check (amount >= 0),
  demo        boolean not null default false,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

create table if not exists public.zv_contracts (
  id           text primary key,
  client       text not null,
  name         text,
  service      text not null,
  status       text not null default 'Activo' check (status in ('Propuesta', 'Activo', 'Finalizado')),
  start_date   date,
  months       integer not null default 1 check (months between 1 and 120),
  revenue      numeric(14,2) not null default 0 check (revenue >= 0),
  cost_labor   numeric(14,2) not null default 0 check (cost_labor >= 0),
  cost_travel  numeric(14,2) not null default 0 check (cost_travel >= 0),
  cost_sub     numeric(14,2) not null default 0 check (cost_sub >= 0),
  cost_other   numeric(14,2) not null default 0 check (cost_other >= 0),
  demo         boolean not null default false,
  created_at   timestamptz default now(),
  updated_at   timestamptz default now()
);

-- zv_receivables pudo crearse antes con otra forma: se completa columna a columna.
create table if not exists public.zv_receivables (
  id  text primary key
);
alter table public.zv_receivables add column if not exists number        text;
alter table public.zv_receivables add column if not exists client        text;
alter table public.zv_receivables add column if not exists issue_date    date;
alter table public.zv_receivables add column if not exists due_date      date;
alter table public.zv_receivables add column if not exists amount        numeric(14,2) not null default 0;
alter table public.zv_receivables add column if not exists collected     numeric(14,2) not null default 0;
alter table public.zv_receivables add column if not exists status        text not null default 'Pendiente';
alter table public.zv_receivables add column if not exists collected_on  date;
alter table public.zv_receivables add column if not exists demo          boolean not null default false;
alter table public.zv_receivables add column if not exists created_at    timestamptz default now();
alter table public.zv_receivables add column if not exists updated_at    timestamptz default now();

create table if not exists public.zv_projects (
  id          text primary key,
  name        text not null,
  type        text not null default 'Proyecto',
  investment  numeric(14,2) not null default 0 check (investment >= 0),
  rate        numeric(9,2) not null default 12,
  flows       jsonb not null default '[]'::jsonb,   -- flujos anuales [año1, año2, …]
  notes       text,
  demo        boolean not null default false,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

create table if not exists public.zv_assets (
  id          text primary key,
  name        text not null,
  category    text not null default 'Otros',
  cost        numeric(14,2) not null default 0 check (cost >= 0),
  salvage     numeric(14,2) not null default 0 check (salvage >= 0),
  life        integer not null default 5 check (life between 1 and 50),
  acquired    date,
  demo        boolean not null default false,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

-- Supuestos financieros: una sola fila con id = 'zv'.
create table if not exists public.zv_cfo_settings (
  id             text primary key default 'zv' check (id = 'zv'),
  target_margin  numeric(5,2) not null default 35,
  min_runway     integer not null default 6,
  manual_cash    numeric(14,2),
  updated_at     timestamptz default now()
);

-- ---------------------------------------------------------------------
-- 3. RLS: solo los correos de zv_allowed_users leen y escriben
-- ---------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'fo_entities', 'fo_bank_accounts', 'fo_journal_entries', 'fo_investments',
    'zv_fixed_costs', 'zv_contracts', 'zv_receivables', 'zv_projects', 'zv_assets', 'zv_cfo_settings'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);

    execute format('drop policy if exists zv_members_select on public.%I', t);
    execute format('drop policy if exists zv_members_insert on public.%I', t);
    execute format('drop policy if exists zv_members_update on public.%I', t);
    execute format('drop policy if exists zv_members_delete on public.%I', t);

    execute format('create policy zv_members_select on public.%I for select to authenticated using (public.zv_is_member())', t);
    execute format('create policy zv_members_insert on public.%I for insert to authenticated with check (public.zv_is_member())', t);
    execute format('create policy zv_members_update on public.%I for update to authenticated using (public.zv_is_member()) with check (public.zv_is_member())', t);
    execute format('create policy zv_members_delete on public.%I for delete to authenticated using (public.zv_is_member())', t);
  end loop;
end $$;

-- Que la API vea las columnas nuevas de inmediato.
notify pgrst, 'reload schema';

commit;

-- ---------------------------------------------------------------------
-- 4. Comprobaciones (ejecutar aparte, solo lectura)
-- ---------------------------------------------------------------------
-- ¿Quién tiene acceso?
--   select * from public.zv_allowed_users;
-- ¿Qué políticas hay en cada tabla? Busca alguna antigua con «true» o «auth.role() = 'authenticated'»:
--   select tablename, policyname, cmd, roles, qual, with_check
--   from pg_policies where schemaname = 'public'
--   and tablename like any (array['fo\_%', 'zv\_%']) order by tablename, policyname;
-- Recomendado también: Authentication → Sign In / Providers → desactivar «Allow new users to sign up».
