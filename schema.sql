-- APONTA P3 EQUIPE v2.8 - BANCO SUPABASE
-- Execute todo este arquivo no SQL Editor do Supabase.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text not null default '',
  role text not null default 'colaborador' check (role in ('administrador','gestor','colaborador')),
  daily_hours numeric(5,2) not null default 8 check (daily_hours > 0 and daily_hours <= 24),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text not null default '',
  active boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.activities (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  activity_type text not null default 'Demanda',
  frequency text not null default '',
  active boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.time_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  entry_date date not null,
  project_id uuid not null references public.projects(id),
  activity_id uuid not null references public.activities(id),
  hours numeric(5,2) not null check (hours > 0 and hours <= 24),
  details text not null default '',
  status text not null default 'rascunho' check (status in ('rascunho','enviado','aprovado','devolvido')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.absences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  start_date date not null,
  end_date date not null,
  absence_type text not null,
  notes text not null default '',
  created_at timestamptz not null default now(),
  check (end_date >= start_date)
);

create table if not exists public.monthly_closings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  month_ref date not null,
  status text not null default 'aberto' check (status in ('aberto','enviado','aprovado','devolvido')),
  submitted_at timestamptz,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  review_note text not null default '',
  unique(user_id, month_ref)
);

create table if not exists public.holidays (
  id uuid primary key default gen_random_uuid(),
  holiday_date date not null unique,
  name text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_time_entries_user_date on public.time_entries(user_id, entry_date);
create index if not exists idx_time_entries_project on public.time_entries(project_id);
create index if not exists idx_absences_user_dates on public.absences(user_id, start_date, end_date);
create index if not exists idx_closings_user_month on public.monthly_closings(user_id, month_ref);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

drop trigger if exists trg_time_entries_updated_at on public.time_entries;
create trigger trg_time_entries_updated_at before update on public.time_entries
for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare first_user boolean;
begin
  select not exists(select 1 from public.profiles) into first_user;
  insert into public.profiles(id, full_name, email, role)
  values(
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)),
    coalesce(new.email,''),
    case when first_user then 'administrador' else 'colaborador' end
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.is_manager()
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid() and active = true and role in ('administrador','gestor')
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid() and active = true and role = 'administrador'
  );
$$;

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on function public.is_manager() to authenticated;
grant execute on function public.is_admin() to authenticated;

alter table public.profiles enable row level security;
alter table public.projects enable row level security;
alter table public.activities enable row level security;
alter table public.time_entries enable row level security;
alter table public.absences enable row level security;
alter table public.monthly_closings enable row level security;
alter table public.holidays enable row level security;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated using (true);
drop policy if exists profiles_admin_update on public.profiles;
create policy profiles_admin_update on public.profiles for update to authenticated
using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists projects_select on public.projects;
create policy projects_select on public.projects for select to authenticated using (true);
drop policy if exists projects_manage_insert on public.projects;
create policy projects_manage_insert on public.projects for insert to authenticated with check ((select public.is_manager()));
drop policy if exists projects_manage_update on public.projects;
create policy projects_manage_update on public.projects for update to authenticated using ((select public.is_manager())) with check ((select public.is_manager()));
drop policy if exists projects_manage_delete on public.projects;
create policy projects_manage_delete on public.projects for delete to authenticated using ((select public.is_manager()));

drop policy if exists activities_select on public.activities;
create policy activities_select on public.activities for select to authenticated using (true);
drop policy if exists activities_manage_insert on public.activities;
create policy activities_manage_insert on public.activities for insert to authenticated with check ((select public.is_manager()));
drop policy if exists activities_manage_update on public.activities;
create policy activities_manage_update on public.activities for update to authenticated using ((select public.is_manager())) with check ((select public.is_manager()));
drop policy if exists activities_manage_delete on public.activities;
create policy activities_manage_delete on public.activities for delete to authenticated using ((select public.is_manager()));

drop policy if exists entries_select on public.time_entries;
create policy entries_select on public.time_entries for select to authenticated
using (auth.uid() = user_id or (select public.is_manager()));
drop policy if exists entries_insert on public.time_entries;
create policy entries_insert on public.time_entries for insert to authenticated
with check (auth.uid() = user_id or (select public.is_manager()));
drop policy if exists entries_update on public.time_entries;
create policy entries_update on public.time_entries for update to authenticated
using ((auth.uid() = user_id and status in ('rascunho','devolvido')) or (select public.is_manager()))
with check (auth.uid() = user_id or (select public.is_manager()));
drop policy if exists entries_delete on public.time_entries;
create policy entries_delete on public.time_entries for delete to authenticated
using ((auth.uid() = user_id and status in ('rascunho','devolvido')) or (select public.is_manager()));

drop policy if exists absences_select on public.absences;
create policy absences_select on public.absences for select to authenticated
using (auth.uid() = user_id or (select public.is_manager()));
drop policy if exists absences_insert on public.absences;
create policy absences_insert on public.absences for insert to authenticated
with check (auth.uid() = user_id or (select public.is_manager()));
drop policy if exists absences_update on public.absences;
create policy absences_update on public.absences for update to authenticated
using (auth.uid() = user_id or (select public.is_manager()))
with check (auth.uid() = user_id or (select public.is_manager()));
drop policy if exists absences_delete on public.absences;
create policy absences_delete on public.absences for delete to authenticated
using (auth.uid() = user_id or (select public.is_manager()));

drop policy if exists closings_select on public.monthly_closings;
create policy closings_select on public.monthly_closings for select to authenticated
using (auth.uid() = user_id or (select public.is_manager()));
drop policy if exists closings_insert on public.monthly_closings;
create policy closings_insert on public.monthly_closings for insert to authenticated
with check (auth.uid() = user_id or (select public.is_manager()));
drop policy if exists closings_update on public.monthly_closings;
create policy closings_update on public.monthly_closings for update to authenticated
using ((auth.uid() = user_id and status in ('aberto','devolvido')) or (select public.is_manager()))
with check (auth.uid() = user_id or (select public.is_manager()));

drop policy if exists holidays_select on public.holidays;
create policy holidays_select on public.holidays for select to authenticated using (true);
drop policy if exists holidays_manage_insert on public.holidays;
create policy holidays_manage_insert on public.holidays for insert to authenticated with check ((select public.is_manager()));
drop policy if exists holidays_manage_update on public.holidays;
create policy holidays_manage_update on public.holidays for update to authenticated using ((select public.is_manager())) with check ((select public.is_manager()));
drop policy if exists holidays_manage_delete on public.holidays;
create policy holidays_manage_delete on public.holidays for delete to authenticated using ((select public.is_manager()));

insert into public.projects(name, description)
values ('CORP','Atividades corporativas')
on conflict (name) do nothing;

insert into public.activities(name, activity_type, frequency)
values
 ('COTAÇÃO','Demanda',''),
 ('REUNIÃO','Recorrente','Semanal'),
 ('PLANEJAMENTO','Recorrente','Mensal')
on conflict (name) do nothing;


-- Função para cada usuário editar o próprio nome e jornada.

create or replace function public.update_my_profile(
  p_full_name text,
  p_daily_hours numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado';
  end if;

  if length(trim(coalesce(p_full_name, ''))) < 2 then
    raise exception 'Informe um nome válido';
  end if;

  if p_daily_hours <= 0 or p_daily_hours > 24 then
    raise exception 'A jornada deve estar entre 1 e 24 horas';
  end if;

  update public.profiles
     set full_name = trim(p_full_name),
         daily_hours = p_daily_hours
   where id = auth.uid();
end;
$$;

grant execute on function public.update_my_profile(text, numeric) to authenticated;


-- Proteção contra apontamentos em datas futuras.

create or replace function public.prevent_future_time_entry()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.entry_date > current_date then
    raise exception 'Não é permitido realizar apontamentos em datas futuras.'
      using errcode = '22007';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_prevent_future_time_entry on public.time_entries;

create trigger trg_prevent_future_time_entry
before insert or update of entry_date
on public.time_entries
for each row
execute function public.prevent_future_time_entry();


-- APONTA P3 MODULAR v2.6
-- Campos complementares para importar a aba Atividades.

alter table public.activities
  add column if not exists responsible_name text not null default '';

alter table public.activities
  add column if not exists backup_name text not null default '';


-- ============================================================
-- RECURSOS DA VERSÃO 2.8
-- ============================================================
-- APONTA P3 MODULAR v2.8
-- Férias, afastamentos individuais e exclusões seguras.
-- Para atualizar uma instalação v2.7, execute este arquivo no SQL Editor do Supabase.


alter table public.absences
  add column if not exists created_by uuid references public.profiles(id) on delete set null;

alter table public.absences
  add column if not exists updated_at timestamptz not null default now();

create index if not exists idx_absences_user_period_v28
  on public.absences(user_id, start_date, end_date);

create or replace function public.aponta_current_role_v28()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role
    from public.profiles
   where id = auth.uid()
     and active = true
   limit 1;
$$;

revoke all on function public.aponta_current_role_v28() from public;
grant execute on function public.aponta_current_role_v28() to authenticated;

create or replace function public.aponta_set_absence_updated_at_v28()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_absences_updated_at_v28 on public.absences;
create trigger trg_absences_updated_at_v28
before update on public.absences
for each row
execute function public.aponta_set_absence_updated_at_v28();

create or replace function public.aponta_upsert_absence_v28(
  p_id uuid,
  p_user_id uuid,
  p_absence_type text,
  p_start_date date,
  p_end_date date,
  p_notes text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_id uuid;
  v_owner uuid;
  v_type text;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado.';
  end if;

  v_role := public.aponta_current_role_v28();
  if v_role is null then
    raise exception 'Perfil inativo ou não encontrado.';
  end if;

  if p_user_id is null then
    raise exception 'Selecione o colaborador.';
  end if;

  if p_user_id <> auth.uid()
     and v_role not in ('administrador', 'gestor') then
    raise exception 'Você não pode cadastrar férias ou afastamento para outro colaborador.';
  end if;

  if not exists (
    select 1 from public.profiles
     where id = p_user_id and active = true
  ) then
    raise exception 'Colaborador não encontrado ou inativo.';
  end if;

  if p_start_date is null or p_end_date is null then
    raise exception 'Informe as datas inicial e final.';
  end if;

  if p_end_date < p_start_date then
    raise exception 'A data final não pode ser anterior à data inicial.';
  end if;

  v_type := trim(coalesce(p_absence_type, ''));
  if lower(v_type) not in (
    'férias', 'ferias',
    'atestado', 'atestado médico', 'atestado medico',
    'afastamento', 'afastamento pelo inss',
    'licença', 'licenca',
    'licença-maternidade', 'licenca-maternidade',
    'licença-paternidade', 'licenca-paternidade',
    'licença não remunerada', 'licenca nao remunerada',
    'folga', 'outro', 'outro afastamento'
  ) then
    raise exception 'Selecione um tipo válido de férias ou afastamento.';
  end if;

  if p_id is null then
    insert into public.absences(
      user_id, start_date, end_date, absence_type, notes, created_by, updated_at
    ) values (
      p_user_id,
      p_start_date,
      p_end_date,
      v_type,
      coalesce(trim(p_notes), ''),
      auth.uid(),
      now()
    )
    returning id into v_id;
  else
    select user_id into v_owner
      from public.absences
     where id = p_id;

    if v_owner is null then
      raise exception 'Registro não encontrado.';
    end if;

    if v_owner <> auth.uid()
       and v_role not in ('administrador', 'gestor') then
      raise exception 'Você não pode editar este registro.';
    end if;

    update public.absences
       set user_id = p_user_id,
           start_date = p_start_date,
           end_date = p_end_date,
           absence_type = v_type,
           notes = coalesce(trim(p_notes), ''),
           updated_at = now()
     where id = p_id
     returning id into v_id;
  end if;

  return v_id;
end;
$$;

revoke all on function public.aponta_upsert_absence_v28(uuid, uuid, text, date, date, text) from public;
grant execute on function public.aponta_upsert_absence_v28(uuid, uuid, text, date, date, text) to authenticated;

create or replace function public.aponta_delete_absence_v28(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_owner uuid;
begin
  v_role := public.aponta_current_role_v28();

  select user_id into v_owner
    from public.absences
   where id = p_id;

  if v_owner is null then
    raise exception 'Registro não encontrado.';
  end if;

  if v_owner <> auth.uid()
     and v_role not in ('administrador', 'gestor') then
    raise exception 'Você não pode excluir este registro.';
  end if;

  delete from public.absences where id = p_id;
end;
$$;

revoke all on function public.aponta_delete_absence_v28(uuid) from public;
grant execute on function public.aponta_delete_absence_v28(uuid) to authenticated;

create or replace function public.aponta_prevent_entry_during_absence_v28()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_type text;
begin
  select absence_type into v_type
    from public.absences
   where user_id = new.user_id
     and new.entry_date between start_date and end_date
   order by start_date
   limit 1;

  if v_type is not null then
    raise exception 'Não é permitido lançar horas nesta data: colaborador cadastrado em %.', v_type
      using errcode = '22007';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_prevent_entry_during_absence_v28 on public.time_entries;
create trigger trg_prevent_entry_during_absence_v28
before insert or update of user_id, entry_date
on public.time_entries
for each row
execute function public.aponta_prevent_entry_during_absence_v28();

create or replace function public.aponta_protect_time_entry_delete_v28()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_closing_status text;
begin
  v_role := public.aponta_current_role_v28();

  if old.user_id <> auth.uid()
     and v_role not in ('administrador', 'gestor') then
    raise exception 'Você não pode excluir este apontamento.';
  end if;

  select status into v_closing_status
    from public.monthly_closings
   where user_id = old.user_id
     and month_ref = date_trunc('month', old.entry_date)::date
   limit 1;

  if old.status in ('enviado', 'aprovado')
     or v_closing_status in ('enviado', 'aprovado') then
    raise exception 'O período está enviado ou aprovado. Reabra o fechamento antes de excluir.';
  end if;

  return old;
end;
$$;

drop trigger if exists trg_protect_time_entry_delete_v28 on public.time_entries;
create trigger trg_protect_time_entry_delete_v28
before delete on public.time_entries
for each row
execute function public.aponta_protect_time_entry_delete_v28();

create or replace function public.aponta_delete_time_entry_v28(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.time_entries where id = p_id;
  if not found then
    raise exception 'Apontamento não encontrado ou sem permissão.';
  end if;
end;
$$;

revoke all on function public.aponta_delete_time_entry_v28(uuid) from public;
grant execute on function public.aponta_delete_time_entry_v28(uuid) to authenticated;

create or replace function public.aponta_delete_activity_v28(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.aponta_current_role_v28() not in ('administrador', 'gestor') then
    raise exception 'Somente Administradores e Gestores podem excluir atividades.';
  end if;

  if exists (select 1 from public.time_entries where activity_id = p_id) then
    raise exception 'A atividade possui apontamentos. Desative-a para preservar o histórico.';
  end if;

  delete from public.activities where id = p_id;
  if not found then
    raise exception 'Atividade não encontrada.';
  end if;
end;
$$;

revoke all on function public.aponta_delete_activity_v28(uuid) from public;
grant execute on function public.aponta_delete_activity_v28(uuid) to authenticated;

create or replace function public.aponta_delete_project_v28(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.aponta_current_role_v28() not in ('administrador', 'gestor') then
    raise exception 'Somente Administradores e Gestores podem excluir projetos.';
  end if;

  if exists (select 1 from public.time_entries where project_id = p_id) then
    raise exception 'O projeto possui apontamentos. Desative-o para preservar o histórico.';
  end if;

  delete from public.projects where id = p_id;
  if not found then
    raise exception 'Projeto não encontrado.';
  end if;
end;
$$;

revoke all on function public.aponta_delete_project_v28(uuid) from public;
grant execute on function public.aponta_delete_project_v28(uuid) to authenticated;

create or replace view public.vw_powerbi_ausencias as
select
  ab.id as ausencia_id,
  ab.user_id as colaborador_id,
  p.full_name as colaborador,
  ab.start_date as data_inicio,
  ab.end_date as data_fim,
  (ab.end_date - ab.start_date + 1) as quantidade_dias,
  ab.absence_type as tipo_ausencia,
  case
    when current_date < ab.start_date then 'programado'
    when current_date > ab.end_date then 'encerrado'
    else 'em_andamento'
  end as situacao,
  coalesce(ab.notes, '') as observacao,
  ab.created_at,
  ab.updated_at
from public.absences ab
join public.profiles p on p.id = ab.user_id;


select 'Aponta P3 v2.8 instalado' as resultado;


-- ============================================================
-- RECURSOS DA VERSÃO 2.10
-- ============================================================
-- APONTA P3 MODULAR v2.10
-- Aprovação de férias e afastamentos.
-- Após a aprovação, o colaborador não pode editar nem excluir.
-- Gestores e Administradores continuam podendo alterar ou excluir.



-- 1. Campos de aprovação
alter table public.absences
  add column if not exists approval_status text;

alter table public.absences
  add column if not exists approved_by uuid references public.profiles(id) on delete set null;

alter table public.absences
  add column if not exists approved_at timestamptz;

-- Registros antigos já eram considerados oficiais antes deste fluxo.
update public.absences
   set approval_status = 'aprovado',
       approved_by = coalesce(approved_by, created_by),
       approved_at = coalesce(approved_at, updated_at, created_at)
 where approval_status is null;

alter table public.absences
  alter column approval_status set default 'pendente';

alter table public.absences
  alter column approval_status set not null;

alter table public.absences
  drop constraint if exists absences_approval_status_check_v210;

alter table public.absences
  add constraint absences_approval_status_check_v210
  check (approval_status in ('pendente', 'aprovado'));

create index if not exists idx_absences_approval_status_v210
  on public.absences(approval_status, start_date, end_date);

-- 2. Protege os campos de aprovação contra alteração pelo colaborador
create or replace function public.aponta_protect_absence_approval_v210()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
begin
  v_role := public.aponta_current_role_v28();

  if tg_op = 'INSERT' then
    if v_role not in ('administrador', 'gestor') then
      new.approval_status := 'pendente';
      new.approved_by := null;
      new.approved_at := null;
    end if;
    return new;
  end if;

  if v_role not in ('administrador', 'gestor') then
    if old.approval_status = 'aprovado' then
      raise exception 'Este período já foi aprovado e somente Gestor ou Administrador pode alterá-lo.';
    end if;

    new.approval_status := old.approval_status;
    new.approved_by := old.approved_by;
    new.approved_at := old.approved_at;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_protect_absence_approval_v210 on public.absences;
create trigger trg_protect_absence_approval_v210
before insert or update on public.absences
for each row
execute function public.aponta_protect_absence_approval_v210();

-- Proteção adicional para exclusão direta
create or replace function public.aponta_protect_absence_delete_v210()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.approval_status = 'aprovado'
     and public.aponta_current_role_v28() not in ('administrador', 'gestor') then
    raise exception 'Este período já foi aprovado e somente Gestor ou Administrador pode excluí-lo.';
  end if;
  return old;
end;
$$;

drop trigger if exists trg_protect_absence_delete_v210 on public.absences;
create trigger trg_protect_absence_delete_v210
before delete on public.absences
for each row
execute function public.aponta_protect_absence_delete_v210();

-- 3. Políticas RLS atualizadas
alter table public.absences enable row level security;

drop policy if exists absences_select on public.absences;
drop policy if exists absences_insert on public.absences;
drop policy if exists absences_update on public.absences;
drop policy if exists absences_delete on public.absences;
drop policy if exists v28_absences_select on public.absences;
drop policy if exists v28_absences_insert on public.absences;
drop policy if exists v28_absences_update on public.absences;
drop policy if exists v28_absences_delete on public.absences;

create policy absences_select
on public.absences for select to authenticated
using (
  auth.uid() = user_id
  or public.aponta_current_role_v28() in ('administrador', 'gestor')
);

create policy absences_insert
on public.absences for insert to authenticated
with check (
  auth.uid() = user_id
  or public.aponta_current_role_v28() in ('administrador', 'gestor')
);

create policy absences_update
on public.absences for update to authenticated
using (
  (auth.uid() = user_id and approval_status = 'pendente')
  or public.aponta_current_role_v28() in ('administrador', 'gestor')
)
with check (
  (auth.uid() = user_id and approval_status = 'pendente')
  or public.aponta_current_role_v28() in ('administrador', 'gestor')
);

create policy absences_delete
on public.absences for delete to authenticated
using (
  (auth.uid() = user_id and approval_status = 'pendente')
  or public.aponta_current_role_v28() in ('administrador', 'gestor')
);

-- 4. Cadastro e edição com bloqueio após aprovação
create or replace function public.aponta_upsert_absence_v28(
  p_id uuid,
  p_user_id uuid,
  p_absence_type text,
  p_start_date date,
  p_end_date date,
  p_notes text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_id uuid;
  v_owner uuid;
  v_approval_status text;
  v_type text;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado.';
  end if;

  v_role := public.aponta_current_role_v28();
  if v_role is null then
    raise exception 'Perfil inativo ou não encontrado.';
  end if;

  if p_user_id is null then
    raise exception 'Selecione o colaborador.';
  end if;

  if p_user_id <> auth.uid()
     and v_role not in ('administrador', 'gestor') then
    raise exception 'Você não pode cadastrar férias ou afastamento para outro colaborador.';
  end if;

  if not exists (
    select 1 from public.profiles
     where id = p_user_id and active = true
  ) then
    raise exception 'Colaborador não encontrado ou inativo.';
  end if;

  if p_start_date is null or p_end_date is null then
    raise exception 'Informe as datas inicial e final.';
  end if;

  if p_end_date < p_start_date then
    raise exception 'A data final não pode ser anterior à data inicial.';
  end if;

  v_type := trim(coalesce(p_absence_type, ''));
  if lower(v_type) not in (
    'férias', 'ferias',
    'atestado', 'atestado médico', 'atestado medico',
    'afastamento', 'afastamento pelo inss',
    'licença', 'licenca',
    'licença-maternidade', 'licenca-maternidade',
    'licença-paternidade', 'licenca-paternidade',
    'licença não remunerada', 'licenca nao remunerada',
    'folga', 'outro', 'outro afastamento'
  ) then
    raise exception 'Selecione um tipo válido de férias ou afastamento.';
  end if;

  if p_id is null then
    insert into public.absences(
      user_id, start_date, end_date, absence_type, notes,
      created_by, updated_at, approval_status
    ) values (
      p_user_id,
      p_start_date,
      p_end_date,
      v_type,
      coalesce(trim(p_notes), ''),
      auth.uid(),
      now(),
      'pendente'
    )
    returning id into v_id;
  else
    select user_id, approval_status
      into v_owner, v_approval_status
      from public.absences
     where id = p_id;

    if v_owner is null then
      raise exception 'Registro não encontrado.';
    end if;

    if v_owner <> auth.uid()
       and v_role not in ('administrador', 'gestor') then
      raise exception 'Você não pode editar este registro.';
    end if;

    if v_approval_status = 'aprovado'
       and v_role not in ('administrador', 'gestor') then
      raise exception 'Este período já foi aprovado. Somente Gestor ou Administrador pode alterá-lo.';
    end if;

    update public.absences
       set user_id = p_user_id,
           start_date = p_start_date,
           end_date = p_end_date,
           absence_type = v_type,
           notes = coalesce(trim(p_notes), ''),
           updated_at = now()
     where id = p_id
     returning id into v_id;
  end if;

  return v_id;
end;
$$;

revoke all on function public.aponta_upsert_absence_v28(uuid, uuid, text, date, date, text) from public;
grant execute on function public.aponta_upsert_absence_v28(uuid, uuid, text, date, date, text) to authenticated;

-- 5. Exclusão com bloqueio após aprovação
create or replace function public.aponta_delete_absence_v28(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_owner uuid;
  v_approval_status text;
begin
  v_role := public.aponta_current_role_v28();

  select user_id, approval_status
    into v_owner, v_approval_status
    from public.absences
   where id = p_id;

  if v_owner is null then
    raise exception 'Registro não encontrado.';
  end if;

  if v_owner <> auth.uid()
     and v_role not in ('administrador', 'gestor') then
    raise exception 'Você não pode excluir este registro.';
  end if;

  if v_approval_status = 'aprovado'
     and v_role not in ('administrador', 'gestor') then
    raise exception 'Este período já foi aprovado. Somente Gestor ou Administrador pode excluí-lo.';
  end if;

  delete from public.absences where id = p_id;
end;
$$;

revoke all on function public.aponta_delete_absence_v28(uuid) from public;
grant execute on function public.aponta_delete_absence_v28(uuid) to authenticated;

-- 6. Aprovação por Gestor ou Administrador
create or replace function public.aponta_approve_absence_v210(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado.';
  end if;

  v_role := public.aponta_current_role_v28();
  if v_role not in ('administrador', 'gestor') then
    raise exception 'Somente Gestor ou Administrador pode aprovar férias e afastamentos.';
  end if;

  update public.absences
     set approval_status = 'aprovado',
         approved_by = auth.uid(),
         approved_at = now(),
         updated_at = now()
   where id = p_id
     and approval_status = 'pendente';

  if not found then
    if exists (select 1 from public.absences where id = p_id and approval_status = 'aprovado') then
      raise exception 'Este período já está aprovado.';
    end if;
    raise exception 'Registro não encontrado.';
  end if;
end;
$$;

revoke all on function public.aponta_approve_absence_v210(uuid) from public;
grant execute on function public.aponta_approve_absence_v210(uuid) to authenticated;

-- 7. Power BI com situação da aprovação
create or replace view public.vw_powerbi_ausencias as
select
  ab.id as ausencia_id,
  ab.user_id as colaborador_id,
  p.full_name as colaborador,
  ab.start_date as data_inicio,
  ab.end_date as data_fim,
  (ab.end_date - ab.start_date + 1) as quantidade_dias,
  ab.absence_type as tipo_ausencia,
  case
    when current_date < ab.start_date then 'programado'
    when current_date > ab.end_date then 'encerrado'
    else 'em_andamento'
  end as situacao,
  ab.approval_status as situacao_aprovacao,
  ab.approved_by as aprovado_por_id,
  approver.full_name as aprovado_por,
  ab.approved_at as aprovado_em,
  coalesce(ab.notes, '') as observacao,
  ab.created_at,
  ab.updated_at
from public.absences ab
join public.profiles p on p.id = ab.user_id
left join public.profiles approver on approver.id = ab.approved_by;






-- APONTA P3 v2.11
-- APROVAÇÃO DE INSCRIÇÃO PARA LIBERAR APONTAMENTOS
--
-- Fluxo:
-- 1. Usuário cria a conta.
-- 2. Perfil entra como PENDENTE.
-- 3. Gestor ou Administrador aprova ou rejeita.
-- 4. Somente perfil APROVADO pode criar/alterar os próprios apontamentos.
--
-- Execute no Supabase:
-- SQL Editor > New query > Run


-- ============================================================
-- 1. CAMPOS DE APROVAÇÃO DA INSCRIÇÃO
-- ============================================================

alter table public.profiles
  add column if not exists registration_status text;

alter table public.profiles
  add column if not exists registration_reviewed_by uuid
  references public.profiles(id) on delete set null;

alter table public.profiles
  add column if not exists registration_reviewed_at timestamptz;

alter table public.profiles
  add column if not exists registration_review_note text not null default '';

-- Preserva os usuários que já utilizam o sistema.
update public.profiles
   set registration_status = 'aprovado',
       registration_reviewed_at = coalesce(registration_reviewed_at, created_at)
 where registration_status is null
    or trim(registration_status) = '';

alter table public.profiles
  alter column registration_status set default 'pendente';

alter table public.profiles
  alter column registration_status set not null;

alter table public.profiles
  drop constraint if exists profiles_registration_status_check_v211;

alter table public.profiles
  add constraint profiles_registration_status_check_v211
  check (registration_status in ('pendente', 'aprovado', 'rejeitado'));

create index if not exists idx_profiles_registration_status_v211
  on public.profiles(registration_status, active, full_name);

-- ============================================================
-- 2. NOVOS USUÁRIOS ENTRAM COMO PENDENTES
-- ============================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  first_user boolean;
begin
  select not exists(select 1 from public.profiles) into first_user;

  insert into public.profiles(
    id,
    full_name,
    email,
    role,
    active,
    registration_status,
    registration_reviewed_at,
    registration_review_note
  )
  values(
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)),
    coalesce(new.email,''),
    case when first_user then 'administrador' else 'colaborador' end,
    true,
    case when first_user then 'aprovado' else 'pendente' end,
    case when first_user then now() else null end,
    ''
  );

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_user();

-- ============================================================
-- 3. FUNÇÃO QUE CONFERE SE O PERFIL PODE APONTAR
-- ============================================================

create or replace function public.aponta_can_make_entries_v211(
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
      from public.profiles
     where id = p_user_id
       and active = true
       and registration_status = 'aprovado'
  );
$$;

revoke all
  on function public.aponta_can_make_entries_v211(uuid)
  from public;

grant execute
  on function public.aponta_can_make_entries_v211(uuid)
  to authenticated;

-- ============================================================
-- 4. GESTOR OU ADMINISTRADOR APROVA/REJEITA
-- ============================================================

create or replace function public.aponta_review_registration_v211(
  p_user_id uuid,
  p_decision text,
  p_note text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_target_role text;
  v_decision text;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado.';
  end if;

  v_role := public.aponta_current_role_v28();

  if v_role not in ('administrador', 'gestor') then
    raise exception 'Somente Gestor ou Administrador pode analisar inscrições.';
  end if;

  if not public.aponta_can_make_entries_v211(auth.uid()) then
    raise exception 'Seu próprio cadastro ainda não está aprovado.';
  end if;

  v_decision := lower(trim(coalesce(p_decision, '')));

  if v_decision not in ('aprovado', 'rejeitado') then
    raise exception 'Decisão inválida. Use aprovado ou rejeitado.';
  end if;

  select role into v_target_role
    from public.profiles
   where id = p_user_id;

  if v_target_role is null then
    raise exception 'Usuário não encontrado.';
  end if;

  -- Gestor pode analisar somente inscrições de colaboradores.
  if v_role = 'gestor' and v_target_role <> 'colaborador' then
    raise exception 'Gestor pode analisar somente inscrições de colaboradores.';
  end if;

  if p_user_id = auth.uid() and v_decision = 'rejeitado' then
    raise exception 'Você não pode rejeitar o próprio cadastro.';
  end if;

  update public.profiles
     set registration_status = v_decision,
         registration_reviewed_by = auth.uid(),
         registration_reviewed_at = now(),
         registration_review_note = trim(coalesce(p_note, ''))
   where id = p_user_id;
end;
$$;

revoke all
  on function public.aponta_review_registration_v211(uuid, text, text)
  from public;

grant execute
  on function public.aponta_review_registration_v211(uuid, text, text)
  to authenticated;

-- ============================================================
-- 5. BLOQUEIO NO BANCO DOS APONTAMENTOS
-- ============================================================

drop policy if exists entries_insert on public.time_entries;
create policy entries_insert
on public.time_entries
for insert
to authenticated
with check (
  (
    auth.uid() = user_id
    or (select public.is_manager())
  )
  and public.aponta_can_make_entries_v211(user_id)
);

drop policy if exists entries_update on public.time_entries;
create policy entries_update
on public.time_entries
for update
to authenticated
using (
  (
    auth.uid() = user_id
    and status in ('rascunho','devolvido')
    and public.aponta_can_make_entries_v211(auth.uid())
  )
  or (select public.is_manager())
)
with check (
  (
    auth.uid() = user_id
    and public.aponta_can_make_entries_v211(auth.uid())
  )
  or (select public.is_manager())
);

drop policy if exists entries_delete on public.time_entries;
create policy entries_delete
on public.time_entries
for delete
to authenticated
using (
  (
    auth.uid() = user_id
    and status in ('rascunho','devolvido')
    and public.aponta_can_make_entries_v211(auth.uid())
  )
  or (select public.is_manager())
);

-- Também protege o envio do fechamento pelo próprio colaborador.
drop policy if exists closings_insert on public.monthly_closings;
create policy closings_insert
on public.monthly_closings
for insert
to authenticated
with check (
  (
    auth.uid() = user_id
    and public.aponta_can_make_entries_v211(auth.uid())
  )
  or (select public.is_manager())
);

drop policy if exists closings_update on public.monthly_closings;
create policy closings_update
on public.monthly_closings
for update
to authenticated
using (
  (
    auth.uid() = user_id
    and status in ('aberto','devolvido')
    and public.aponta_can_make_entries_v211(auth.uid())
  )
  or (select public.is_manager())
)
with check (
  (
    auth.uid() = user_id
    and public.aponta_can_make_entries_v211(auth.uid())
  )
  or (select public.is_manager())
);

-- Defesa adicional contra inserção direta fora da tela do aplicativo.
create or replace function public.aponta_block_unapproved_entry_v211()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Permite operações administrativas internas com service_role,
  -- onde auth.uid() é nulo, como restauração de backup.
  if auth.uid() is not null
     and not public.aponta_can_make_entries_v211(new.user_id) then
    raise exception
      'Este usuário ainda não foi aprovado para realizar apontamentos.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_block_unapproved_entry_v211
  on public.time_entries;

create trigger trg_block_unapproved_entry_v211
before insert
on public.time_entries
for each row
execute function public.aponta_block_unapproved_entry_v211();

-- ============================================================
-- 6. VISIBILIDADE DE PERFIS
-- ============================================================

drop policy if exists profiles_select on public.profiles;
create policy profiles_select
on public.profiles
for select
to authenticated
using (
  id = auth.uid()
  or (select public.is_manager())
  or public.aponta_can_make_entries_v211(auth.uid())
);

notify pgrst, 'reload schema';


select
  'APONTA P3 v2.11 INSTALADO COM SUCESSO' as resultado,
  count(*) filter (where registration_status = 'pendente') as pendentes,
  count(*) filter (where registration_status = 'aprovado') as aprovados,
  count(*) filter (where registration_status = 'rejeitado') as rejeitados
from public.profiles;



-- APONTA P3 v2.12.0 — FLUXO PROJETO > ÁREA > REFERÊNCIA > ATIVIDADE
-- Execute todo este arquivo no SQL Editor do Supabase antes de publicar o app v2.12.0.

create extension if not exists pgcrypto;

alter table public.projects add column if not exists code text;
alter table public.projects add column if not exists client_name text not null default '';
alter table public.projects add column if not exists project_status text not null default 'Em andamento';
create unique index if not exists projects_code_unique_v212 on public.projects(code) where code is not null;

alter table public.activities add column if not exists code text;
alter table public.activities add column if not exists discipline_code text not null default '';
alter table public.activities add column if not exists discipline_name text not null default '';
alter table public.activities add column if not exists sector_principal text not null default '';
alter table public.activities add column if not exists nature text not null default '';
alter table public.activities add column if not exists usage_description text not null default '';
alter table public.activities add column if not exists observation_requirement text not null default 'Recomendado';
create unique index if not exists activities_code_unique_v212 on public.activities(code) where code is not null;

create table if not exists public.work_areas (
  code text primary key,
  name text not null unique,
  detail_type text not null check (detail_type in ('sector','module','panel_type','room','none')),
  order_index integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.manufacturing_sectors (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null unique,
  description text not null default '',
  order_index integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.modules (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  module_type text not null default '',
  usage_suggested text not null default '',
  order_index integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  functional_group text not null default '',
  usage_suggested text not null default '',
  order_index integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.panel_types (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null unique,
  order_index integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.activity_area_links (
  activity_id uuid not null references public.activities(id) on delete cascade,
  area_code text not null references public.work_areas(code) on delete cascade,
  primary key(activity_id, area_code)
);

create table if not exists public.project_modules (
  project_id uuid not null references public.projects(id) on delete cascade,
  module_id uuid not null references public.modules(id) on delete cascade,
  display_name text not null default '',
  order_index integer not null default 0,
  active boolean not null default true,
  primary key(project_id, module_id)
);

alter table public.time_entries add column if not exists area_code text references public.work_areas(code);
alter table public.time_entries add column if not exists sector_id uuid references public.manufacturing_sectors(id);
alter table public.time_entries add column if not exists module_id uuid references public.modules(id);
alter table public.time_entries add column if not exists room_id uuid references public.rooms(id);
alter table public.time_entries add column if not exists panel_type_id uuid references public.panel_types(id);

create index if not exists idx_time_entries_area_v212 on public.time_entries(area_code);
create index if not exists idx_activity_area_links_area_v212 on public.activity_area_links(area_code);
create index if not exists idx_project_modules_project_v212 on public.project_modules(project_id);

alter table public.work_areas enable row level security;
alter table public.manufacturing_sectors enable row level security;
alter table public.modules enable row level security;
alter table public.rooms enable row level security;
alter table public.panel_types enable row level security;
alter table public.activity_area_links enable row level security;
alter table public.project_modules enable row level security;

grant select, insert, update, delete on public.work_areas, public.manufacturing_sectors,
  public.modules, public.rooms, public.panel_types, public.activity_area_links,
  public.project_modules to authenticated;


drop policy if exists work_areas_select_v212 on public.work_areas;
create policy work_areas_select_v212 on public.work_areas for select to authenticated using (true);
drop policy if exists work_areas_insert_v212 on public.work_areas;
create policy work_areas_insert_v212 on public.work_areas for insert to authenticated with check ((select public.is_manager()));
drop policy if exists work_areas_update_v212 on public.work_areas;
create policy work_areas_update_v212 on public.work_areas for update to authenticated using ((select public.is_manager())) with check ((select public.is_manager()));
drop policy if exists work_areas_delete_v212 on public.work_areas;
create policy work_areas_delete_v212 on public.work_areas for delete to authenticated using ((select public.is_manager()));

drop policy if exists manufacturing_sectors_select_v212 on public.manufacturing_sectors;
create policy manufacturing_sectors_select_v212 on public.manufacturing_sectors for select to authenticated using (true);
drop policy if exists manufacturing_sectors_insert_v212 on public.manufacturing_sectors;
create policy manufacturing_sectors_insert_v212 on public.manufacturing_sectors for insert to authenticated with check ((select public.is_manager()));
drop policy if exists manufacturing_sectors_update_v212 on public.manufacturing_sectors;
create policy manufacturing_sectors_update_v212 on public.manufacturing_sectors for update to authenticated using ((select public.is_manager())) with check ((select public.is_manager()));
drop policy if exists manufacturing_sectors_delete_v212 on public.manufacturing_sectors;
create policy manufacturing_sectors_delete_v212 on public.manufacturing_sectors for delete to authenticated using ((select public.is_manager()));

drop policy if exists modules_select_v212 on public.modules;
create policy modules_select_v212 on public.modules for select to authenticated using (true);
drop policy if exists modules_insert_v212 on public.modules;
create policy modules_insert_v212 on public.modules for insert to authenticated with check ((select public.is_manager()));
drop policy if exists modules_update_v212 on public.modules;
create policy modules_update_v212 on public.modules for update to authenticated using ((select public.is_manager())) with check ((select public.is_manager()));
drop policy if exists modules_delete_v212 on public.modules;
create policy modules_delete_v212 on public.modules for delete to authenticated using ((select public.is_manager()));

drop policy if exists rooms_select_v212 on public.rooms;
create policy rooms_select_v212 on public.rooms for select to authenticated using (true);
drop policy if exists rooms_insert_v212 on public.rooms;
create policy rooms_insert_v212 on public.rooms for insert to authenticated with check ((select public.is_manager()));
drop policy if exists rooms_update_v212 on public.rooms;
create policy rooms_update_v212 on public.rooms for update to authenticated using ((select public.is_manager())) with check ((select public.is_manager()));
drop policy if exists rooms_delete_v212 on public.rooms;
create policy rooms_delete_v212 on public.rooms for delete to authenticated using ((select public.is_manager()));

drop policy if exists panel_types_select_v212 on public.panel_types;
create policy panel_types_select_v212 on public.panel_types for select to authenticated using (true);
drop policy if exists panel_types_insert_v212 on public.panel_types;
create policy panel_types_insert_v212 on public.panel_types for insert to authenticated with check ((select public.is_manager()));
drop policy if exists panel_types_update_v212 on public.panel_types;
create policy panel_types_update_v212 on public.panel_types for update to authenticated using ((select public.is_manager())) with check ((select public.is_manager()));
drop policy if exists panel_types_delete_v212 on public.panel_types;
create policy panel_types_delete_v212 on public.panel_types for delete to authenticated using ((select public.is_manager()));

drop policy if exists activity_area_links_select_v212 on public.activity_area_links;
create policy activity_area_links_select_v212 on public.activity_area_links for select to authenticated using (true);
drop policy if exists activity_area_links_insert_v212 on public.activity_area_links;
create policy activity_area_links_insert_v212 on public.activity_area_links for insert to authenticated with check ((select public.is_manager()));
drop policy if exists activity_area_links_update_v212 on public.activity_area_links;
create policy activity_area_links_update_v212 on public.activity_area_links for update to authenticated using ((select public.is_manager())) with check ((select public.is_manager()));
drop policy if exists activity_area_links_delete_v212 on public.activity_area_links;
create policy activity_area_links_delete_v212 on public.activity_area_links for delete to authenticated using ((select public.is_manager()));

drop policy if exists project_modules_select_v212 on public.project_modules;
create policy project_modules_select_v212 on public.project_modules for select to authenticated using (true);
drop policy if exists project_modules_insert_v212 on public.project_modules;
create policy project_modules_insert_v212 on public.project_modules for insert to authenticated with check ((select public.is_manager()));
drop policy if exists project_modules_update_v212 on public.project_modules;
create policy project_modules_update_v212 on public.project_modules for update to authenticated using ((select public.is_manager())) with check ((select public.is_manager()));
drop policy if exists project_modules_delete_v212 on public.project_modules;
create policy project_modules_delete_v212 on public.project_modules for delete to authenticated using ((select public.is_manager()));

insert into public.work_areas(code,name,detail_type,order_index,active) values
 ('FAB','Fabricação','sector',1,true),
 ('MES','Montagem Estrutural','module',2,true),
 ('MPA','Montagem de Painéis','panel_type',3,true),
 ('MFI','Montagem Final','room',4,true),
 ('ADM','Administrativo','none',5,true)
on conflict(code) do update set name=excluded.name,detail_type=excluded.detail_type,order_index=excluded.order_index,active=true;
insert into public.projects(name,description,code,client_name,project_status,active) values ('Atividades internas da Engenharia de Manufatura','','INTERNO-EM','Interno','Em andamento',true) on conflict(name) do update set code=excluded.code,client_name=excluded.client_name,project_status=excluded.project_status,active=excluded.active;
insert into public.projects(name,description,code,client_name,project_status,active) values ('AWS','','AWS','','Em andamento',true) on conflict(name) do update set code=excluded.code,client_name=excluded.client_name,project_status=excluded.project_status,active=excluded.active;
insert into public.projects(name,description,code,client_name,project_status,active) values ('TB11','','TB11','','Em andamento',true) on conflict(name) do update set code=excluded.code,client_name=excluded.client_name,project_status=excluded.project_status,active=excluded.active;
insert into public.projects(name,description,code,client_name,project_status,active) values ('UFG','','UFG','','Em andamento',true) on conflict(name) do update set code=excluded.code,client_name=excluded.client_name,project_status=excluded.project_status,active=excluded.active;
insert into public.projects(name,description,code,client_name,project_status,active) values ('PRODEB','','PRODEB','','Em andamento',true) on conflict(name) do update set code=excluded.code,client_name=excluded.client_name,project_status=excluded.project_status,active=excluded.active;
insert into public.projects(name,description,code,client_name,project_status,active) values ('BARBADOS','','BARBADOS','','Em andamento',true) on conflict(name) do update set code=excluded.code,client_name=excluded.client_name,project_status=excluded.project_status,active=excluded.active;
insert into public.projects(name,description,code,client_name,project_status,active) values ('FOR','','FOR','','Em andamento',true) on conflict(name) do update set code=excluded.code,client_name=excluded.client_name,project_status=excluded.project_status,active=excluded.active;
insert into public.projects(name,description,code,client_name,project_status,active) values ('BOG','','BOG','','Em andamento',true) on conflict(name) do update set code=excluded.code,client_name=excluded.client_name,project_status=excluded.project_status,active=excluded.active;
insert into public.projects(name,description,code,client_name,project_status,active) values ('CRUSOE','','CRUSOE','','Em andamento',true) on conflict(name) do update set code=excluded.code,client_name=excluded.client_name,project_status=excluded.project_status,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MOD-GERAL','Geral do projeto','Geral','Usar quando a atividade abrange mais de um módulo ou o projeto completo',0,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MOD-NA','Não aplicável','Não aplicável','Usar para atividades internas sem vínculo físico',1,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M01','Módulo 01','Módulo padrão','Unidade modular numerada do projeto',2,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M02','Módulo 02','Módulo padrão','Unidade modular numerada do projeto',3,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M03','Módulo 03','Módulo padrão','Unidade modular numerada do projeto',4,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M04','Módulo 04','Módulo padrão','Unidade modular numerada do projeto',5,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M05','Módulo 05','Módulo padrão','Unidade modular numerada do projeto',6,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M06','Módulo 06','Módulo padrão','Unidade modular numerada do projeto',7,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M07','Módulo 07','Módulo padrão','Unidade modular numerada do projeto',8,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M08','Módulo 08','Módulo padrão','Unidade modular numerada do projeto',9,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M09','Módulo 09','Módulo padrão','Unidade modular numerada do projeto',10,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M10','Módulo 10','Módulo padrão','Unidade modular numerada do projeto',11,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M11','Módulo 11','Módulo padrão','Unidade modular numerada do projeto',12,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M12','Módulo 12','Módulo padrão','Unidade modular numerada do projeto',13,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M13','Módulo 13','Módulo padrão','Unidade modular numerada do projeto',14,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M14','Módulo 14','Módulo padrão','Unidade modular numerada do projeto',15,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M15','Módulo 15','Módulo padrão','Unidade modular numerada do projeto',16,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M16','Módulo 16','Módulo padrão','Unidade modular numerada do projeto',17,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M17','Módulo 17','Módulo padrão','Unidade modular numerada do projeto',18,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M18','Módulo 18','Módulo padrão','Unidade modular numerada do projeto',19,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M19','Módulo 19','Módulo padrão','Unidade modular numerada do projeto',20,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M20','Módulo 20','Módulo padrão','Unidade modular numerada do projeto',21,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M21','Módulo 21','Módulo padrão','Unidade modular numerada do projeto',22,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M22','Módulo 22','Módulo padrão','Unidade modular numerada do projeto',23,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M23','Módulo 23','Módulo padrão','Unidade modular numerada do projeto',24,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M24','Módulo 24','Módulo padrão','Unidade modular numerada do projeto',25,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M25','Módulo 25','Módulo padrão','Unidade modular numerada do projeto',26,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M26','Módulo 26','Módulo padrão','Unidade modular numerada do projeto',27,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M27','Módulo 27','Módulo padrão','Unidade modular numerada do projeto',28,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M28','Módulo 28','Módulo padrão','Unidade modular numerada do projeto',29,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M29','Módulo 29','Módulo padrão','Unidade modular numerada do projeto',30,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M30','Módulo 30','Módulo padrão','Unidade modular numerada do projeto',31,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M31','Módulo 31','Módulo padrão','Unidade modular numerada do projeto',32,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('M32','Módulo 32','Módulo padrão','Unidade modular numerada do projeto',33,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MONO01','Monobloco 01','Monobloco','Opção adicional para projetos com esta configuração',34,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MONO02','Monobloco 02','Monobloco','Opção adicional para projetos com esta configuração',35,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MONO03','Monobloco 03','Monobloco','Opção adicional para projetos com esta configuração',36,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MONO04','Monobloco 04','Monobloco','Opção adicional para projetos com esta configuração',37,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MONO05','Monobloco 05','Monobloco','Opção adicional para projetos com esta configuração',38,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MONO06','Monobloco 06','Monobloco','Opção adicional para projetos com esta configuração',39,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MONO07','Monobloco 07','Monobloco','Opção adicional para projetos com esta configuração',40,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MONO08','Monobloco 08','Monobloco','Opção adicional para projetos com esta configuração',41,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MB01','Minibloco 01','Minibloco','Opção adicional para projetos com esta configuração',42,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MB02','Minibloco 02','Minibloco','Opção adicional para projetos com esta configuração',43,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MB03','Minibloco 03','Minibloco','Opção adicional para projetos com esta configuração',44,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MB04','Minibloco 04','Minibloco','Opção adicional para projetos com esta configuração',45,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MB05','Minibloco 05','Minibloco','Opção adicional para projetos com esta configuração',46,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MB06','Minibloco 06','Minibloco','Opção adicional para projetos com esta configuração',47,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MB07','Minibloco 07','Minibloco','Opção adicional para projetos com esta configuração',48,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MB08','Minibloco 08','Minibloco','Opção adicional para projetos com esta configuração',49,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('POD01','Mini POD 01','Mini POD','Opção adicional para projetos com esta configuração',50,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('POD02','Mini POD 02','Mini POD','Opção adicional para projetos com esta configuração',51,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('POD03','Mini POD 03','Mini POD','Opção adicional para projetos com esta configuração',52,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('POD04','Mini POD 04','Mini POD','Opção adicional para projetos com esta configuração',53,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('POD05','Mini POD 05','Mini POD','Opção adicional para projetos com esta configuração',54,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('POD06','Mini POD 06','Mini POD','Opção adicional para projetos com esta configuração',55,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('POD07','Mini POD 07','Mini POD','Opção adicional para projetos com esta configuração',56,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('POD08','Mini POD 08','Mini POD','Opção adicional para projetos com esta configuração',57,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('SKID01','Skid 01','Skid','Opção adicional para projetos com esta configuração',58,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('SKID02','Skid 02','Skid','Opção adicional para projetos com esta configuração',59,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('SKID03','Skid 03','Skid','Opção adicional para projetos com esta configuração',60,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('SKID04','Skid 04','Skid','Opção adicional para projetos com esta configuração',61,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('SKID05','Skid 05','Skid','Opção adicional para projetos com esta configuração',62,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('SKID06','Skid 06','Skid','Opção adicional para projetos com esta configuração',63,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('SKID07','Skid 07','Skid','Opção adicional para projetos com esta configuração',64,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('SKID08','Skid 08','Skid','Opção adicional para projetos com esta configuração',65,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('HVAC01','HVAC Catcher 01','HVAC Catcher','Opção adicional para projetos com esta configuração',66,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('HVAC02','HVAC Catcher 02','HVAC Catcher','Opção adicional para projetos com esta configuração',67,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('HVAC03','HVAC Catcher 03','HVAC Catcher','Opção adicional para projetos com esta configuração',68,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('HVAC04','HVAC Catcher 04','HVAC Catcher','Opção adicional para projetos com esta configuração',69,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('HVAC05','HVAC Catcher 05','HVAC Catcher','Opção adicional para projetos com esta configuração',70,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('HVAC06','HVAC Catcher 06','HVAC Catcher','Opção adicional para projetos com esta configuração',71,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('HVAC07','HVAC Catcher 07','HVAC Catcher','Opção adicional para projetos com esta configuração',72,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('HVAC08','HVAC Catcher 08','HVAC Catcher','Opção adicional para projetos com esta configuração',73,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('BASE01','Base modular 01','Base','Opção adicional para projetos com esta configuração',74,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('BASE02','Base modular 02','Base','Opção adicional para projetos com esta configuração',75,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('BASE03','Base modular 03','Base','Opção adicional para projetos com esta configuração',76,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('BASE04','Base modular 04','Base','Opção adicional para projetos com esta configuração',77,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('BASE05','Base modular 05','Base','Opção adicional para projetos com esta configuração',78,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('BASE06','Base modular 06','Base','Opção adicional para projetos com esta configuração',79,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('BASE07','Base modular 07','Base','Opção adicional para projetos com esta configuração',80,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('BASE08','Base modular 08','Base','Opção adicional para projetos com esta configuração',81,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('TETO01','Teto modular 01','Teto','Opção adicional para projetos com esta configuração',82,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('TETO02','Teto modular 02','Teto','Opção adicional para projetos com esta configuração',83,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('TETO03','Teto modular 03','Teto','Opção adicional para projetos com esta configuração',84,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('TETO04','Teto modular 04','Teto','Opção adicional para projetos com esta configuração',85,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('TETO05','Teto modular 05','Teto','Opção adicional para projetos com esta configuração',86,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('TETO06','Teto modular 06','Teto','Opção adicional para projetos com esta configuração',87,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('TETO07','Teto modular 07','Teto','Opção adicional para projetos com esta configuração',88,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('TETO08','Teto modular 08','Teto','Opção adicional para projetos com esta configuração',89,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('AREA-EXT','Área externa do projeto','Área externa','Áreas externas, bases, passarelas e interligações',90,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('CAMPO','Campo / site do cliente','Campo','Atividades executadas no local de implantação',91,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('FAT-AREA','Área de FAT e testes','Área de testes','Atividades de montagem, inspeção e testes de fábrica',92,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MOD-COMP','Módulo compartilhado','Compartilhado','Atividades que envolvem uma unidade compartilhada por mais de uma sala',93,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MOD-INT','Módulo de interligação','Interligação','Módulo dedicado a interfaces e interligações entre unidades',94,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MOD-TRANS','Módulo de transição','Transição','Unidade de transição entre módulos ou sistemas',95,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MOD-AUX','Módulo auxiliar','Auxiliar','Unidade auxiliar de apoio ao sistema principal',96,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MOD-PIL','Módulo piloto / protótipo','Piloto','Protótipo, mock-up ou primeira unidade para validação',97,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MOD-TESTE','Módulo de testes','Teste','Unidade destinada a montagem experimental ou testes',98,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('MOD-EXP','Módulo de embalagem / expedição','Expedição','Unidade em preparação para transporte e expedição',99,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('PASS-TEC','Passarela técnica','Passarela','Passarela, ponte ou conexão técnica modular',100,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('EH01','E-House 01','E-House','Opção adicional conforme configuração do projeto',101,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('EH02','E-House 02','E-House','Opção adicional conforme configuração do projeto',102,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('EH03','E-House 03','E-House','Opção adicional conforme configuração do projeto',103,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('EH04','E-House 04','E-House','Opção adicional conforme configuração do projeto',104,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('EH05','E-House 05','E-House','Opção adicional conforme configuração do projeto',105,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('EH06','E-House 06','E-House','Opção adicional conforme configuração do projeto',106,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('EH07','E-House 07','E-House','Opção adicional conforme configuração do projeto',107,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('EH08','E-House 08','E-House','Opção adicional conforme configuração do projeto',108,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('PDU01','Skid elétrico / PDU 01','Skid elétrico','Opção adicional conforme configuração do projeto',109,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('PDU02','Skid elétrico / PDU 02','Skid elétrico','Opção adicional conforme configuração do projeto',110,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('PDU03','Skid elétrico / PDU 03','Skid elétrico','Opção adicional conforme configuração do projeto',111,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('PDU04','Skid elétrico / PDU 04','Skid elétrico','Opção adicional conforme configuração do projeto',112,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('PDU05','Skid elétrico / PDU 05','Skid elétrico','Opção adicional conforme configuração do projeto',113,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('PDU06','Skid elétrico / PDU 06','Skid elétrico','Opção adicional conforme configuração do projeto',114,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('PDU07','Skid elétrico / PDU 07','Skid elétrico','Opção adicional conforme configuração do projeto',115,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('PDU08','Skid elétrico / PDU 08','Skid elétrico','Opção adicional conforme configuração do projeto',116,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('CHW01','Skid de água gelada 01','Skid HVAC','Opção adicional conforme configuração do projeto',117,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('CHW02','Skid de água gelada 02','Skid HVAC','Opção adicional conforme configuração do projeto',118,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('CHW03','Skid de água gelada 03','Skid HVAC','Opção adicional conforme configuração do projeto',119,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('CHW04','Skid de água gelada 04','Skid HVAC','Opção adicional conforme configuração do projeto',120,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('CHW05','Skid de água gelada 05','Skid HVAC','Opção adicional conforme configuração do projeto',121,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('CHW06','Skid de água gelada 06','Skid HVAC','Opção adicional conforme configuração do projeto',122,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('CHW07','Skid de água gelada 07','Skid HVAC','Opção adicional conforme configuração do projeto',123,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('CHW08','Skid de água gelada 08','Skid HVAC','Opção adicional conforme configuração do projeto',124,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('UTIL01','Módulo de utilidades 01','Utilidades','Opção adicional conforme configuração do projeto',125,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('UTIL02','Módulo de utilidades 02','Utilidades','Opção adicional conforme configuração do projeto',126,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('UTIL03','Módulo de utilidades 03','Utilidades','Opção adicional conforme configuração do projeto',127,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('UTIL04','Módulo de utilidades 04','Utilidades','Opção adicional conforme configuração do projeto',128,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('UTIL05','Módulo de utilidades 05','Utilidades','Opção adicional conforme configuração do projeto',129,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('UTIL06','Módulo de utilidades 06','Utilidades','Opção adicional conforme configuração do projeto',130,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('UTIL07','Módulo de utilidades 07','Utilidades','Opção adicional conforme configuração do projeto',131,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values ('UTIL08','Módulo de utilidades 08','Utilidades','Opção adicional conforme configuração do projeto',132,true) on conflict(code) do update set name=excluded.name,module_type=excluded.module_type,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('SALA-GERAL','Geral do módulo','Geral','Usar quando a atividade abrange todo o módulo',0,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('SALA-NA','Não aplicável','Não aplicável','Atividade sem vínculo com uma sala específica',1,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('DH','Data Hall','Operacional','Sala principal de TI',2,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('SE','Sala Elétrica','Elétrica','Sala elétrica geral',3,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('BT','Sala de Baixa Tensão','Elétrica','Painéis e distribuição BT',4,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('MT','Sala de Média Tensão','Elétrica','Cubículos e sistemas de MT',5,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('UPS','Sala de UPS','Elétrica','UPS e distribuição associada',6,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('BAT','Sala de Baterias','Elétrica','Bancos de baterias e acessórios',7,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('TRAFO','Sala de Transformadores','Elétrica','Transformadores e conexões',8,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('GER','Sala de Geradores','Elétrica/Mecânica','Geradores e sistemas auxiliares',9,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('TELECOM','Sala de Telecom / MMR','Telecom','Telecomunicações e meet-me room',10,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('CTRL','Sala de Controle / BMS','Automação','Controle, supervisão e BMS',11,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('CFTV','Sala de Segurança / CFTV','Segurança eletrônica','CFTV e controle de acesso',12,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('SDACI','Sala / Área de SDACI','Incêndio','Detecção, alarme e combate a incêndio',13,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('HVAC-SALA','Sala Mecânica / HVAC','HVAC','Climatização e equipamentos mecânicos',14,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('AGUA-GEL','Sala de Bombas / Água Gelada','HVAC/Hidráulica','Bombas, manifolds e tubulação de água gelada',15,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('CATCHER','HVAC Catcher','HVAC','Unidade catcher acoplada ao Data Hall',16,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('COR-FRIO','Corredor Frio','Data Hall','Corredor de insuflamento frio',17,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('COR-QUENTE','Corredor Quente','Data Hall','Corredor de retorno quente',18,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('PLENUM','Plenum','HVAC','Plenum de insuflamento ou retorno',19,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('COR-TEC','Corredor Técnico','Infraestrutura','Passagem técnica e manutenção',20,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('COR-ACESSO','Corredor de Acesso','Arquitetura','Circulação interna',21,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('ANTESSALA','Antessala','Arquitetura','Área de transição e acesso',22,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('COBERTURA','Cobertura / Teto','Estrutural','Teto, cobertura e componentes superiores',23,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('BASE-PISO','Base / Piso Inferior','Estrutural','Base estrutural e piso inferior',24,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('PISO-TEC','Piso Técnico / Elevado','Arquitetura','Piso elevado e infraestrutura associada',25,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('PAREDE-INT','Paredes Internas','Arquitetura','Paredes, divisórias e fechamentos internos',26,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('FACHADA','Paredes Externas / Fachada','Arquitetura','Envoltória e acabamento externo',27,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('CF','Compartimentação Corta-Fogo','Incêndio','Selagens, portas e barreiras corta-fogo',28,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('INTERCON','Zona de Interconexão entre Módulos','Integração','Interfaces e acoplamentos entre módulos',29,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('AREA-TEC-EXT','Área Técnica Externa','Infraestrutura','Equipamentos e infraestrutura externos',30,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('EXPED','Área de Embalagem / Expedição','Logística','Embalagem, amarração e expedição',31,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('FAB','Área de Fabricação','Produção','Corte, dobra, solda e usinagem',32,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('PINT','Área de Pintura / Jateamento','Produção','Preparação de superfície e pintura',33,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('MONT-EST','Área de Montagem Estrutural','Produção','Bases, steel frame e estrutura',34,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('MONT-FINAL','Área de Montagem Final','Produção','Integração e acabamentos finais',35,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('PAINEIS','Área de Montagem de Painéis','Produção','Montagem de painéis e barramentos',36,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('TESTES','Área de Testes / FAT','Testes','Inspeções, testes e FAT',37,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('ALMOX','Almoxarifado / Preparação de Kits','Logística','Separação, conferência e preparação de materiais',38,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('OUTRA','Outra sala / área','Outra','Cadastrar nova opção quando recorrente',39,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('NOC','Sala NOC / Operação','Operação','Centro de operação e monitoramento',40,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('PDU-RPP','Sala PDU / RPP','Elétrica','Distribuição elétrica próxima às cargas de TI',41,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('QGBT-MCC','Sala QGBT / MCC','Elétrica','Quadros gerais, CCM e distribuição de potência',42,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('PROT-MED','Sala de Proteção e Medição','Elétrica','Relés, medição, proteção e controle',43,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('SAUX','Sala de Serviços Auxiliares','Elétrica','Serviços auxiliares CA/CC',44,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('RET','Sala de Retificadores','Elétrica','Retificadores e sistemas CC',45,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('BCAP','Sala de Banco de Capacitores','Elétrica','Correção de fator de potência e filtros',46,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('CHILLER','Sala / Área de Chillers','HVAC','Chillers e equipamentos associados',47,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('CRAH','Sala / Área de CRAH-CRAC','HVAC','Unidades de tratamento e climatização do Data Hall',48,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('MANIFOLD','Área de Manifold','HVAC/Hidráulica','Manifolds, válvulas e distribuição hidráulica',49,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('BOMB-INC','Sala de Bombas de Incêndio','Incêndio','Bombas e sistemas hidráulicos de incêndio',50,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('GAS-INC','Sala de Cilindros / Supressão por Gás','Incêndio','Cilindros e sistemas de supressão por gás',51,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('MANTRAP','Eclusa / Mantrap','Segurança','Controle físico de acesso',52,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('ROOFTOP','Cobertura Técnica / Rooftop','Infraestrutura','Equipamentos e interligações na cobertura',53,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('PASSARELA','Passarela / Ponte Técnica','Infraestrutura','Conexões, travessias e acesso técnico',54,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('DOCA','Doca / Carga e Descarga','Logística','Recebimento, carregamento e descarregamento',55,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('STAGING','Área de Staging / Pré-montagem','Logística','Pré-montagem, separação e preparação de unidades',56,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('KIT','Área de Kitting / Preparação de Kits','Logística','Montagem e conferência de kits de produção',57,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('LASER','Área de Corte Laser / Lantek','Fabricação','Programação, nesting e corte a laser',58,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('SERRA-FUR','Área de Serra e Furação','Fabricação','Serramento, furação e preparação de perfis',59,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('DOBRA','Área de Dobra e Conformação','Fabricação','Dobra de chapas, perfis e barramentos',60,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('SOLDA','Área de Soldagem e Caldeiraria','Fabricação','Soldagem, caldeiraria e subconjuntos',61,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('JATO','Área de Jateamento','Pintura','Preparação de superfície por jateamento',62,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('CAB-PINT','Cabine / Área de Pintura','Pintura','Pintura líquida, eletrostática e cura',63,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('MONT-MEC','Área de Montagem Mecânica','Montagem','Montagem de equipamentos e sistemas mecânicos',64,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('MONT-ELET','Área de Montagem Elétrica','Montagem','Infraestrutura, cabos, eletrocalhas e ligações',65,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('PAINEL-BT','Área de Painéis BT','Painéis','Montagem de painéis de baixa tensão',66,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('PAINEL-MT','Área de Painéis MT','Painéis','Montagem de painéis de média tensão',67,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('BARRAMENTO','Área de Fabricação de Barramentos','Painéis','Corte, dobra, furação e preparação de barramentos',68,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('BANC-ELET','Bancada Elétrica','Painéis','Montagem, crimpagem e testes de componentes elétricos',69,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('BANC-MEC','Bancada Mecânica','Montagem','Ajustes, preparação e montagem de componentes mecânicos',70,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('INSP','Área de Inspeção da Qualidade','Qualidade','Inspeções dimensionais, visuais e de processo',71,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('LAB-TESTE','Laboratório / Bancada de Testes','Testes','Ensaios, medições e validações técnicas',72,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('QUARENT','Área de Quarentena / Material Não Conforme','Qualidade','Segregação e tratativa de materiais não conformes',73,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values ('RETRAB','Área de Retrabalho','Produção','Ajustes, correções e retrabalhos controlados',74,true) on conflict(code) do update set name=excluded.name,functional_group=excluded.functional_group,usage_suggested=excluded.usage_suggested,order_index=excluded.order_index,active=excluded.active;
insert into public.manufacturing_sectors(code,name,description,order_index,active) values ('SETOR-GERAL','Geral da fabricação','Atividade que abrange mais de um setor de fabricação.',0,true) on conflict(code) do update set name=excluded.name,description=excluded.description,order_index=excluded.order_index,active=true;
insert into public.manufacturing_sectors(code,name,description,order_index,active) values ('FAB','Área de Fabricação','Corte, dobra, solda e usinagem',1,true) on conflict(code) do update set name=excluded.name,description=excluded.description,order_index=excluded.order_index,active=true;
insert into public.manufacturing_sectors(code,name,description,order_index,active) values ('PINT','Área de Pintura / Jateamento','Preparação de superfície e pintura',2,true) on conflict(code) do update set name=excluded.name,description=excluded.description,order_index=excluded.order_index,active=true;
insert into public.manufacturing_sectors(code,name,description,order_index,active) values ('STAGING','Área de Staging / Pré-montagem','Pré-montagem, separação e preparação de unidades',3,true) on conflict(code) do update set name=excluded.name,description=excluded.description,order_index=excluded.order_index,active=true;
insert into public.manufacturing_sectors(code,name,description,order_index,active) values ('KIT','Área de Kitting / Preparação de Kits','Montagem e conferência de kits de produção',4,true) on conflict(code) do update set name=excluded.name,description=excluded.description,order_index=excluded.order_index,active=true;
insert into public.manufacturing_sectors(code,name,description,order_index,active) values ('LASER','Área de Corte Laser / Lantek','Programação, nesting e corte a laser',5,true) on conflict(code) do update set name=excluded.name,description=excluded.description,order_index=excluded.order_index,active=true;
insert into public.manufacturing_sectors(code,name,description,order_index,active) values ('SERRA-FUR','Área de Serra e Furação','Serramento, furação e preparação de perfis',6,true) on conflict(code) do update set name=excluded.name,description=excluded.description,order_index=excluded.order_index,active=true;
insert into public.manufacturing_sectors(code,name,description,order_index,active) values ('DOBRA','Área de Dobra e Conformação','Dobra de chapas, perfis e barramentos',7,true) on conflict(code) do update set name=excluded.name,description=excluded.description,order_index=excluded.order_index,active=true;
insert into public.manufacturing_sectors(code,name,description,order_index,active) values ('SOLDA','Área de Soldagem e Caldeiraria','Soldagem, caldeiraria e subconjuntos',8,true) on conflict(code) do update set name=excluded.name,description=excluded.description,order_index=excluded.order_index,active=true;
insert into public.manufacturing_sectors(code,name,description,order_index,active) values ('JATO','Área de Jateamento','Preparação de superfície por jateamento',9,true) on conflict(code) do update set name=excluded.name,description=excluded.description,order_index=excluded.order_index,active=true;
insert into public.manufacturing_sectors(code,name,description,order_index,active) values ('CAB-PINT','Cabine / Área de Pintura','Pintura líquida, eletrostática e cura',10,true) on conflict(code) do update set name=excluded.name,description=excluded.description,order_index=excluded.order_index,active=true;
insert into public.manufacturing_sectors(code,name,description,order_index,active) values ('INSP','Área de Inspeção da Qualidade','Inspeções dimensionais, visuais e de processo',11,true) on conflict(code) do update set name=excluded.name,description=excluded.description,order_index=excluded.order_index,active=true;
insert into public.manufacturing_sectors(code,name,description,order_index,active) values ('RETRAB','Área de Retrabalho','Ajustes, correções e retrabalhos controlados',12,true) on conflict(code) do update set name=excluded.name,description=excluded.description,order_index=excluded.order_index,active=true;
insert into public.manufacturing_sectors(code,name,description,order_index,active) values ('FAB','Fabricação Mecânica','Corte, furação, dobra, solda, caldeiraria e atendimento à fabricação',13,true) on conflict(code) do update set name=excluded.name,description=excluded.description,order_index=excluded.order_index,active=true;
insert into public.manufacturing_sectors(code,name,description,order_index,active) values ('SETOR-OUTRO','Outro setor de fabricação','Usar quando o setor específico ainda não estiver cadastrado.',14,true) on conflict(code) do update set name=excluded.name,description=excluded.description,order_index=excluded.order_index,active=true;
insert into public.panel_types(code,name,order_index,active) values ('UPS','UPS',0,true) on conflict(code) do update set name=excluded.name,order_index=excluded.order_index,active=true;
insert into public.panel_types(code,name,order_index,active) values ('BMS','BMS',1,true) on conflict(code) do update set name=excluded.name,order_index=excluded.order_index,active=true;
insert into public.panel_types(code,name,order_index,active) values ('RPP','RPP',2,true) on conflict(code) do update set name=excluded.name,order_index=excluded.order_index,active=true;
insert into public.panel_types(code,name,order_index,active) values ('QGBT','QGBT',3,true) on conflict(code) do update set name=excluded.name,order_index=excluded.order_index,active=true;
insert into public.panel_types(code,name,order_index,active) values ('PDU','PDU',4,true) on conflict(code) do update set name=excluded.name,order_index=excluded.order_index,active=true;
insert into public.panel_types(code,name,order_index,active) values ('ATS','ATS',5,true) on conflict(code) do update set name=excluded.name,order_index=excluded.order_index,active=true;
insert into public.panel_types(code,name,order_index,active) values ('CCM','CCM',6,true) on conflict(code) do update set name=excluded.name,order_index=excluded.order_index,active=true;
insert into public.panel_types(code,name,order_index,active) values ('PBT','Painel BT',7,true) on conflict(code) do update set name=excluded.name,order_index=excluded.order_index,active=true;
insert into public.panel_types(code,name,order_index,active) values ('PMT','Painel MT',8,true) on conflict(code) do update set name=excluded.name,order_index=excluded.order_index,active=true;
insert into public.panel_types(code,name,order_index,active) values ('AUT','Painel de Automação',9,true) on conflict(code) do update set name=excluded.name,order_index=excluded.order_index,active=true;
insert into public.panel_types(code,name,order_index,active) values ('CTRL','Painel de Controle',10,true) on conflict(code) do update set name=excluded.name,order_index=excluded.order_index,active=true;
insert into public.panel_types(code,name,order_index,active) values ('AUX','Painel Auxiliar',11,true) on conflict(code) do update set name=excluded.name,order_index=excluded.order_index,active=true;
insert into public.panel_types(code,name,order_index,active) values ('OUTRO','Outro tipo de painel',12,true) on conflict(code) do update set name=excluded.name,order_index=excluded.order_index,active=true;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Planejamento diário das atividades','Demanda','', '', '', 'EM-GES-001','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: planejamento diário das atividades.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-001' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Planejamento semanal das entregas','Demanda','', '', '', 'EM-GES-002','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: planejamento semanal das entregas.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-002' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Priorização de demandas do projeto','Demanda','', '', '', 'EM-GES-003','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: priorização de demandas do projeto.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-003' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Acompanhamento do cronograma de manufatura','Demanda','', '', '', 'EM-GES-004','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: acompanhamento do cronograma de manufatura.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-004' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Follow-up de pendências e bloqueios','Demanda','', '', '', 'EM-GES-005','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: follow-up de pendências e bloqueios.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-005' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Reunião de projeto','Demanda','', '', '', 'EM-GES-006','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: reunião de projeto.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-006' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Reunião com Produção','Demanda','', '', '', 'EM-GES-007','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: reunião com produção.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-007' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Reunião com Engenharia de Produto / DFMA','Demanda','', '', '', 'EM-GES-008','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: reunião com engenharia de produto / dfma.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-008' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Reunião com Qualidade','Demanda','', '', '', 'EM-GES-009','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: reunião com qualidade.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-009' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Reunião com fornecedor ou cliente','Demanda','', '', '', 'EM-GES-010','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: reunião com fornecedor ou cliente.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-010' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('SQDC / OBEYA / gestão visual','Demanda','', '', '', 'EM-GES-011','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: sqdc / obeya / gestão visual.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-011' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Atualização de indicadores e relatórios','Demanda','', '', '', 'EM-GES-012','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: atualização de indicadores e relatórios.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-012' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Preparação de apresentação técnica','Demanda','', '', '', 'EM-GES-013','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: preparação de apresentação técnica.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-013' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Treinamento, integração ou capacitação','Demanda','', '', '', 'EM-GES-014','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: treinamento, integração ou capacitação.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-014' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Distribuição e acompanhamento de tarefas da equipe','Demanda','', '', '', 'EM-GES-015','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: distribuição e acompanhamento de tarefas da equipe.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-015' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Atualização de plano de ação','Demanda','', '', '', 'EM-GES-016','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: atualização de plano de ação.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-016' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Gestão de riscos, restrições e bloqueios','Demanda','', '', '', 'EM-GES-017','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: gestão de riscos, restrições e bloqueios.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-017' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Reunião com PCP e planejamento','Demanda','', '', '', 'EM-GES-018','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: reunião com pcp e planejamento.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-018' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Reunião com Compras ou Suprimentos','Demanda','', '', '', 'EM-GES-019','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: reunião com compras ou suprimentos.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-019' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Reunião de alinhamento multidisciplinar','Demanda','', '', '', 'EM-GES-020','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: reunião de alinhamento multidisciplinar.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-020' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Atualização do status das demandas','Demanda','', '', '', 'EM-GES-021','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: atualização do status das demandas.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-021' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Organização e priorização do backlog','Demanda','', '', '', 'EM-GES-022','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: organização e priorização do backlog.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-022' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Conferência de apontamentos e horas da equipe','Demanda','', '', '', 'EM-GES-023','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: conferência de apontamentos e horas da equipe.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-023' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Fechamento e registro de atividades concluídas','Demanda','', '', '', 'EM-GES-024','GES','Gestão e Coordenação','Transversal','Rotina / Planejada','Registrar o objeto analisado, a ação executada e o resultado relacionado a: fechamento e registro de atividades concluídas.','Recomendado',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-GES-024' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de fabricabilidade','Demanda','', '', '', 'EM-DFM-001','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de fabricabilidade.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-001' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de montabilidade','Demanda','', '', '', 'EM-DFM-002','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de montabilidade.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-002' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de acesso para fabricação e montagem','Demanda','', '', '', 'EM-DFM-003','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de acesso para fabricação e montagem.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-003' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de acesso para manutenção','Demanda','', '', '', 'EM-DFM-004','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de acesso para manutenção.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-004' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de interfaces entre disciplinas','Demanda','', '', '', 'EM-DFM-005','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de interfaces entre disciplinas.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-005' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de interferências','Demanda','', '', '', 'EM-DFM-006','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de interferências.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-006' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Verificação de cotas, tolerâncias e detalhes construtivos','Demanda','', '', '', 'EM-DFM-007','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: verificação de cotas, tolerâncias e detalhes construtivos.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-007' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Verificação de materiais e especificações','Demanda','', '', '', 'EM-DFM-008','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: verificação de materiais e especificações.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-008' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Verificação de BOM / lista de materiais','Demanda','', '', '', 'EM-DFM-009','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: verificação de bom / lista de materiais.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-009' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de Red Pen / marcações de campo','Demanda','', '', '', 'EM-DFM-010','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de red pen / marcações de campo.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-010' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de DANE ou solicitação de alteração','Demanda','', '', '', 'EM-DFM-011','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de dane ou solicitação de alteração.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-011' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Revisão técnica de desenho no Fusion','Demanda','', '', '', 'EM-DFM-012','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: revisão técnica de desenho no fusion.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-012' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Aprovação e liberação de desenho no Fusion','Demanda','', '', '', 'EM-DFM-013','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: aprovação e liberação de desenho no fusion.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-013' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Devolução de desenho para correção','Demanda','', '', '', 'EM-DFM-014','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: devolução de desenho para correção.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-014' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Tratativa de alteração de engenharia / CCB','Demanda','', '', '', 'EM-DFM-015','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: tratativa de alteração de engenharia / ccb.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-015' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Padronização, simplificação ou nacionalização do produto','Demanda','', '', '', 'EM-DFM-016','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: padronização, simplificação ou nacionalização do produto.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-016' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-016' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-016' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-016' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-016' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Revisão de modelo 3D','Demanda','', '', '', 'EM-DFM-017','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: revisão de modelo 3d.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-017' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-017' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-017' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-017' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-017' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Comparação entre modelo 3D e desenho 2D','Demanda','', '', '', 'EM-DFM-018','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: comparação entre modelo 3d e desenho 2d.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-018' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-018' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-018' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-018' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-018' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de peça especial ou solução não padronizada','Demanda','', '', '', 'EM-DFM-019','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de peça especial ou solução não padronizada.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-019' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-019' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-019' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-019' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-019' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Avaliação de envelope, folgas e zonas de acesso','Demanda','', '', '', 'EM-DFM-020','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: avaliação de envelope, folgas e zonas de acesso.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-020' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-020' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-020' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-020' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-020' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de transporte e embalagem no desenvolvimento do produto','Demanda','', '', '', 'EM-DFM-021','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de transporte e embalagem no desenvolvimento do produto.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-021' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-021' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-021' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-021' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-021' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de manutenção e substituição de componentes','Demanda','', '', '', 'EM-DFM-022','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de manutenção e substituição de componentes.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-022' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-022' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-022' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-022' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-022' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Consolidação de comentários de desenho','Demanda','', '', '', 'EM-DFM-023','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: consolidação de comentários de desenho.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-023' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-023' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-023' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-023' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-023' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Verificação final antes da liberação para produção','Demanda','', '', '', 'EM-DFM-024','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: verificação final antes da liberação para produção.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-024' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-024' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-024' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-024' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-024' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Validação da alteração incorporada ao desenho','Demanda','', '', '', 'EM-DFM-025','DFM','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: validação da alteração incorporada ao desenho.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-DFM-025' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-DFM-025' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-DFM-025' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-DFM-025' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DFM-025' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Desenvolvimento de processo de fabricação','Demanda','', '', '', 'EM-PRC-001','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: desenvolvimento de processo de fabricação.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-001' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Desenvolvimento de processo de montagem','Demanda','', '', '', 'EM-PRC-002','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: desenvolvimento de processo de montagem.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-002' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Revisão e otimização de processo existente','Demanda','', '', '', 'EM-PRC-003','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: revisão e otimização de processo existente.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-003' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição da sequência de fabricação','Demanda','', '', '', 'EM-PRC-004','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição da sequência de fabricação.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-004' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição da sequência de montagem','Demanda','', '', '', 'EM-PRC-005','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição da sequência de montagem.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-005' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição de método, máquinas, ferramentas e recursos','Demanda','', '', '', 'EM-PRC-006','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição de método, máquinas, ferramentas e recursos.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-006' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Elaboração de instrução de trabalho','Demanda','', '', '', 'EM-PRC-007','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: elaboração de instrução de trabalho.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-007' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Revisão de instrução de trabalho','Demanda','', '', '', 'EM-PRC-008','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: revisão de instrução de trabalho.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-008' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Elaboração de auxílio visual ou padrão operacional','Demanda','', '', '', 'EM-PRC-009','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: elaboração de auxílio visual ou padrão operacional.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-009' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Estudo de tempos','Demanda','', '', '', 'EM-PRC-010','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: estudo de tempos.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-010' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição de tempo padrão e tempo de ciclo','Demanda','', '', '', 'EM-PRC-011','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição de tempo padrão e tempo de ciclo.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-011' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de capacidade produtiva','Demanda','', '', '', 'EM-PRC-012','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de capacidade produtiva.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-012' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Dimensionamento de mão de obra','Demanda','', '', '', 'EM-PRC-013','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: dimensionamento de mão de obra.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-013' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Balanceamento de atividades ou linha','Demanda','', '', '', 'EM-PRC-014','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: balanceamento de atividades ou linha.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-014' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Desenvolvimento ou alteração de layout','Demanda','', '', '', 'EM-PRC-015','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: desenvolvimento ou alteração de layout.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-015' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Acompanhamento de primeira execução / try-out','Demanda','', '', '', 'EM-PRC-016','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: acompanhamento de primeira execução / try-out.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-016' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-016' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-016' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-016' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-016' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Validação e liberação de processo','Demanda','', '', '', 'EM-PRC-017','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: validação e liberação de processo.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-017' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-017' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-017' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-017' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-017' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Treinamento da produção e acompanhamento de ramp-up','Demanda','', '', '', 'EM-PRC-018','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: treinamento da produção e acompanhamento de ramp-up.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-018' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-018' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-018' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-018' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-018' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Levantamento do processo atual em fábrica','Demanda','', '', '', 'EM-PRC-019','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: levantamento do processo atual em fábrica.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-019' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-019' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-019' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-019' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-019' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Criação de fluxograma ou mapa de processo','Demanda','', '', '', 'EM-PRC-020','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: criação de fluxograma ou mapa de processo.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-020' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-020' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-020' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-020' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-020' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição de pontos de inspeção e controle','Demanda','', '', '', 'EM-PRC-021','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição de pontos de inspeção e controle.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-021' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-021' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-021' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-021' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-021' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Elaboração de checklist de processo','Demanda','', '', '', 'EM-PRC-022','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: elaboração de checklist de processo.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-022' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-022' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-022' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-022' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-022' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Preparação do plano de industrialização','Demanda','', '', '', 'EM-PRC-023','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: preparação do plano de industrialização.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-023' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-023' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-023' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-023' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-023' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição de kit de fabricação ou montagem','Demanda','', '', '', 'EM-PRC-024','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição de kit de fabricação ou montagem.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-024' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-024' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-024' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-024' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-024' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição de embalagem, amarração e proteção','Demanda','', '', '', 'EM-PRC-025','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição de embalagem, amarração e proteção.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-025' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-025' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-025' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-025' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-025' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Acompanhamento de processo executado por fornecedor','Demanda','', '', '', 'EM-PRC-026','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: acompanhamento de processo executado por fornecedor.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-026' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-026' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-026' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-026' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-026' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de gargalo e restrição produtiva','Demanda','', '', '', 'EM-PRC-027','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de gargalo e restrição produtiva.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-027' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-027' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-027' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-027' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-027' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Elaboração e acompanhamento de plano de recuperação','Demanda','', '', '', 'EM-PRC-028','PRC','Processo e Industrialização','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: elaboração e acompanhamento de plano de recuperação.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PRC-028' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-PRC-028' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-PRC-028' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PRC-028' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PRC-028' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Criação de rota de fabricação ou montagem','Demanda','', '', '', 'EM-SAP-001','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: criação de rota de fabricação ou montagem.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-001' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Revisão de rota','Demanda','', '', '', 'EM-SAP-002','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: revisão de rota.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-002' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Verificação de rota versus processo real','Demanda','', '', '', 'EM-SAP-003','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: verificação de rota versus processo real.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-003' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Criação de operação','Demanda','', '', '', 'EM-SAP-004','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: criação de operação.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-004' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Alteração ou correção de operação','Demanda','', '', '', 'EM-SAP-005','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: alteração ou correção de operação.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-005' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição da sequência de operações','Demanda','', '', '', 'EM-SAP-006','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição da sequência de operações.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-006' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Cadastro ou correção de centro de trabalho','Demanda','', '', '', 'EM-SAP-007','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: cadastro ou correção de centro de trabalho.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-007' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Cadastro de tempos de operação','Demanda','', '', '', 'EM-SAP-008','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: cadastro de tempos de operação.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-008' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Revisão e validação de tempos no SAP','Demanda','', '', '', 'EM-SAP-009','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: revisão e validação de tempos no sap.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-009' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Criação ou consulta de ordem de produção','Demanda','', '', '', 'EM-SAP-010','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: criação ou consulta de ordem de produção.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-010' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Verificação de ordem de produção','Demanda','', '', '', 'EM-SAP-011','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: verificação de ordem de produção.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-011' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Correção de ordem ou sequência de operações','Demanda','', '', '', 'EM-SAP-012','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: correção de ordem ou sequência de operações.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-012' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Verificação de apontamentos de produção','Demanda','', '', '', 'EM-SAP-013','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: verificação de apontamentos de produção.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-013' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Correção ou estorno de apontamentos','Demanda','', '', '', 'EM-SAP-014','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: correção ou estorno de apontamentos.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-014' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de divergência entre roteiro, OP e produção','Demanda','', '', '', 'EM-SAP-015','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de divergência entre roteiro, op e produção.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-015' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Cadastro, saneamento ou atualização em massa de dados mestres','Demanda','', '', '', 'EM-SAP-016','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: cadastro, saneamento ou atualização em massa de dados mestres.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-016' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Criação ou revisão de versão de produção','Demanda','', '', '', 'EM-SAP-017','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: criação ou revisão de versão de produção.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-017' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Liberação técnica de roteiro ou operação','Demanda','', '', '', 'EM-SAP-018','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: liberação técnica de roteiro ou operação.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-018' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Verificação de consumo e baixa de materiais','Demanda','', '', '', 'EM-SAP-019','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: verificação de consumo e baixa de materiais.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-019' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de estorno ou correção de componentes','Demanda','', '', '', 'EM-SAP-020','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de estorno ou correção de componentes.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-020' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Verificação do status e avanço da ordem de produção','Demanda','', '', '', 'EM-SAP-021','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: verificação do status e avanço da ordem de produção.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-021' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Fechamento técnico de ordem de produção','Demanda','', '', '', 'EM-SAP-022','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: fechamento técnico de ordem de produção.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-022' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Extração e análise de dados do SAP','Demanda','', '', '', 'EM-SAP-023','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: extração e análise de dados do sap.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-023' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Apoio ao usuário em transação SAP','Demanda','', '', '', 'EM-SAP-024','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: apoio ao usuário em transação sap.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-024' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Teste e validação de alteração realizada no SAP','Demanda','', '', '', 'EM-SAP-025','SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: teste e validação de alteração realizada no sap.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SAP-025' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Cadastro ou importação de geometrias no Lantek','Demanda','', '', '', 'EM-LTK-001','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: cadastro ou importação de geometrias no lantek.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-001' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Revisão do desenho para programação','Demanda','', '', '', 'EM-LTK-002','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: revisão do desenho para programação.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-002' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Preparação de peças para programação','Demanda','', '', '', 'EM-LTK-003','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: preparação de peças para programação.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-003' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Programação de corte a laser','Demanda','', '', '', 'EM-LTK-004','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: programação de corte a laser.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-004' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Criação de nesting manual','Demanda','', '', '', 'EM-LTK-005','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: criação de nesting manual.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-005' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Criação de nesting automático','Demanda','', '', '', 'EM-LTK-006','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: criação de nesting automático.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-006' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Revisão de nesting','Demanda','', '', '', 'EM-LTK-007','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: revisão de nesting.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-007' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Otimização de nesting e aproveitamento de chapa','Demanda','', '', '', 'EM-LTK-008','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: otimização de nesting e aproveitamento de chapa.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-008' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise e reaproveitamento de retalhos','Demanda','', '', '', 'EM-LTK-009','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise e reaproveitamento de retalhos.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-009' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição ou ajuste de parâmetros de corte','Demanda','', '', '', 'EM-LTK-010','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição ou ajuste de parâmetros de corte.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-010' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Geração de programa CNC','Demanda','', '', '', 'EM-LTK-011','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: geração de programa cnc.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-011' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Correção de programa de máquina','Demanda','', '', '', 'EM-LTK-012','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: correção de programa de máquina.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-012' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Simulação e validação do programa','Demanda','', '', '', 'EM-LTK-013','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: simulação e validação do programa.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-013' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Suporte técnico à máquina ou à produção','Demanda','', '', '', 'EM-LTK-014','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: suporte técnico à máquina ou à produção.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-014' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Conversão e limpeza de geometria CAD','Demanda','', '', '', 'EM-LTK-015','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: conversão e limpeza de geometria cad.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-015' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição de entradas, saídas e microjuntas','Demanda','', '', '', 'EM-LTK-016','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição de entradas, saídas e microjuntas.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-016' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Gestão de biblioteca de materiais e chapas','Demanda','', '', '', 'EM-LTK-017','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: gestão de biblioteca de materiais e chapas.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-017' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Ajuste de programa por espessura ou qualidade do material','Demanda','', '', '', 'EM-LTK-018','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: ajuste de programa por espessura ou qualidade do material.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-018' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de colisões, contornos e geometrias abertas','Demanda','', '', '', 'EM-LTK-019','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de colisões, contornos e geometrias abertas.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-019' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Liberação do programa para produção','Demanda','', '', '', 'EM-LTK-020','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: liberação do programa para produção.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-020' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Acompanhamento da primeira chapa cortada','Demanda','', '', '', 'EM-LTK-021','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: acompanhamento da primeira chapa cortada.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-021' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Reprogramação por alteração de desenho','Demanda','', '', '', 'EM-LTK-022','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: reprogramação por alteração de desenho.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-022' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Controle de retalhos e sobras','Demanda','', '', '', 'EM-LTK-023','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: controle de retalhos e sobras.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-023' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de tempo estimado de corte','Demanda','', '', '', 'EM-LTK-024','LTK','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de tempo estimado de corte.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-LTK-024' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise do processo de corte','Demanda','', '', '', 'EM-FAB-001','FAB','Fabricação Mecânica','Fabricação','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise do processo de corte.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-FAB-001' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise do processo de furação','Demanda','', '', '', 'EM-FAB-002','FAB','Fabricação Mecânica','Fabricação','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise do processo de furação.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-FAB-002' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise do processo de dobra','Demanda','', '', '', 'EM-FAB-003','FAB','Fabricação Mecânica','Fabricação','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise do processo de dobra.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-FAB-003' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise do processo de conformação','Demanda','', '', '', 'EM-FAB-004','FAB','Fabricação Mecânica','Fabricação','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise do processo de conformação.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-FAB-004' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise do processo de soldagem','Demanda','', '', '', 'EM-FAB-005','FAB','Fabricação Mecânica','Fabricação','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise do processo de soldagem.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-FAB-005' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de caldeiraria e montagem de subconjuntos','Demanda','', '', '', 'EM-FAB-006','FAB','Fabricação Mecânica','Fabricação','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de caldeiraria e montagem de subconjuntos.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-FAB-006' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de usinagem e acabamento mecânico','Demanda','', '', '', 'EM-FAB-007','FAB','Fabricação Mecânica','Fabricação','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de usinagem e acabamento mecânico.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-FAB-007' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição de gabaritos e meios de fixação','Demanda','', '', '', 'EM-FAB-008','FAB','Fabricação Mecânica','Fabricação','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição de gabaritos e meios de fixação.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-FAB-008' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição ou ajuste de parâmetros de máquina','Demanda','', '', '', 'EM-FAB-009','FAB','Fabricação Mecânica','Fabricação','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição ou ajuste de parâmetros de máquina.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-FAB-009' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Validação de primeira peça fabricada','Demanda','', '', '', 'EM-FAB-010','FAB','Fabricação Mecânica','Fabricação','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: validação de primeira peça fabricada.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-FAB-010' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Acompanhamento de fabricação crítica','Demanda','', '', '', 'EM-FAB-011','FAB','Fabricação Mecânica','Fabricação','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: acompanhamento de fabricação crítica.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-FAB-011' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Tratativa de desvio dimensional','Demanda','', '', '', 'EM-FAB-012','FAB','Fabricação Mecânica','Fabricação','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: tratativa de desvio dimensional.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-FAB-012' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Tratativa de falta ou incompatibilidade de material','Demanda','', '', '', 'EM-FAB-013','FAB','Fabricação Mecânica','Fabricação','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: tratativa de falta ou incompatibilidade de material.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-FAB-013' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição e acompanhamento de retrabalho ou refugo','Demanda','', '', '', 'EM-FAB-014','FAB','Fabricação Mecânica','Fabricação','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição e acompanhamento de retrabalho ou refugo.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-FAB-014' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Atendimento técnico à fabricação','Demanda','', '', '', 'EM-FAB-015','FAB','Fabricação Mecânica','Fabricação','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: atendimento técnico à fabricação.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-FAB-015' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise do processo de serramento','Demanda','', '', '', 'EM-FAB-016','FAB','Fabricação Mecânica','Fabricação','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise do processo de serramento.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-FAB-016' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de marcação e identificação de peças','Demanda','', '', '', 'EM-FAB-017','FAB','Fabricação Mecânica','Fabricação','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de marcação e identificação de peças.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-FAB-017' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição da sequência de fabricação de subconjuntos','Demanda','', '', '', 'EM-FAB-018','FAB','Fabricação Mecânica','Fabricação','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição da sequência de fabricação de subconjuntos.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-FAB-018' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de capacidade e disponibilidade de máquina','Demanda','', '', '', 'EM-FAB-019','FAB','Fabricação Mecânica','Fabricação','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de capacidade e disponibilidade de máquina.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-FAB-019' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição ou ajuste de ferramental de fabricação','Demanda','', '', '', 'EM-FAB-020','FAB','Fabricação Mecânica','Fabricação','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição ou ajuste de ferramental de fabricação.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-FAB-020' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de consumíveis e parâmetros de processo','Demanda','', '', '', 'EM-FAB-021','FAB','Fabricação Mecânica','Fabricação','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de consumíveis e parâmetros de processo.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-FAB-021' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Acompanhamento de protótipo ou lote piloto','Demanda','', '', '', 'EM-FAB-022','FAB','Fabricação Mecânica','Fabricação','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: acompanhamento de protótipo ou lote piloto.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-FAB-022' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Liberação técnica da fabricação','Demanda','', '', '', 'EM-FAB-023','FAB','Fabricação Mecânica','Fabricação','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: liberação técnica da fabricação.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-FAB-023' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de preparação de superfície','Demanda','', '', '', 'EM-PIN-001','PIN','Pintura, Corrosão e Vedação','Fabricação / Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de preparação de superfície.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PIN-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PIN-001' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise do processo de jateamento','Demanda','', '', '', 'EM-PIN-002','PIN','Pintura, Corrosão e Vedação','Fabricação / Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise do processo de jateamento.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PIN-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PIN-002' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de pintura líquida','Demanda','', '', '', 'EM-PIN-003','PIN','Pintura, Corrosão e Vedação','Fabricação / Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de pintura líquida.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PIN-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PIN-003' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de pintura eletrostática','Demanda','', '', '', 'EM-PIN-004','PIN','Pintura, Corrosão e Vedação','Fabricação / Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de pintura eletrostática.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PIN-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PIN-004' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de pintura intumescente','Demanda','', '', '', 'EM-PIN-005','PIN','Pintura, Corrosão e Vedação','Fabricação / Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de pintura intumescente.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PIN-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PIN-005' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de proteção anticorrosiva','Demanda','', '', '', 'EM-PIN-006','PIN','Pintura, Corrosão e Vedação','Fabricação / Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de proteção anticorrosiva.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PIN-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PIN-006' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição ou validação de primer e sistema de pintura','Demanda','', '', '', 'EM-PIN-007','PIN','Pintura, Corrosão e Vedação','Fabricação / Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição ou validação de primer e sistema de pintura.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PIN-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PIN-007' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Verificação de espessura, aderência e acabamento','Demanda','', '', '', 'EM-PIN-008','PIN','Pintura, Corrosão e Vedação','Fabricação / Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: verificação de espessura, aderência e acabamento.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PIN-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PIN-008' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Verificação de ponto de orvalho e condição ambiental','Demanda','', '', '', 'EM-PIN-009','PIN','Pintura, Corrosão e Vedação','Fabricação / Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: verificação de ponto de orvalho e condição ambiental.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PIN-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PIN-009' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição e acompanhamento de reparo de pintura','Demanda','', '', '', 'EM-PIN-010','PIN','Pintura, Corrosão e Vedação','Fabricação / Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição e acompanhamento de reparo de pintura.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PIN-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PIN-010' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de vedação e aplicação de selantes','Demanda','', '', '', 'EM-PIN-011','PIN','Pintura, Corrosão e Vedação','Fabricação / Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PIN-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PIN-011' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Acompanhamento de processo crítico de pintura','Demanda','', '', '', 'EM-PIN-012','PIN','Pintura, Corrosão e Vedação','Fabricação / Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PIN-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PIN-012' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Tratativa de falha, corrosão ou retrabalho superficial','Demanda','', '', '', 'EM-PIN-013','PIN','Pintura, Corrosão e Vedação','Fabricação / Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: t...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PIN-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PIN-013' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição de mascaramento e proteção de superfícies','Demanda','', '', '', 'EM-PIN-014','PIN','Pintura, Corrosão e Vedação','Fabricação / Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: d...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PIN-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PIN-014' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Cálculo ou estimativa de consumo de tinta e insumos','Demanda','', '', '', 'EM-PIN-015','PIN','Pintura, Corrosão e Vedação','Fabricação / Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: c...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PIN-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PIN-015' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de cura, secagem e intervalo entre demãos','Demanda','', '', '', 'EM-PIN-016','PIN','Pintura, Corrosão e Vedação','Fabricação / Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PIN-016' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PIN-016' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Avaliação de cabine, ventilação e condição de aplicação','Demanda','', '', '', 'EM-PIN-017','PIN','Pintura, Corrosão e Vedação','Fabricação / Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PIN-017' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PIN-017' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Avaliação de corrosão e causa provável','Demanda','', '', '', 'EM-PIN-018','PIN','Pintura, Corrosão e Vedação','Fabricação / Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PIN-018' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PIN-018' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição de tratamento ou recuperação de superfície','Demanda','', '', '', 'EM-PIN-019','PIN','Pintura, Corrosão e Vedação','Fabricação / Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: d...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PIN-019' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PIN-019' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Validação do reparo de pintura ou corrosão','Demanda','', '', '', 'EM-PIN-020','PIN','Pintura, Corrosão e Vedação','Fabricação / Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: v...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-PIN-020' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-PIN-020' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição da sequência de montagem estrutural','Demanda','', '', '', 'EM-MES-001','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: d...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-001' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de montagem da base','Demanda','', '', '', 'EM-MES-002','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-002' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de montagem de steel frame','Demanda','', '', '', 'EM-MES-003','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-003' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de vigas, travessas e reforços','Demanda','', '', '', 'EM-MES-004','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-004' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de pé-direito, teto e elementos superiores','Demanda','', '', '', 'EM-MES-005','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-005' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Verificação de alinhamento, nível e esquadro','Demanda','', '', '', 'EM-MES-006','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: v...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-006' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Verificação de cotas e tolerâncias estruturais','Demanda','', '', '', 'EM-MES-007','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: v...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-007' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de juntas, fixações e elementos de união','Demanda','', '', '', 'EM-MES-008','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-008' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição ou validação de torque estrutural','Demanda','', '', '', 'EM-MES-009','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: d...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-009' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de içamento e pontos de pega','Demanda','', '', '', 'EM-MES-010','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-010' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de movimentação e posicionamento de estruturas','Demanda','', '', '', 'EM-MES-011','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-011' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de acoplamento entre módulos','Demanda','', '', '', 'EM-MES-012','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-012' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de mantas, vedação e fechamentos estruturais','Demanda','', '', '', 'EM-MES-013','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-013' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de suportes e suportagem','Demanda','', '', '', 'EM-MES-014','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-014' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Acompanhamento de montagem estrutural crítica','Demanda','', '', '', 'EM-MES-015','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-015' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição de ajuste, retrabalho e liberação estrutural','Demanda','', '', '', 'EM-MES-016','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: d...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-016' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise e validação de gabarito estrutural','Demanda','', '', '', 'EM-MES-017','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-017' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Elaboração ou revisão do plano de montagem estrutural','Demanda','', '', '', 'EM-MES-018','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: e...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-018' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Elaboração ou revisão do plano de içamento','Demanda','', '', '', 'EM-MES-019','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: e...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-019' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Validação de olhais e pontos de pega','Demanda','', '', '', 'EM-MES-020','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: v...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-020' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de interface entre estrutura e arquitetura','Demanda','', '', '', 'EM-MES-021','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-021' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de interface entre estrutura e equipamentos','Demanda','', '', '', 'EM-MES-022','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-022' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de base, piso e pontos de apoio','Demanda','', '', '', 'EM-MES-023','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-023' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Acompanhamento de acoplamento e união de módulos','Demanda','', '', '', 'EM-MES-024','MES','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MES-024' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição da sequência de montagem final','Demanda','', '', '', 'EM-MFI-001','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: d...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-001' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de instalação de HVAC e climatização','Demanda','', '', '', 'EM-MFI-002','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-002' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de tubulação de água gelada','Demanda','', '', '', 'EM-MFI-003','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-003' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de ventilação e renovação de ar','Demanda','', '', '', 'EM-MFI-004','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-004' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de eletrocalhas e leitos','Demanda','', '', '', 'EM-MFI-005','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-005' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de eletrodutos e canaletas','Demanda','', '', '', 'EM-MFI-006','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-006' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de infraestrutura elétrica','Demanda','', '', '', 'EM-MFI-007','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de infraestrutura elétrica.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-007' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de BMS e automação','Demanda','', '', '', 'EM-MFI-008','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de bms e automação.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-008' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de CFTV e controle de acesso','Demanda','', '', '', 'EM-MFI-009','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de cftv e controle de acesso.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-009' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de detecção, alarme e combate a incêndio','Demanda','', '', '', 'EM-MFI-010','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de detecção, alarme e combate a incêndio.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-010' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de iluminação e aterramento','Demanda','', '', '', 'EM-MFI-011','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de iluminação e aterramento.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-011' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de pisos, forros e revestimentos','Demanda','', '', '', 'EM-MFI-012','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de pisos, forros e revestimentos.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-012' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de portas, janelas e fechamentos','Demanda','', '', '', 'EM-MFI-013','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de portas, janelas e fechamentos.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-013' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de vedação e selagem corta-fogo','Demanda','', '', '', 'EM-MFI-014','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de vedação e selagem corta-fogo.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-014' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de instalação e fixação de equipamentos','Demanda','', '', '', 'EM-MFI-015','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de instalação e fixação de equipamentos.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-015' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de interconexões entre módulos','Demanda','', '', '', 'EM-MFI-016','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de interconexões entre módulos.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-016' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Acompanhamento de montagem final crítica','Demanda','', '', '', 'EM-MFI-017','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: acompanhamento de montagem final crítica.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-017' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição de ajuste, retrabalho e liberação final','Demanda','', '', '', 'EM-MFI-018','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição de ajuste, retrabalho e liberação final.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-018' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de embalagem, amarração e transporte','Demanda','', '', '', 'EM-MFI-019','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de embalagem, amarração e transporte.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-019' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Atendimento técnico à montagem final','Demanda','', '', '', 'EM-MFI-020','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: atendimento técnico à montagem final.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-020' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de rota multidisciplinar','Demanda','', '', '', 'EM-MFI-021','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de rota multidisciplinar.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-021' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de suportação e pontos de fixação','Demanda','', '', '', 'EM-MFI-022','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de suportação e pontos de fixação.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-022' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Coordenação e tratativa de interferências em montagem','Demanda','', '', '', 'EM-MFI-023','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: coordenação e tratativa de interferências em montagem.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-023' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de acessibilidade e manutenção dos sistemas','Demanda','', '', '', 'EM-MFI-024','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de acessibilidade e manutenção dos sistemas.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-024' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de interfaces entre montagem final e painéis','Demanda','', '', '', 'EM-MFI-025','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de interfaces entre montagem final e painéis.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-025' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Acompanhamento de interligações mecânicas e elétricas','Demanda','', '', '', 'EM-MFI-026','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: acompanhamento de interligações mecânicas e elétricas.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-026' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Acompanhamento de preparação para transporte e entrega','Demanda','', '', '', 'EM-MFI-027','MFI','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: acompanhamento de preparação para transporte e entrega.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MFI-027' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição da sequência de montagem do painel','Demanda','', '', '', 'EM-MPA-001','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição da sequência de montagem do painel.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-001' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise do layout interno do painel','Demanda','', '', '', 'EM-MPA-002','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise do layout interno do painel.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-002' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise do posicionamento de componentes','Demanda','', '', '', 'EM-MPA-003','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise do posicionamento de componentes.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-003' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de fabricação de barramentos rígidos','Demanda','', '', '', 'EM-MPA-004','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de fabricação de barramentos rígidos.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-004' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de montagem e conexão de barramentos','Demanda','', '', '', 'EM-MPA-005','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de montagem e conexão de barramentos.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-005' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de barramentos flexíveis','Demanda','', '', '', 'EM-MPA-006','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de barramentos flexíveis.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-006' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de corte, dobra e furação de barramentos','Demanda','', '', '', 'EM-MPA-007','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de corte, dobra e furação de barramentos.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-007' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de tratamento superficial de barramentos','Demanda','', '', '', 'EM-MPA-008','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de tratamento superficial de barramentos.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-008' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de cabos, terminais e crimpagem','Demanda','', '', '', 'EM-MPA-009','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de cabos, terminais e crimpagem.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-009' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de identificação, anilhas e etiquetas','Demanda','', '', '', 'EM-MPA-010','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de identificação, anilhas e etiquetas.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-010' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição ou validação de torque elétrico','Demanda','', '', '', 'EM-MPA-011','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição ou validação de torque elétrico.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-011' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de furação, portas e adaptações mecânicas','Demanda','', '', '', 'EM-MPA-012','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de furação, portas e adaptações mecânicas.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-012' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de montagem de componentes elétricos','Demanda','', '', '', 'EM-MPA-013','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de montagem de componentes elétricos.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-013' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de transformadores, TCs e instrumentos','Demanda','', '', '', 'EM-MPA-014','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de transformadores, tcs e instrumentos.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-014' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Verificação de continuidade e isolação (MPA)','Demanda','', '', '', 'EM-MPA-015','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: verificação de continuidade e isolação.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-015' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Inspeção visual e dimensional do painel','Demanda','', '', '', 'EM-MPA-016','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: inspeção visual e dimensional do painel.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-016' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Acompanhamento de testes funcionais','Demanda','', '', '', 'EM-MPA-017','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: acompanhamento de testes funcionais.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-017' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Acompanhamento de energização ou painel energizado','Demanda','', '', '', 'EM-MPA-018','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: acompanhamento de energização ou painel energizado.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-018' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Apoio técnico ao FAT de painéis','Demanda','', '', '', 'EM-MPA-019','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: apoio técnico ao fat de painéis.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-019' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição de ajuste, retrabalho e liberação do painel','Demanda','', '', '', 'EM-MPA-020','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição de ajuste, retrabalho e liberação do painel.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-020' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise da lista de materiais do painel','Demanda','', '', '', 'EM-MPA-021','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise da lista de materiais do painel.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-021' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição de plano de montagem e kits do painel','Demanda','', '', '', 'EM-MPA-022','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição de plano de montagem e kits do painel.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-022' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição de ferramentas, bancadas e recursos','Demanda','', '', '', 'EM-MPA-023','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição de ferramentas, bancadas e recursos.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-023' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de dissipação térmica e ventilação do painel','Demanda','', '', '', 'EM-MPA-024','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de dissipação térmica e ventilação do painel.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-024' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de segregação, afastamentos e acessibilidade','Demanda','', '', '', 'EM-MPA-025','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de segregação, afastamentos e acessibilidade.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-025' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Verificação de diagrama e documentação para montagem','Demanda','', '', '', 'EM-MPA-026','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: verificação de diagrama e documentação para montagem.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-026' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Liberação do painel para testes','Demanda','', '', '', 'EM-MPA-027','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: liberação do painel para testes.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-027' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Correção de montagem após teste ou inspeção','Demanda','', '', '', 'EM-MPA-028','MPA','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Registrar o objeto analisado, a ação executada e o resultado relacionado a: correção de montagem após teste ou inspeção.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MPA-028' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Inspeção e validação dimensional','Demanda','', '', '', 'EM-QLD-001','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: inspeção e validação dimensional.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-001' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Validação de primeira peça','Demanda','', '', '', 'EM-QLD-002','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: validação de primeira peça.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-002' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Validação de processo de fabricação','Demanda','', '', '', 'EM-QLD-003','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: validação de processo de fabricação.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-003' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Validação de montagem estrutural','Demanda','', '', '', 'EM-QLD-004','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: validação de montagem estrutural.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-004' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Validação de montagem final','Demanda','', '', '', 'EM-QLD-005','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: validação de montagem final.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-005' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Validação de montagem de painéis','Demanda','', '', '', 'EM-QLD-006','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: validação de montagem de painéis.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-006' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Validação de soldagem','Demanda','', '', '', 'EM-QLD-007','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: validação de soldagem.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-007' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Validação de pintura e proteção anticorrosiva','Demanda','', '', '', 'EM-QLD-008','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: validação de pintura e proteção anticorrosiva.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-008' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Validação de vedação e acabamento','Demanda','', '', '', 'EM-QLD-009','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: validação de vedação e acabamento.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-009' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Validação de torque e fixações','Demanda','', '', '', 'EM-QLD-010','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: validação de torque e fixações.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-010' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Verificação ou relatório IQ','Demanda','', '', '', 'EM-QLD-011','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: verificação ou relatório iq.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-011' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Verificação ou relatório OQ','Demanda','', '', '', 'EM-QLD-012','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: verificação ou relatório oq.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-012' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Verificação ou relatório PQ','Demanda','', '', '', 'EM-QLD-013','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: verificação ou relatório pq.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-013' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Auditoria de processo','Demanda','', '', '', 'EM-QLD-014','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: auditoria de processo.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-014' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de RNC / não conformidade','Demanda','', '', '', 'EM-QLD-015','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de rnc / não conformidade.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-015' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Investigação de causa raiz','Demanda','', '', '', 'EM-QLD-016','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: investigação de causa raiz.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-016' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-016' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-016' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-016' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-016' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição de contenção, retrabalho e verificação de eficácia','Demanda','', '', '', 'EM-QLD-017','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: definição de contenção, retrabalho e verificação de eficácia.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-017' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-017' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-017' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-017' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-017' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Registro e aplicação de lição aprendida','Demanda','', '', '', 'EM-QLD-018','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: registro e aplicação de lição aprendida.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-018' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-018' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-018' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-018' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-018' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Elaboração ou revisão de PFMEA','Demanda','', '', '', 'EM-QLD-019','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: elaboração ou revisão de pfmea.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-019' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-019' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-019' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-019' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-019' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Elaboração ou revisão de Plano de Controle','Demanda','', '', '', 'EM-QLD-020','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: elaboração ou revisão de plano de controle.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-020' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-020' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-020' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-020' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-020' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Elaboração ou revisão de plano de inspeção','Demanda','', '', '', 'EM-QLD-021','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: elaboração ou revisão de plano de inspeção.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-021' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-021' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-021' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-021' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-021' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Aplicação de 5 Porquês ou Diagrama de Ishikawa','Demanda','', '', '', 'EM-QLD-022','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: aplicação de 5 porquês ou diagrama de ishikawa.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-022' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-022' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-022' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-022' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-022' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Elaboração de A3 ou 8D','Demanda','', '', '', 'EM-QLD-023','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: elaboração de a3 ou 8d.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-023' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-023' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-023' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-023' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-023' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de capacidade e estabilidade do processo','Demanda','', '', '', 'EM-QLD-024','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de capacidade e estabilidade do processo.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-024' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-024' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-024' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-024' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-024' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Acompanhamento de auditoria de cliente ou terceira parte','Demanda','', '', '', 'EM-QLD-025','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: acompanhamento de auditoria de cliente ou terceira parte.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-025' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-025' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-025' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-025' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-025' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de reincidência de não conformidade','Demanda','', '', '', 'EM-QLD-026','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de reincidência de não conformidade.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-026' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-026' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-026' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-026' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-026' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Fechamento de punch list de fabricação ou montagem','Demanda','', '', '', 'EM-QLD-027','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: fechamento de punch list de fabricação ou montagem.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-027' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-027' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-027' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-027' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-027' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Organização e validação de evidências da qualidade','Demanda','', '', '', 'EM-QLD-028','QLD','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Registrar o objeto analisado, a ação executada e o resultado relacionado a: organização e validação de evidências da qualidade.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-QLD-028' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-QLD-028' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-QLD-028' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-QLD-028' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-QLD-028' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Reunião com Segurança do Trabalho','Demanda','', '', '', 'EM-SST-001','SST','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: reunião com segurança do trabalho.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-SST-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-SST-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-SST-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-SST-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SST-001' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('DDS ou alinhamento de segurança','Demanda','', '', '', 'EM-SST-002','SST','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: dds ou alinhamento de segurança.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-SST-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-SST-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-SST-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-SST-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SST-002' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de risco do processo','Demanda','', '', '', 'EM-SST-003','SST','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de risco do processo.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-SST-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-SST-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-SST-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-SST-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SST-003' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Avaliação ergonômica do posto de trabalho','Demanda','', '', '', 'EM-SST-004','SST','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-SST-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-SST-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-SST-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-SST-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SST-004' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de movimentação manual de carga','Demanda','', '', '', 'EM-SST-005','SST','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-SST-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-SST-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-SST-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-SST-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SST-005' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de içamento e movimentação mecanizada','Demanda','', '', '', 'EM-SST-006','SST','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-SST-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-SST-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-SST-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-SST-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SST-006' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Avaliação de segurança de máquina','Demanda','', '', '', 'EM-SST-007','SST','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-SST-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-SST-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-SST-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-SST-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SST-007' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Avaliação de segurança de ferramenta ou dispositivo','Demanda','', '', '', 'EM-SST-008','SST','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-SST-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-SST-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-SST-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-SST-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SST-008' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de bloqueio, etiquetagem e energias perigosas','Demanda','', '', '', 'EM-SST-009','SST','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-SST-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-SST-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-SST-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-SST-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SST-009' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de trabalho em altura e acesso','Demanda','', '', '', 'EM-SST-010','SST','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-SST-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-SST-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-SST-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-SST-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SST-010' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de produtos químicos, pintura e ventilação','Demanda','', '', '', 'EM-SST-011','SST','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-SST-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-SST-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-SST-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-SST-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SST-011' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise ambiental, resíduos e impacto do processo','Demanda','', '', '', 'EM-SST-012','SST','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-SST-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-SST-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-SST-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-SST-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SST-012' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição e acompanhamento de melhoria de segurança ou ergonomia','Demanda','', '', '', 'EM-SST-013','SST','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: d...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-SST-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-SST-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-SST-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-SST-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SST-013' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Elaboração ou revisão de APR','Demanda','', '', '', 'EM-SST-014','SST','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: e...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-SST-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-SST-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-SST-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-SST-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SST-014' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição de EPI e EPC do processo','Demanda','', '', '', 'EM-SST-015','SST','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: d...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-SST-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-SST-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-SST-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-SST-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SST-015' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Validação de proteção e adequação de máquina','Demanda','', '', '', 'EM-SST-016','SST','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: v...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-SST-016' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-SST-016' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-SST-016' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-SST-016' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SST-016' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de acesso e manutenção segura','Demanda','', '', '', 'EM-SST-017','SST','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-SST-017' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-SST-017' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-SST-017' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-SST-017' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SST-017' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Reunião específica de ergonomia','Demanda','', '', '', 'EM-SST-018','SST','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: r...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-SST-018' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-SST-018' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-SST-018' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-SST-018' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SST-018' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de altura, alcance, postura e esforço no posto','Demanda','', '', '', 'EM-SST-019','SST','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-SST-019' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-SST-019' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-SST-019' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-SST-019' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SST-019' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Acompanhamento da adequação de segurança ou ergonomia','Demanda','', '', '', 'EM-SST-020','SST','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-SST-020' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-SST-020' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-SST-020' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-SST-020' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SST-020' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Validação da condição após implantação da melhoria','Demanda','', '', '', 'EM-SST-021','SST','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: v...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-SST-021' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-SST-021' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-SST-021' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-SST-021' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-SST-021' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Evento Kaizen ou melhoria contínua','Demanda','', '', '', 'EM-MEL-001','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: e...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-001' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Melhoria de produtividade','Demanda','', '', '', 'EM-MEL-002','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: m...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-002' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Redução de custos','Demanda','', '', '', 'EM-MEL-003','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: r...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-003' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Redução de desperdício, refugo ou retrabalho','Demanda','', '', '', 'EM-MEL-004','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: r...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-004' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Melhoria de fluxo de materiais e informação','Demanda','', '', '', 'EM-MEL-005','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: m...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-005' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Melhoria de layout ou posto de trabalho','Demanda','', '', '', 'EM-MEL-006','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: m...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-006' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Padronização entre projetos','Demanda','', '', '', 'EM-MEL-007','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: p...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-007' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Desenvolvimento de dispositivo','Demanda','', '', '', 'EM-MEL-008','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: d...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-008' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Desenvolvimento de gabarito','Demanda','', '', '', 'EM-MEL-009','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: d...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-009' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Projeto ou detalhamento de ferramental','Demanda','', '', '', 'EM-MEL-010','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: p...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-010' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Acompanhamento da fabricação de dispositivo','Demanda','', '', '', 'EM-MEL-011','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-011' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Try-out e ajuste de dispositivo','Demanda','', '', '', 'EM-MEL-012','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: t...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-012' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Validação e liberação de dispositivo','Demanda','', '', '', 'EM-MEL-013','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: v...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-013' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Automação ou digitalização de processo','Demanda','', '', '', 'EM-MEL-014','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-014' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Desenvolvimento de Power BI, Power Apps, SharePoint ou Aponta P3','Demanda','', '', '', 'EM-MEL-015','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: d...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-015' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Avaliação de benefício e resultado da melhoria','Demanda','', '', '', 'EM-MEL-016','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-016' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-016' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-016' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-016' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-016' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Levantamento de oportunidade de melhoria','Demanda','', '', '', 'EM-MEL-017','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: l...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-017' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-017' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-017' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-017' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-017' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Estudo de viabilidade técnica e econômica','Demanda','', '', '', 'EM-MEL-018','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: e...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-018' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-018' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-018' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-018' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-018' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Elaboração de business case ou cálculo de retorno','Demanda','', '', '', 'EM-MEL-019','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: e...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-019' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-019' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-019' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-019' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-019' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Mapeamento de fluxo de valor','Demanda','', '', '', 'EM-MEL-020','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: m...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-020' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-020' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-020' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-020' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-020' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Implantação ou auditoria de 5S','Demanda','', '', '', 'EM-MEL-021','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: i...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-021' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-021' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-021' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-021' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-021' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Desenvolvimento de trabalho padronizado','Demanda','', '', '', 'EM-MEL-022','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: d...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-022' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-022' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-022' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-022' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-022' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Desenvolvimento de poka-yoke','Demanda','', '', '', 'EM-MEL-023','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: d...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-023' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-023' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-023' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-023' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-023' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise e redução de tempo de setup','Demanda','', '', '', 'EM-MEL-024','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-024' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-024' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-024' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-024' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-024' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Implantação de Kanban ou gestão visual de fluxo','Demanda','', '', '', 'EM-MEL-025','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: i...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-025' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-025' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-025' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-025' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-025' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Elaboração de plano de ação de melhoria','Demanda','', '', '', 'EM-MEL-026','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: e...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-026' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-026' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-026' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-026' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-026' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Implantação piloto da melhoria','Demanda','', '', '', 'EM-MEL-027','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: i...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-027' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-027' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-027' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-027' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-027' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Auditoria de sustentação e padronização','Demanda','', '', '', 'EM-MEL-028','MEL','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MEL-028' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MEL-028' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MEL-028' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MEL-028' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MEL-028' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Planejamento da demanda de fabricação e montagem','Demanda','', '', '', 'EM-PCP-001','PCP','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Registrar o objeto analisado, a ação executada e o resultado relacionado a: p...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PCP-001' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Revisão do sequenciamento de produção','Demanda','', '', '', 'EM-PCP-002','PCP','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Registrar o objeto analisado, a ação executada e o resultado relacionado a: r...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PCP-002' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de carga e capacidade por recurso','Demanda','', '', '', 'EM-PCP-003','PCP','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PCP-003' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Acompanhamento da programação diária ou semanal','Demanda','', '', '', 'EM-PCP-004','PCP','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PCP-004' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Verificação de disponibilidade de máquina, mão de obra e recurso','Demanda','', '', '', 'EM-PCP-005','PCP','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Registrar o objeto analisado, a ação executada e o resultado relacionado a: v...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PCP-005' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Follow-up de peças e conjuntos pendentes','Demanda','', '', '', 'EM-PCP-006','PCP','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Registrar o objeto analisado, a ação executada e o resultado relacionado a: f...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PCP-006' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Atualização do cronograma de manufatura','Demanda','', '', '', 'EM-PCP-007','PCP','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PCP-007' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Replanejamento por restrição ou atraso','Demanda','', '', '', 'EM-PCP-008','PCP','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Registrar o objeto analisado, a ação executada e o resultado relacionado a: r...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PCP-008' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Reunião e alinhamento com PCP','Demanda','', '', '', 'EM-PCP-009','PCP','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Registrar o objeto analisado, a ação executada e o resultado relacionado a: r...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PCP-009' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Acompanhamento de backlog e trabalho em processo','Demanda','', '', '', 'EM-PCP-010','PCP','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PCP-010' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição de prioridade de ordens de produção','Demanda','', '', '', 'EM-PCP-011','PCP','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Registrar o objeto analisado, a ação executada e o resultado relacionado a: d...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PCP-011' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de atraso e plano de recuperação','Demanda','', '', '', 'EM-PCP-012','PCP','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PCP-012' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Controle de avanço físico por módulo ou sala','Demanda','', '', '', 'EM-PCP-013','PCP','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Registrar o objeto analisado, a ação executada e o resultado relacionado a: c...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PCP-013' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Fechamento de etapa de fabricação ou montagem','Demanda','', '', '', 'EM-PCP-014','PCP','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Registrar o objeto analisado, a ação executada e o resultado relacionado a: f...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-PCP-014' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de necessidade de material','Demanda','', '', '', 'EM-MAT-001','MAT','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MAT-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MAT-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MAT-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MAT-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MAT-001' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Verificação de disponibilidade em estoque','Demanda','', '', '', 'EM-MAT-002','MAT','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: v...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MAT-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MAT-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MAT-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MAT-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MAT-002' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise e aprovação de material alternativo','Demanda','', '', '', 'EM-MAT-003','MAT','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MAT-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MAT-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MAT-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MAT-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MAT-003' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Elaboração de especificação técnica para compra','Demanda','', '', '', 'EM-MAT-004','MAT','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: e...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MAT-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MAT-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MAT-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MAT-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MAT-004' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Solicitação ou requisição de compra técnica','Demanda','', '', '', 'EM-MAT-005','MAT','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: s...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MAT-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MAT-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MAT-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MAT-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MAT-005' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Equalização técnica de propostas','Demanda','', '', '', 'EM-MAT-006','MAT','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: e...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MAT-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MAT-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MAT-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MAT-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MAT-006' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Reunião técnica com fornecedor','Demanda','', '', '', 'EM-MAT-007','MAT','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: r...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MAT-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MAT-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MAT-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MAT-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MAT-007' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Follow-up de fabricação ou entrega de fornecedor','Demanda','', '', '', 'EM-MAT-008','MAT','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: f...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MAT-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MAT-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MAT-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MAT-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MAT-008' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Acompanhamento de desenvolvimento de fornecedor','Demanda','', '', '', 'EM-MAT-009','MAT','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MAT-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MAT-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MAT-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MAT-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MAT-009' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Inspeção ou recebimento técnico de material','Demanda','', '', '', 'EM-MAT-010','MAT','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: i...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MAT-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MAT-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MAT-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MAT-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MAT-010' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Tratativa de material não conforme','Demanda','', '', '', 'EM-MAT-011','MAT','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: t...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MAT-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MAT-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MAT-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MAT-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MAT-011' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Aprovação de amostra ou protótipo de fornecedor','Demanda','', '', '', 'EM-MAT-012','MAT','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MAT-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MAT-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MAT-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MAT-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MAT-012' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Controle de pendências de material','Demanda','', '', '', 'EM-MAT-013','MAT','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: c...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MAT-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MAT-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MAT-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MAT-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MAT-013' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Definição e validação de kit de montagem','Demanda','', '', '', 'EM-MAT-014','MAT','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: d...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MAT-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MAT-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MAT-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MAT-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MAT-014' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de nacionalização de componente ou fornecedor','Demanda','', '', '', 'EM-MAT-015','MAT','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-MAT-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-MAT-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-MAT-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-MAT-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-MAT-015' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Criação de documentação técnica','Demanda','', '', '', 'EM-DOC-001','DOC','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: c...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DOC-001' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Revisão de documentação técnica','Demanda','', '', '', 'EM-DOC-002','DOC','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: r...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DOC-002' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Controle de revisão e validade de documentos','Demanda','', '', '', 'EM-DOC-003','DOC','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: c...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DOC-003' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Cadastro, publicação ou atualização de documento no sistema','Demanda','', '', '', 'EM-DOC-004','DOC','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: c...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DOC-004' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de documento recebido de outra área ou fornecedor','Demanda','', '', '', 'EM-DOC-005','DOC','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: a...','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DOC-005' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Revisão e atualização de desenho as-built','Demanda','', '', '', 'EM-DOC-006','DOC','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: revisão e atualização de desenho as-built.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DOC-006' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Controle e consolidação de Red Pen','Demanda','', '', '', 'EM-DOC-007','DOC','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: controle e consolidação de red pen.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DOC-007' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Registro e acompanhamento de DANE ou mudança','Demanda','', '', '', 'EM-DOC-008','DOC','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: registro e acompanhamento de dane ou mudança.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DOC-008' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Atualização de BOM ou lista de materiais','Demanda','', '', '', 'EM-DOC-009','DOC','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: atualização de bom ou lista de materiais.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DOC-009' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Elaboração e atualização de lista de pendências','Demanda','', '', '', 'EM-DOC-010','DOC','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: elaboração e atualização de lista de pendências.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DOC-010' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Preparação de pacote para liberação de produção','Demanda','', '', '', 'EM-DOC-011','DOC','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: preparação de pacote para liberação de produção.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DOC-011' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Organização de registros e evidências técnicas','Demanda','', '', '', 'EM-DOC-012','DOC','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: organização de registros e evidências técnicas.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DOC-012' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Emissão de relatório técnico','Demanda','', '', '', 'EM-DOC-013','DOC','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: emissão de relatório técnico.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DOC-013' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Atualização de matriz ou índice de documentos','Demanda','', '', '', 'EM-DOC-014','DOC','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: atualização de matriz ou índice de documentos.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DOC-014' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Registro e publicação de lição aprendida','Demanda','', '', '', 'EM-DOC-015','DOC','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: registro e publicação de lição aprendida.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-DOC-015' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Planejamento de teste ou FAT','Demanda','', '', '', 'EM-TST-001','TST','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: planejamento de teste ou fat.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-TST-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-TST-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-TST-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-TST-001' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-TST-001' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Preparação de checklist, procedimento ou protocolo de teste','Demanda','', '', '', 'EM-TST-002','TST','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: preparação de checklist, procedimento ou protocolo de teste.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-TST-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-TST-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-TST-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-TST-002' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-TST-002' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Verificação de pré-requisitos para teste','Demanda','', '', '', 'EM-TST-003','TST','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: verificação de pré-requisitos para teste.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-TST-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-TST-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-TST-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-TST-003' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-TST-003' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Acompanhamento de FAT / L1','Demanda','', '', '', 'EM-TST-004','TST','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: acompanhamento de fat / l1.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-TST-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-TST-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-TST-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-TST-004' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-TST-004' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Acompanhamento de SAT / L2 de fábrica ou pré-site','Demanda','', '', '', 'EM-TST-005','TST','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: acompanhamento de sat / l2 de fábrica ou pré-site.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-TST-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-TST-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-TST-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-TST-005' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-TST-005' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Apoio a startup e energização controlada','Demanda','', '', '', 'EM-TST-006','TST','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: apoio a startup e energização controlada.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-TST-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-TST-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-TST-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-TST-006' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-TST-006' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Acompanhamento de teste funcional','Demanda','', '', '', 'EM-TST-007','TST','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: acompanhamento de teste funcional.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-TST-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-TST-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-TST-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-TST-007' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-TST-007' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Verificação de continuidade e isolação (TST)','Demanda','', '', '', 'EM-TST-008','TST','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: verificação de continuidade e isolação.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-TST-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-TST-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-TST-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-TST-008' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-TST-008' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Verificação de torque e conexões','Demanda','', '', '', 'EM-TST-009','TST','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: verificação de torque e conexões.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-TST-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-TST-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-TST-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-TST-009' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-TST-009' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Teste de vedação, estanqueidade ou acabamento','Demanda','', '', '', 'EM-TST-010','TST','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: teste de vedação, estanqueidade ou acabamento.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-TST-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-TST-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-TST-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-TST-010' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-TST-010' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Teste de pintura, espessura ou aderência','Demanda','', '', '', 'EM-TST-011','TST','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: teste de pintura, espessura ou aderência.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-TST-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-TST-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-TST-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-TST-011' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-TST-011' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Tratativa e acompanhamento de punch list','Demanda','', '', '', 'EM-TST-012','TST','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: tratativa e acompanhamento de punch list.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-TST-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-TST-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-TST-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-TST-012' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-TST-012' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Registro e organização de evidências de teste','Demanda','', '', '', 'EM-TST-013','TST','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: registro e organização de evidências de teste.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-TST-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-TST-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-TST-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-TST-013' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-TST-013' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Análise de falha identificada em teste','Demanda','', '', '', 'EM-TST-014','TST','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: análise de falha identificada em teste.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-TST-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-TST-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-TST-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-TST-014' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-TST-014' on conflict do nothing;
insert into public.activities(name,activity_type,frequency,responsible_name,backup_name,code,discipline_code,discipline_name,sector_principal,nature,usage_description,observation_requirement,active) values ('Liberação técnica após teste','Demanda','', '', '', 'EM-TST-015','TST','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Registrar o objeto analisado, a ação executada e o resultado relacionado a: liberação técnica após teste.','Sim',true) on conflict(name) do update set code=excluded.code,discipline_code=excluded.discipline_code,discipline_name=excluded.discipline_name,sector_principal=excluded.sector_principal,nature=excluded.nature,usage_description=excluded.usage_description,observation_requirement=excluded.observation_requirement,active=excluded.active;
insert into public.activity_area_links(activity_id,area_code) select id,'FAB' from public.activities where code='EM-TST-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MES' from public.activities where code='EM-TST-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MPA' from public.activities where code='EM-TST-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'MFI' from public.activities where code='EM-TST-015' on conflict do nothing;
insert into public.activity_area_links(activity_id,area_code) select id,'ADM' from public.activities where code='EM-TST-015' on conflict do nothing;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Geral do projeto',0,true from public.projects p join public.modules m on m.code='MOD-GERAL' where p.code='INTERNO-EM' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 01',1,true from public.projects p join public.modules m on m.code='M01' where p.code='INTERNO-EM' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 02',2,true from public.projects p join public.modules m on m.code='M02' where p.code='INTERNO-EM' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 03',3,true from public.projects p join public.modules m on m.code='M03' where p.code='INTERNO-EM' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 04',4,true from public.projects p join public.modules m on m.code='M04' where p.code='INTERNO-EM' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 05',5,true from public.projects p join public.modules m on m.code='M05' where p.code='INTERNO-EM' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 06',6,true from public.projects p join public.modules m on m.code='M06' where p.code='INTERNO-EM' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 07',7,true from public.projects p join public.modules m on m.code='M07' where p.code='INTERNO-EM' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 08',8,true from public.projects p join public.modules m on m.code='M08' where p.code='INTERNO-EM' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 09',9,true from public.projects p join public.modules m on m.code='M09' where p.code='INTERNO-EM' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 10',10,true from public.projects p join public.modules m on m.code='M10' where p.code='INTERNO-EM' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 11',11,true from public.projects p join public.modules m on m.code='M11' where p.code='INTERNO-EM' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 12',12,true from public.projects p join public.modules m on m.code='M12' where p.code='INTERNO-EM' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 13',13,true from public.projects p join public.modules m on m.code='M13' where p.code='INTERNO-EM' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 14',14,true from public.projects p join public.modules m on m.code='M14' where p.code='INTERNO-EM' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 15',15,true from public.projects p join public.modules m on m.code='M15' where p.code='INTERNO-EM' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 16',16,true from public.projects p join public.modules m on m.code='M16' where p.code='INTERNO-EM' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Geral do projeto',0,true from public.projects p join public.modules m on m.code='MOD-GERAL' where p.code='AWS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 01',1,true from public.projects p join public.modules m on m.code='M01' where p.code='AWS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 02',2,true from public.projects p join public.modules m on m.code='M02' where p.code='AWS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 03',3,true from public.projects p join public.modules m on m.code='M03' where p.code='AWS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 04',4,true from public.projects p join public.modules m on m.code='M04' where p.code='AWS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 05',5,true from public.projects p join public.modules m on m.code='M05' where p.code='AWS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 06',6,true from public.projects p join public.modules m on m.code='M06' where p.code='AWS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 07',7,true from public.projects p join public.modules m on m.code='M07' where p.code='AWS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 08',8,true from public.projects p join public.modules m on m.code='M08' where p.code='AWS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 09',9,true from public.projects p join public.modules m on m.code='M09' where p.code='AWS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 10',10,true from public.projects p join public.modules m on m.code='M10' where p.code='AWS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 11',11,true from public.projects p join public.modules m on m.code='M11' where p.code='AWS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 12',12,true from public.projects p join public.modules m on m.code='M12' where p.code='AWS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 13',13,true from public.projects p join public.modules m on m.code='M13' where p.code='AWS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 14',14,true from public.projects p join public.modules m on m.code='M14' where p.code='AWS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 15',15,true from public.projects p join public.modules m on m.code='M15' where p.code='AWS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 16',16,true from public.projects p join public.modules m on m.code='M16' where p.code='AWS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Geral do projeto',0,true from public.projects p join public.modules m on m.code='MOD-GERAL' where p.code='TB11' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 01',1,true from public.projects p join public.modules m on m.code='M01' where p.code='TB11' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 02',2,true from public.projects p join public.modules m on m.code='M02' where p.code='TB11' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 03',3,true from public.projects p join public.modules m on m.code='M03' where p.code='TB11' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 04',4,true from public.projects p join public.modules m on m.code='M04' where p.code='TB11' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 05',5,true from public.projects p join public.modules m on m.code='M05' where p.code='TB11' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 06',6,true from public.projects p join public.modules m on m.code='M06' where p.code='TB11' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 07',7,true from public.projects p join public.modules m on m.code='M07' where p.code='TB11' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 08',8,true from public.projects p join public.modules m on m.code='M08' where p.code='TB11' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 09',9,true from public.projects p join public.modules m on m.code='M09' where p.code='TB11' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 10',10,true from public.projects p join public.modules m on m.code='M10' where p.code='TB11' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 11',11,true from public.projects p join public.modules m on m.code='M11' where p.code='TB11' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 12',12,true from public.projects p join public.modules m on m.code='M12' where p.code='TB11' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 13',13,true from public.projects p join public.modules m on m.code='M13' where p.code='TB11' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 14',14,true from public.projects p join public.modules m on m.code='M14' where p.code='TB11' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 15',15,true from public.projects p join public.modules m on m.code='M15' where p.code='TB11' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 16',16,true from public.projects p join public.modules m on m.code='M16' where p.code='TB11' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Geral do projeto',0,true from public.projects p join public.modules m on m.code='MOD-GERAL' where p.code='UFG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 01',1,true from public.projects p join public.modules m on m.code='M01' where p.code='UFG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 02',2,true from public.projects p join public.modules m on m.code='M02' where p.code='UFG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 03',3,true from public.projects p join public.modules m on m.code='M03' where p.code='UFG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 04',4,true from public.projects p join public.modules m on m.code='M04' where p.code='UFG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 05',5,true from public.projects p join public.modules m on m.code='M05' where p.code='UFG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 06',6,true from public.projects p join public.modules m on m.code='M06' where p.code='UFG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 07',7,true from public.projects p join public.modules m on m.code='M07' where p.code='UFG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 08',8,true from public.projects p join public.modules m on m.code='M08' where p.code='UFG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 09',9,true from public.projects p join public.modules m on m.code='M09' where p.code='UFG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 10',10,true from public.projects p join public.modules m on m.code='M10' where p.code='UFG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 11',11,true from public.projects p join public.modules m on m.code='M11' where p.code='UFG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 12',12,true from public.projects p join public.modules m on m.code='M12' where p.code='UFG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 13',13,true from public.projects p join public.modules m on m.code='M13' where p.code='UFG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 14',14,true from public.projects p join public.modules m on m.code='M14' where p.code='UFG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 15',15,true from public.projects p join public.modules m on m.code='M15' where p.code='UFG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 16',16,true from public.projects p join public.modules m on m.code='M16' where p.code='UFG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Geral do projeto',0,true from public.projects p join public.modules m on m.code='MOD-GERAL' where p.code='PRODEB' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 01',1,true from public.projects p join public.modules m on m.code='M01' where p.code='PRODEB' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 02',2,true from public.projects p join public.modules m on m.code='M02' where p.code='PRODEB' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 03',3,true from public.projects p join public.modules m on m.code='M03' where p.code='PRODEB' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 04',4,true from public.projects p join public.modules m on m.code='M04' where p.code='PRODEB' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 05',5,true from public.projects p join public.modules m on m.code='M05' where p.code='PRODEB' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 06',6,true from public.projects p join public.modules m on m.code='M06' where p.code='PRODEB' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 07',7,true from public.projects p join public.modules m on m.code='M07' where p.code='PRODEB' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 08',8,true from public.projects p join public.modules m on m.code='M08' where p.code='PRODEB' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 09',9,true from public.projects p join public.modules m on m.code='M09' where p.code='PRODEB' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 10',10,true from public.projects p join public.modules m on m.code='M10' where p.code='PRODEB' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 11',11,true from public.projects p join public.modules m on m.code='M11' where p.code='PRODEB' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 12',12,true from public.projects p join public.modules m on m.code='M12' where p.code='PRODEB' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 13',13,true from public.projects p join public.modules m on m.code='M13' where p.code='PRODEB' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 14',14,true from public.projects p join public.modules m on m.code='M14' where p.code='PRODEB' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 15',15,true from public.projects p join public.modules m on m.code='M15' where p.code='PRODEB' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 16',16,true from public.projects p join public.modules m on m.code='M16' where p.code='PRODEB' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Geral do projeto',0,true from public.projects p join public.modules m on m.code='MOD-GERAL' where p.code='BARBADOS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 01',1,true from public.projects p join public.modules m on m.code='M01' where p.code='BARBADOS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 02',2,true from public.projects p join public.modules m on m.code='M02' where p.code='BARBADOS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 03',3,true from public.projects p join public.modules m on m.code='M03' where p.code='BARBADOS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 04',4,true from public.projects p join public.modules m on m.code='M04' where p.code='BARBADOS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 05',5,true from public.projects p join public.modules m on m.code='M05' where p.code='BARBADOS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 06',6,true from public.projects p join public.modules m on m.code='M06' where p.code='BARBADOS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 07',7,true from public.projects p join public.modules m on m.code='M07' where p.code='BARBADOS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 08',8,true from public.projects p join public.modules m on m.code='M08' where p.code='BARBADOS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 09',9,true from public.projects p join public.modules m on m.code='M09' where p.code='BARBADOS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 10',10,true from public.projects p join public.modules m on m.code='M10' where p.code='BARBADOS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 11',11,true from public.projects p join public.modules m on m.code='M11' where p.code='BARBADOS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 12',12,true from public.projects p join public.modules m on m.code='M12' where p.code='BARBADOS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 13',13,true from public.projects p join public.modules m on m.code='M13' where p.code='BARBADOS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 14',14,true from public.projects p join public.modules m on m.code='M14' where p.code='BARBADOS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 15',15,true from public.projects p join public.modules m on m.code='M15' where p.code='BARBADOS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 16',16,true from public.projects p join public.modules m on m.code='M16' where p.code='BARBADOS' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Geral do projeto',0,true from public.projects p join public.modules m on m.code='MOD-GERAL' where p.code='FOR' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 01',1,true from public.projects p join public.modules m on m.code='M01' where p.code='FOR' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 02',2,true from public.projects p join public.modules m on m.code='M02' where p.code='FOR' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 03',3,true from public.projects p join public.modules m on m.code='M03' where p.code='FOR' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 04',4,true from public.projects p join public.modules m on m.code='M04' where p.code='FOR' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 05',5,true from public.projects p join public.modules m on m.code='M05' where p.code='FOR' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 06',6,true from public.projects p join public.modules m on m.code='M06' where p.code='FOR' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 07',7,true from public.projects p join public.modules m on m.code='M07' where p.code='FOR' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 08',8,true from public.projects p join public.modules m on m.code='M08' where p.code='FOR' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 09',9,true from public.projects p join public.modules m on m.code='M09' where p.code='FOR' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 10',10,true from public.projects p join public.modules m on m.code='M10' where p.code='FOR' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 11',11,true from public.projects p join public.modules m on m.code='M11' where p.code='FOR' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 12',12,true from public.projects p join public.modules m on m.code='M12' where p.code='FOR' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 13',13,true from public.projects p join public.modules m on m.code='M13' where p.code='FOR' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 14',14,true from public.projects p join public.modules m on m.code='M14' where p.code='FOR' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 15',15,true from public.projects p join public.modules m on m.code='M15' where p.code='FOR' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 16',16,true from public.projects p join public.modules m on m.code='M16' where p.code='FOR' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Geral do projeto',0,true from public.projects p join public.modules m on m.code='MOD-GERAL' where p.code='BOG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 01',1,true from public.projects p join public.modules m on m.code='M01' where p.code='BOG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 02',2,true from public.projects p join public.modules m on m.code='M02' where p.code='BOG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 03',3,true from public.projects p join public.modules m on m.code='M03' where p.code='BOG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 04',4,true from public.projects p join public.modules m on m.code='M04' where p.code='BOG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 05',5,true from public.projects p join public.modules m on m.code='M05' where p.code='BOG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 06',6,true from public.projects p join public.modules m on m.code='M06' where p.code='BOG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 07',7,true from public.projects p join public.modules m on m.code='M07' where p.code='BOG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 08',8,true from public.projects p join public.modules m on m.code='M08' where p.code='BOG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 09',9,true from public.projects p join public.modules m on m.code='M09' where p.code='BOG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 10',10,true from public.projects p join public.modules m on m.code='M10' where p.code='BOG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 11',11,true from public.projects p join public.modules m on m.code='M11' where p.code='BOG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 12',12,true from public.projects p join public.modules m on m.code='M12' where p.code='BOG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 13',13,true from public.projects p join public.modules m on m.code='M13' where p.code='BOG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 14',14,true from public.projects p join public.modules m on m.code='M14' where p.code='BOG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 15',15,true from public.projects p join public.modules m on m.code='M15' where p.code='BOG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 16',16,true from public.projects p join public.modules m on m.code='M16' where p.code='BOG' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Geral do projeto',0,true from public.projects p join public.modules m on m.code='MOD-GERAL' where p.code='CRUSOE' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 01',1,true from public.projects p join public.modules m on m.code='M01' where p.code='CRUSOE' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 02',2,true from public.projects p join public.modules m on m.code='M02' where p.code='CRUSOE' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 03',3,true from public.projects p join public.modules m on m.code='M03' where p.code='CRUSOE' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 04',4,true from public.projects p join public.modules m on m.code='M04' where p.code='CRUSOE' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 05',5,true from public.projects p join public.modules m on m.code='M05' where p.code='CRUSOE' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 06',6,true from public.projects p join public.modules m on m.code='M06' where p.code='CRUSOE' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 07',7,true from public.projects p join public.modules m on m.code='M07' where p.code='CRUSOE' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 08',8,true from public.projects p join public.modules m on m.code='M08' where p.code='CRUSOE' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 09',9,true from public.projects p join public.modules m on m.code='M09' where p.code='CRUSOE' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 10',10,true from public.projects p join public.modules m on m.code='M10' where p.code='CRUSOE' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 11',11,true from public.projects p join public.modules m on m.code='M11' where p.code='CRUSOE' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 12',12,true from public.projects p join public.modules m on m.code='M12' where p.code='CRUSOE' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 13',13,true from public.projects p join public.modules m on m.code='M13' where p.code='CRUSOE' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 14',14,true from public.projects p join public.modules m on m.code='M14' where p.code='CRUSOE' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 15',15,true from public.projects p join public.modules m on m.code='M15' where p.code='CRUSOE' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;
insert into public.project_modules(project_id,module_id,display_name,order_index,active) select p.id,m.id,'Módulo 16',16,true from public.projects p join public.modules m on m.code='M16' where p.code='CRUSOE' on conflict(project_id,module_id) do update set display_name=excluded.display_name,order_index=excluded.order_index,active=excluded.active;

create or replace function public.aponta_validate_entry_flow_v212()
returns trigger
language plpgsql
as $$
begin
  -- Registros antigos sem área continuam válidos; novos registros do app usam área obrigatoriamente.
  if new.area_code is null then return new; end if;

  if not exists (
    select 1 from public.activity_area_links l
    where l.activity_id = new.activity_id and l.area_code = new.area_code
  ) then
    raise exception 'A atividade selecionada não pertence à área informada.';
  end if;

  if new.area_code = 'FAB' then
    if new.sector_id is null then raise exception 'Informe o setor de fabricação.'; end if;
    new.module_id := null; new.room_id := null; new.panel_type_id := null;
  elsif new.area_code = 'MES' then
    if new.module_id is null then raise exception 'Informe o módulo da montagem estrutural.'; end if;
    new.sector_id := null; new.room_id := null; new.panel_type_id := null;
  elsif new.area_code = 'MPA' then
    if new.panel_type_id is null then raise exception 'Informe o tipo de painel.'; end if;
    new.sector_id := null; new.module_id := null; new.room_id := null;
  elsif new.area_code = 'MFI' then
    if new.room_id is null then raise exception 'Informe a sala da montagem final.'; end if;
    new.sector_id := null; new.module_id := null; new.panel_type_id := null;
  elsif new.area_code = 'ADM' then
    new.sector_id := null; new.module_id := null; new.room_id := null; new.panel_type_id := null;
  else
    raise exception 'Área inválida.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validate_entry_flow_v212 on public.time_entries;
create trigger trg_validate_entry_flow_v212
before insert or update on public.time_entries
for each row execute function public.aponta_validate_entry_flow_v212();

-- Vincular atividades antigas que não vieram da planilha à área Administrativa.
insert into public.activity_area_links(activity_id,area_code)
select a.id,'ADM' from public.activities a
where not exists(select 1 from public.activity_area_links l where l.activity_id=a.id)
on conflict do nothing;

select
  (select count(*) from public.work_areas) as areas,
  (select count(*) from public.manufacturing_sectors) as setores,
  (select count(*) from public.modules) as modulos,
  (select count(*) from public.rooms) as salas,
  (select count(*) from public.panel_types) as tipos_painel,
  (select count(*) from public.activities where code is not null) as atividades_planilha,
  (select count(*) from public.activity_area_links) as vinculos_atividade_area;


-- APONTA P3 v2.13.0 — ESTRUTURA PROJETO > SALA > MÓDULO
-- Gerado a partir da planilha revisada Proposta_Revisao_Projetos_Areas_Atividades_Setores_ApontaP3(1).xlsx
-- Execute todo este arquivo no SQL Editor do Supabase antes de publicar o app v2.13.0.

create extension if not exists pgcrypto;

create table if not exists public.project_rooms (
  project_id uuid not null references public.projects(id) on delete cascade,
  room_id uuid not null references public.rooms(id) on delete cascade,
  display_name text not null default '',
  order_index integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key(project_id, room_id)
);

create table if not exists public.project_room_modules (
  project_id uuid not null references public.projects(id) on delete cascade,
  room_id uuid not null references public.rooms(id) on delete cascade,
  module_id uuid not null references public.modules(id) on delete cascade,
  display_name text not null default '',
  order_index integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key(project_id, room_id, module_id)
);

create index if not exists idx_project_rooms_project_v213
  on public.project_rooms(project_id);

create index if not exists idx_project_room_modules_project_room_v213
  on public.project_room_modules(project_id, room_id);

alter table public.project_rooms enable row level security;
alter table public.project_room_modules enable row level security;

grant select, insert, update, delete on public.project_rooms,
  public.project_room_modules to authenticated;

drop policy if exists project_rooms_select_v213 on public.project_rooms;
create policy project_rooms_select_v213 on public.project_rooms
  for select to authenticated using (true);

drop policy if exists project_rooms_insert_v213 on public.project_rooms;
create policy project_rooms_insert_v213 on public.project_rooms
  for insert to authenticated
  with check ((select public.is_manager()));

drop policy if exists project_rooms_update_v213 on public.project_rooms;
create policy project_rooms_update_v213 on public.project_rooms
  for update to authenticated
  using ((select public.is_manager()))
  with check ((select public.is_manager()));

drop policy if exists project_rooms_delete_v213 on public.project_rooms;
create policy project_rooms_delete_v213 on public.project_rooms
  for delete to authenticated
  using ((select public.is_manager()));

drop policy if exists project_room_modules_select_v213 on public.project_room_modules;
create policy project_room_modules_select_v213 on public.project_room_modules
  for select to authenticated using (true);

drop policy if exists project_room_modules_insert_v213 on public.project_room_modules;
create policy project_room_modules_insert_v213 on public.project_room_modules
  for insert to authenticated
  with check ((select public.is_manager()));

drop policy if exists project_room_modules_update_v213 on public.project_room_modules;
create policy project_room_modules_update_v213 on public.project_room_modules
  for update to authenticated
  using ((select public.is_manager()))
  with check ((select public.is_manager()));

drop policy if exists project_room_modules_delete_v213 on public.project_room_modules;
create policy project_room_modules_delete_v213 on public.project_room_modules
  for delete to authenticated
  using ((select public.is_manager()));


create temporary table tmp_v213_projects (
  code text primary key,
  name text not null,
  client_name text not null,
  project_status text not null,
  active boolean not null
) on commit drop;

insert into tmp_v213_projects(code,name,client_name,project_status,active) values
('INTERNO-EM','Atividades internas da Engenharia de Manufatura','Interno','Em andamento',true),
('AWS','AWS','','Em andamento',true),
('TB11','TB11','','Em andamento',true),
('UFG','UFG','','Em andamento',true),
('PRODEB','PRODEB','','Em andamento',true),
('BARBADOS','BARBADOS','','Em andamento',true),
('FOR','FOR','','Em andamento',true),
('BOG','BOG','','Em andamento',true),
('CRUSOE','CRUSOE','','Em andamento',true);

update public.projects p
set name=t.name,
    client_name=t.client_name,
    project_status=t.project_status,
    active=t.active
from tmp_v213_projects t
where p.code=t.code
   or (p.code is null and p.name=t.name);

insert into public.projects(code,name,client_name,project_status,active)
select t.code,t.name,t.client_name,t.project_status,t.active
from tmp_v213_projects t
where not exists (
  select 1 from public.projects p
  where p.code=t.code or p.name=t.name
);


insert into public.work_areas(code,name,detail_type,order_index,active) values
('FAB','Fabricação','sector',1,true),
('MES','Montagem Estrutural','module',2,true),
('MPA','Montagem de Painéis','panel_type',3,true),
('MFI','Montagem Final','room',4,true),
('ADM','Administrativo','none',5,true)
on conflict(code) do update set
  name=excluded.name,
  detail_type=excluded.detail_type,
  order_index=excluded.order_index,
  active=excluded.active;


-- Corrige o código duplicado PINT da proposta anterior sem perder referências históricas.
update public.manufacturing_sectors s
set code=case
  when upper(s.name) like '%ELETROSTAT%' then 'PINT-PINTURA-ELETROSTATICA'
  else 'PINT-PINTURA-LIQUIDA'
end
where s.code='PINT'
  and not exists (
    select 1 from public.manufacturing_sectors s2
    where s2.code=case
      when upper(s.name) like '%ELETROSTAT%'
        then 'PINT-PINTURA-ELETROSTATICA'
      else 'PINT-PINTURA-LIQUIDA'
    end
  );

insert into public.manufacturing_sectors(code,name,description,order_index,active) values
('GERAL','GERAL FABRICAÇÃO','Atividade que abrange mais de um setor de fabricação.',1,true),
('PINT-PINTURA-LIQUIDA','PINTURA LIQUIDA','Preparação de superfície e pintura.',2,true),
('PINT-PINTURA-ELETROSTATICA','PINTURA ELETROSTATICA','Preparação de superfície e pintura.',3,true),
('SUBCONJUNTO','SUB CONJUNTO','Pré-montagem, separação e preparação de unidades.',4,true),
('KIT','PREARAÇAO DE KITS','Montagem e conferência de kits de produção.',5,true),
('LASER','LASER','Programação, nesting e corte a laser.',6,true),
('SERRA','SERRA','Serramento, furação e preparação de perfis.',7,true),
('FURAÇÃO','Área de  Furação','',0,false),
('DETALHAMENTO','Área de Detalhamento','',0,false),
('DOBRA','DOBRA','Dobra de chapas, perfis e barramentos.',8,true),
('SOLDA','SOLDA','Soldagem, caldeiraria e subconjuntos.',9,true),
('JATO','JATEAMENTO','Preparação de superfície por jateamento.',10,true),
('INSP','INSPEÇAO DAQUALIDADE','Inspeções dimensionais, visuais e de processo.',11,true),
('RETRAB','RETRABALHO','Ajustes, correções e retrabalhos controlados.',12,true),
('FUR','FURAÇÃO','Furaçao',13,true),
('DET','DETALHAMENTO','detalhamento',14,true),
('LIMP. LASER','LIMPEZA LASER','limpeza a laser',15,true),
('PREP. SUBS','PREPARAÇÃO DE SUBSTRATO','preparaçao de substrato',16,true),
('SETOR-OUTRO','Outro setor de fabricação','Usar quando o setor específico ainda não estiver cadastrado.',99,true)
on conflict(code) do update set
  name=excluded.name,
  description=excluded.description,
  order_index=excluded.order_index,
  active=excluded.active;

insert into public.panel_types(code,name,order_index,active) values
('UPS','UPS',1,true),
('BMS','BMS',2,true),
('RPP','RPP',3,true),
('QGBT','QGBT',4,true),
('PDU','PDU',5,true),
('ATS','ATS',6,true),
('CCM','CCM',7,true),
('PBT','Painel BT',8,true),
('PMT','Painel MT',9,true),
('AUT','Painel de Automação',10,true),
('CTRL','Painel de Controle',11,true),
('AUX','Painel Auxiliar',12,true),
('OUTRO','Outro tipo de painel',99,true)
on conflict(code) do update set
  name=excluded.name,
  order_index=excluded.order_index,
  active=excluded.active;


insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values
('DH','Data Hall','','Sala principal de TI',3,true),
('SE','Sala Elétrica','','Sala elétrica geral',4,true),
('SALA-SALA-CATCHER','SALA CATCHER','','Sala vinculada à estrutura do projeto.',0,true),
('SALA-SALA-MEDIA','SALA MEDIA','','Sala vinculada à estrutura do projeto.',0,true),
('SALA-SALA-DE-MAQUINAS','SALA DE MAQUINAS','','Sala vinculada à estrutura do projeto.',0,true),
('PRJ-GERAL','Geral do projeto','','Sala vinculada à estrutura do projeto.',0,true),
('SALA-MONOBLOCO','MONOBLOCO','','Sala vinculada à estrutura do projeto.',0,true),
('SALA-GERAL','Geral do módulo','','Usar quando a atividade abrange todo o módulo',1,true),
('SALA-NA','Não aplicável','','Atividade sem vínculo com uma sala específica',2,true),
('BT','Sala de Baixa Tensão','','Painéis e distribuição BT',5,true),
('MT','Sala de Média Tensão','','Cubículos e sistemas de MT',6,true),
('UPS','Sala de UPS','','UPS e distribuição associada',7,true),
('BAT','Sala de Baterias','','Bancos de baterias e acessórios',8,true),
('TRAFO','Sala de Transformadores','','Transformadores e conexões',9,true),
('GER','Sala de Geradores','','Geradores e sistemas auxiliares',10,true),
('TELECOM','Sala de Telecom / MMR','','Telecomunicações e meet-me room',11,true),
('CTRL','Sala de Controle / BMS','','Controle, supervisão e BMS',12,true),
('CFTV','Sala de Segurança / CFTV','','CFTV e controle de acesso',13,true),
('SDACI','Sala / Área de SDACI','','Detecção, alarme e combate a incêndio',14,true),
('HVAC-SALA','Sala Mecânica / HVAC','','Climatização e equipamentos mecânicos',15,true),
('AGUA-GEL','Sala de Bombas / Água Gelada','','Bombas, manifolds e tubulação de água gelada',16,true),
('CATCHER','HVAC Catcher','','Unidade catcher acoplada ao Data Hall',17,true),
('COR-FRIO','Corredor Frio','','Corredor de insuflamento frio',18,true),
('COR-QUENTE','Corredor Quente','','Corredor de retorno quente',19,true),
('PLENUM','Plenum','','Plenum de insuflamento ou retorno',20,true),
('COR-TEC','Corredor Técnico','','Passagem técnica e manutenção',21,true),
('COR-ACESSO','Corredor de Acesso','','Circulação interna',22,true),
('ANTESSALA','Antessala','','Área de transição e acesso',23,true),
('COBERTURA','Cobertura / Teto','','Teto, cobertura e componentes superiores',24,true),
('BASE-PISO','Base / Piso Inferior','','Base estrutural e piso inferior',25,true),
('PISO-TEC','Piso Técnico / Elevado','','Piso elevado e infraestrutura associada',26,true),
('PAREDE-INT','Paredes Internas','','Paredes, divisórias e fechamentos internos',27,true),
('FACHADA','Paredes Externas / Fachada','','Envoltória e acabamento externo',28,true),
('CF','Compartimentação Corta-Fogo','','Selagens, portas e barreiras corta-fogo',29,true),
('INTERCON','Zona de Interconexão entre Módulos','','Interfaces e acoplamentos entre módulos',30,true),
('AREA-TEC-EXT','Área Técnica Externa','','Equipamentos e infraestrutura externos',31,true),
('EXPED','Área de Embalagem / Expedição','','Embalagem, amarração e expedição',32,true),
('FAB','Área de Fabricação','','Corte, dobra, solda e usinagem',33,true),
('PINT','Área de Pintura / Jateamento','','Preparação de superfície e pintura',34,true),
('MONT-EST','Área de Montagem Estrutural','','Bases, steel frame e estrutura',35,true),
('MONT-FINAL','Área de Montagem Final','','Integração e acabamentos finais',36,true),
('PAINEIS','Área de Montagem de Painéis','','Montagem de painéis e barramentos',37,true),
('TESTES','Área de Testes / FAT','','Inspeções, testes e FAT',38,true),
('ALMOX','Almoxarifado / Preparação de Kits','','Separação, conferência e preparação de materiais',39,true),
('OUTRA','Outra sala / área','','Cadastrar nova opção quando recorrente',40,true),
('NOC','Sala NOC / Operação','','Centro de operação e monitoramento',41,true),
('PDU-RPP','Sala PDU / RPP','','Distribuição elétrica próxima às cargas de TI',42,true),
('QGBT-MCC','Sala QGBT / MCC','','Quadros gerais, CCM e distribuição de potência',43,true),
('PROT-MED','Sala de Proteção e Medição','','Relés, medição, proteção e controle',44,true),
('SAUX','Sala de Serviços Auxiliares','','Serviços auxiliares CA/CC',45,true),
('RET','Sala de Retificadores','','Retificadores e sistemas CC',46,true),
('BCAP','Sala de Banco de Capacitores','','Correção de fator de potência e filtros',47,true),
('CHILLER','Sala / Área de Chillers','','Chillers e equipamentos associados',48,true),
('CRAH','Sala / Área de CRAH-CRAC','','Unidades de tratamento e climatização do Data Hall',49,true),
('MANIFOLD','Área de Manifold','','Manifolds, válvulas e distribuição hidráulica',50,true),
('BOMB-INC','Sala de Bombas de Incêndio','','Bombas e sistemas hidráulicos de incêndio',51,true),
('GAS-INC','Sala de Cilindros / Supressão por Gás','','Cilindros e sistemas de supressão por gás',52,true),
('MANTRAP','Eclusa / Mantrap','','Controle físico de acesso',53,true),
('ROOFTOP','Cobertura Técnica / Rooftop','','Equipamentos e interligações na cobertura',54,true),
('PASSARELA','Passarela / Ponte Técnica','','Conexões, travessias e acesso técnico',55,true),
('DOCA','Doca / Carga e Descarga','','Recebimento, carregamento e descarregamento',56,true),
('STAGING','Área de Staging / Pré-montagem','','Pré-montagem, separação e preparação de unidades',57,true),
('KIT','Área de Kitting / Preparação de Kits','','Montagem e conferência de kits de produção',58,true),
('LASER','Área de Corte Laser / Lantek','','Programação, nesting e corte a laser',59,true),
('SERRA-FUR','Área de Serra e Furação','','Serramento, furação e preparação de perfis',60,true),
('DOBRA','Área de Dobra e Conformação','','Dobra de chapas, perfis e barramentos',61,true),
('SOLDA','Área de Soldagem e Caldeiraria','','Soldagem, caldeiraria e subconjuntos',62,true),
('JATO','Área de Jateamento','','Preparação de superfície por jateamento',63,true),
('CAB-PINT','Cabine / Área de Pintura','','Pintura líquida, eletrostática e cura',64,true),
('MONT-MEC','Área de Montagem Mecânica','','Montagem de equipamentos e sistemas mecânicos',65,true),
('MONT-ELET','Área de Montagem Elétrica','','Infraestrutura, cabos, eletrocalhas e ligações',66,true),
('PAINEL-BT','Área de Painéis BT','','Montagem de painéis de baixa tensão',67,true),
('PAINEL-MT','Área de Painéis MT','','Montagem de painéis de média tensão',68,true),
('BARRAMENTO','Área de Fabricação de Barramentos','','Corte, dobra, furação e preparação de barramentos',69,true),
('BANC-ELET','Bancada Elétrica','','Montagem, crimpagem e testes de componentes elétricos',70,true),
('BANC-MEC','Bancada Mecânica','','Ajustes, preparação e montagem de componentes mecânicos',71,true),
('INSP','Área de Inspeção da Qualidade','','Inspeções dimensionais, visuais e de processo',72,true),
('LAB-TESTE','Laboratório / Bancada de Testes','','Ensaios, medições e validações técnicas',73,true),
('QUARENT','Área de Quarentena / Material Não Conforme','','Segregação e tratativa de materiais não conformes',74,true),
('RETRAB','Área de Retrabalho','','Ajustes, correções e retrabalhos controlados',75,true)
on conflict(code) do update set
  name=excluded.name,
  usage_suggested=excluded.usage_suggested,
  order_index=excluded.order_index,
  active=excluded.active;


insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values
('MOD1','MOD1','','Módulo vinculado a uma sala do projeto.',0,true),
('MOD2','MOD2','','Módulo vinculado a uma sala do projeto.',1,true),
('MOD3','MOD3','','Módulo vinculado a uma sala do projeto.',2,true),
('MOD4','MOD4','','Módulo vinculado a uma sala do projeto.',3,true),
('MOD5','MOD5','','Módulo vinculado a uma sala do projeto.',4,true),
('MOD6','MOD6','','Módulo vinculado a uma sala do projeto.',5,true),
('MOD7','MOD7','','Módulo vinculado a uma sala do projeto.',6,true),
('MOD8','MOD8','','Módulo vinculado a uma sala do projeto.',7,true),
('M04','Módulo 04','','Módulo vinculado a uma sala do projeto.',4,true),
('M05','Módulo 05','','Módulo vinculado a uma sala do projeto.',5,true),
('M06','Módulo 06','','Módulo vinculado a uma sala do projeto.',6,true),
('M07','Módulo 07','','Módulo vinculado a uma sala do projeto.',7,true),
('M08','Módulo 08','','Módulo vinculado a uma sala do projeto.',8,true),
('M09','Módulo 09','','Módulo vinculado a uma sala do projeto.',9,true),
('M10','Módulo 10','','Módulo vinculado a uma sala do projeto.',10,true),
('M11','Módulo 11','','Módulo vinculado a uma sala do projeto.',11,true),
('M12','Módulo 12','','Módulo vinculado a uma sala do projeto.',12,true),
('M13','Módulo 13','','Módulo vinculado a uma sala do projeto.',13,true),
('M14','Módulo 14','','Módulo vinculado a uma sala do projeto.',14,true),
('M15','Módulo 15','','Módulo vinculado a uma sala do projeto.',15,true),
('M16','Módulo 16','','Módulo vinculado a uma sala do projeto.',16,true),
('MOD-GERAL','Geral do projeto','','Módulo vinculado a uma sala do projeto.',0,true),
('M01','Módulo 01','','Módulo vinculado a uma sala do projeto.',1,true),
('M02','Módulo 02','','Módulo vinculado a uma sala do projeto.',2,true),
('M03','Módulo 03','','Módulo vinculado a uma sala do projeto.',3,true)
on conflict(code) do update set
  name=excluded.name,
  usage_suggested=excluded.usage_suggested,
  order_index=excluded.order_index,
  active=excluded.active;


create temporary table tmp_v213_activities (
  code text primary key,
  name text not null,
  discipline_name text not null,
  sector_principal text not null,
  nature text not null,
  observation_requirement text not null,
  active boolean not null
) on commit drop;

insert into tmp_v213_activities(
  code,name,discipline_name,sector_principal,nature,
  observation_requirement,active
) values
('GES-001','Planejamento diário das atividades','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-002','Planejamento semanal das entregas','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-003','Priorização de demandas do projeto','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-004','Acompanhamento do cronograma de manufatura','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-005','Reunião de projeto','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-006','Reunião com Produção','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-007','Reunião com Engenharia de Produto / DFMA','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-008','Reunião com Qualidade','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-009','Reunião com fornecedor ou cliente','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-010','SQDC','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-011','OBEYA','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-012','Atualização de indicadores e relatórios','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-013','Preparação de apresentação técnica','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-014','Treinamento, integração ou capacitação','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-015','Distribuição e acompanhamento de tarefas da equipe','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-016','Reunião com PCP e planejamento','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-020','Reunião com Compras','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-021','Reunião com Suprimentos','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-022','Reunião de alinhamento multidisciplinar','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-023','Atualização do status das demandas','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-024','Conferência de apontamentos e horas da equipe','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-025','Fechamento e registro de atividades concluídas','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('DFM-001','Análise de fabricabilidade','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-002','Análise de montabilidade','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-003','Análise de acesso para fabricação e montagem','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-004','Análise de acesso para manutenção','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-005','Análise de interfaces entre disciplinas','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-006','Análise de interferências','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-007','Verificação de cotas, tolerâncias e detalhes construtivos','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-008','Verificação de materiais e especificações','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-009','Verificação de BOM / lista de materiais','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-010','Análise de Red Pen / marcações de campo','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-011','Análise de DANE ou SAE','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-012','Revisão técnica de desenho','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-013','Aprovação e liberação de desenho','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-014','Devolução de desenho para correção','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-015','Tratativa de alteração de engenharia / CCB','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-016','Padronização, simplificação ou nacionalização do produto','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-017','Análise de peça especial ou solução não padronizada','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-018','Análise de transporte e embalagem no desenvolvimento do produto','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-019','Análise de manutenção e substituição de componentes','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-020','Validação da alteração incorporada ao desenho','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('PRC-001','Desenvolvimento de processo de fabricação','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-002','Desenvolvimento de processo de montagem','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-003','Revisão e otimização de processo existente','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-004','Definição da sequência de fabricação','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-005','Definição da sequência de montagem','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-006','Definição de método, máquinas, ferramentas e recursos','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-007','Elaboração de instrução de trabalho','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-008','Revisão de instrução de trabalho','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-009','Elaboração de auxílio visual ou padrão operacional','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-010','Estudo de tempos','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-011','Definição de tempo padrão e tempo de ciclo','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-012','Análise de capacidade produtiva','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-013','Dimensionamento de mão de obra','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-014','Balanceamento de atividades ou linha','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-015','Desenvolvimento ou alteração de layout','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-016','Acompanhamento de primeira execução / try-out','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-017','Validação e liberação de processo','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-018','Treinamento da produção e acompanhamento de ramp-up','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-019','Levantamento do processo atual em fábrica','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-020','Criação de fluxograma ou mapa de processo','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-021','Elaboração de checklist de processo','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-022','Preparação do plano de industrialização','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-023','Acompanhamento de processo executado por fornecedor','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('SAP-001','Criação de rota de fabricação ou montagem','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-002','Revisão de rota','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-003','Verificação de rota versus processo real','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-004','Criação de operação','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-005','Alteração ou correção de operação','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-006','Definição da sequência de operações','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-007','Cadastro ou correção de centro de trabalho','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-008','Cadastro de tempos de operação','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-009','Revisão e validação de tempos no SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-010','Criação ou consulta de ordem de produção','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-011','Verificação de ordem de produção','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-012','Correção de ordem ou sequência de operações','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-013','Verificação de apontamentos de produção','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-014','Correção ou estorno de apontamentos','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-015','Análise de divergência entre roteiro, OP e produção','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-016','Cadastro, saneamento ou atualização em massa de dados mestres','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-017','Criação ou revisão de versão de produção','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-018','Liberação técnica de roteiro ou operação','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-019','Verificação de consumo e baixa de materiais','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-020','Análise de estorno ou correção de componentes','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-021','Verificação do status e avanço da ordem de produção','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-022','Fechamento técnico de ordem de produção','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-023','Extração e análise de dados do SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-024','Apoio ao usuário em transação SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-025','Teste e validação de alteração realizada no SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('LTK-001','Cadastro ou importação de geometrias no Lantek','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-002','Revisão do desenho para programação','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-003','Criação de nesting manual','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-004','Criação de nesting automático','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-005','Revisão de nesting','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-006','Otimização de nesting e aproveitamento de chapa','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-007','Análise e reaproveitamento de retalhos','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-008','Definição ou ajuste de parâmetros de corte','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-009','Suporte técnico à máquina ou à produção','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-010','Gestão de biblioteca de materiais e chapas','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-011','Acompanhamento da primeira chapa cortada','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-012','Reprogramação por alteração de desenho','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-013','Análise de tempo estimado de corte','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('FAB-001','Atendimento tecnico do processo de corte','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-002','Atendimento tecnico do processo de furação','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-003','Atendimento tecnico do processo de dobra','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-004','Atendimento tecnico do processo de detalhamento','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-005','Atendimento tecnico do processo de soldagem','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-006','Atendimento tecnico de caldeiraria e montagem de subconjuntos','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-007','Definição de gabaritos e meios de fixação','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-008','Definição ou ajuste de parâmetros de máquina','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-009','Validação de primeira peça fabricada','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-010','Acompanhamento de fabricação crítica','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-011','Tratativa de desvio dimensional','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-012','Tratativa de falta ou incompatibilidade de material','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-013','Definição e acompanhamento de retrabalho ou refugo','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-014','Atendimento tecnico do processo de serra','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-015','Análise de marcação e identificação de peças','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-016','Definição da sequência de fabricação de subconjuntos','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-017','Análise de capacidade e disponibilidade de máquina','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-018','Definição ou ajuste de ferramental de fabricação','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-019','Análise de consumíveis e parâmetros de processo','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-020','Acompanhamento de protótipo ou lote piloto','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-021','Análise de preparação de superfície','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-002','Análise do processo de jateamento','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-003','Análise de pintura líquida','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-004','Análise de pintura eletrostática','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-005','Análise de pintura intumescente','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-006','Verificação de ponto de orvalho e condição ambiental','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-007','Análise de vedação e aplicação de selantes','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-008','Acompanhamento de processo crítico de pintura','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-009','Tratativa de falha, corrosão ou retrabalho superficial','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-010','Definição de mascaramento e proteção de superfícies','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-011','Cálculo ou estimativa de consumo de tinta e insumos','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-012','Análise de cura, secagem e intervalo entre demãos','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-013','Validação do reparo de pintura ou corrosão','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('MES-001','Definição da sequência de montagem estrutural','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Não',true),
('MES-002','Atendimento tecnico de montagem Estrutual','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Não',true),
('MES-003','Definição ou validação de torque estrutural','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Não',true),
('MES-004','Análise de içamento e pontos de pega','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Não',true),
('MES-005','Análise de movimentação e posicionamento de estruturas','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Não',true),
('MES-006','Análise de acoplamento entre módulos','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Não',true),
('MES-007','Análise de suportes e suportagem','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Não',true),
('MES-008','Definição de ajuste, retrabalho e liberação estrutural','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Não',true),
('MES-009','Análise e validação de gabarito estrutural','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Não',true),
('MFI-001','Definição da sequência de montagem final','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-002','Análise de instalação de HVAC e climatização','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-003','Análise de tubulação de água gelada','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-004','Análise de ventilação e renovação de ar','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-005','Análise de eletrocalhas e leitos','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-006','Análise de eletrodutos e canaletas','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-007','Análise de infraestrutura elétrica','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-008','Análise de BMS e automação','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-009','Análise de CFTV e controle de acesso','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-010','Análise de detecção, alarme e combate a incêndio','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-011','Análise de iluminação e aterramento','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-012','Análise de pisos, forros e revestimentos','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-013','Análise de portas, janelas e fechamentos','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-014','Análise de vedação e selagem corta-fogo','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-015','Análise de instalação e fixação de equipamentos','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-016','Análise de interconexões entre módulos','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-017','Acompanhamento de montagem final crítica','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-018','Definição de ajuste, retrabalho e liberação final','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-019','Análise de embalagem, amarração e transporte','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-020','Atendimento técnico à montagem final','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-021','Análise de rota multidisciplinar','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-022','Análise de suportação e pontos de fixação','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-023','Coordenação e tratativa de interferências em montagem','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-024','Análise de acessibilidade e manutenção dos sistemas','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-025','Análise de interfaces entre montagem final e painéis','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-026','Acompanhamento de interligações mecânicas e elétricas','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-027','Acompanhamento de preparação para transporte e entrega','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MPA-001','Definição da sequência de montagem do painel','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-002','Análise do layout interno do painel','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-003','Análise do posicionamento de componentes','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-004','Análise de fabricação de barramentos rígidos','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-005','Análise de montagem e conexão de barramentos','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-006','Análise de barramentos flexíveis','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-007','Análise de corte, dobra e furação de barramentos','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-008','Análise de tratamento superficial de barramentos','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-009','Análise de cabos, terminais e crimpagem','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-010','Análise de identificação, anilhas e etiquetas','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-011','Definição ou validação de torque elétrico','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-012','Análise de furação, portas e adaptações mecânicas','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-013','Análise de transformadores, TCs e instrumentos','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-014','Verificação de continuidade e isolação — Painéis','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-015','Acompanhamento de testes funcionais','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-016','Acompanhamento de energização ou painel energizado','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-017','Apoio técnico ao FAT de painéis','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-018','Definição de ajuste, retrabalho e liberação do painel','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-019','Análise da lista de materiais do painel','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-020','Definição de ferramentas, bancadas e recursos','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-021','Verificação de diagrama e documentação para montagem','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-022','Correção de montagem após teste ou inspeção','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('QLD-001','Inspeção e validação dimensional','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-002','Validação de primeira peça','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-003','Validação de processo de fabricação','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-004','Validação de montagem estrutural','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-005','Validação de montagem final','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-006','Validação de montagem de painéis','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-007','Validação de soldagem','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-008','Validação de pintura e proteção anticorrosiva','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-009','Validação de vedação e acabamento','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-010','Validação de torque e fixações','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-011','Verificação ou relatório Qualificação de Instalação (IQ)','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-012','Verificação ou relatório Qualificação de Operação(OQ)','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-013','Verificação ou relatório Qualificação de Desempenho (PQ)','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-014','Auditoria de processo','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-015','Análise de RNC / não conformidade','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-016','Investigação de causa raiz','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-017','Definição de contenção, retrabalho e verificação de eficácia','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-018','Registro e aplicação de lição aprendida','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-019','Elaboração ou revisão de PFMEA','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-020','Elaboração ou revisão de Plano de Controle','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-021','Elaboração ou revisão de plano de inspeção','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-022','Elaboração de A3 ou 8D','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-023','Análise de capacidade e estabilidade do processo','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-024','Acompanhamento de auditoria de cliente ou terceira parte','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-025','Análise de reincidência de não conformidade','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-026','Fechamento de punch list de fabricação ou montagem','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-027','Organização e validação de evidências da qualidade','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('SST-001','Reunião com Segurança do Trabalho','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-002','DDS ou alinhamento de segurança','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-003','Análise de risco do processo','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-004','Avaliação ergonômica do posto de trabalho','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-005','Análise de movimentação manual de carga','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-006','Análise de içamento e movimentação mecanizada','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-007','Avaliação de segurança de máquina','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-008','Avaliação de segurança de ferramenta ou dispositivo','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-009','Análise de bloqueio, etiquetagem e energias perigosas','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-010','Análise de trabalho em altura e acesso','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-011','Análise de produtos químicos, pintura e ventilação','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-012','Análise ambiental, resíduos e impacto do processo','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-013','Definição e acompanhamento de melhoria de segurança ou ergonomia','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-014','Elaboração ou revisão de APR','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-015','Definição de EPI e EPC do processo','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-016','Validação de proteção e adequação de máquina','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-017','Análise de acesso e manutenção segura','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-018','Reunião específica de ergonomia','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-019','Análise de altura, alcance, postura e esforço no posto','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-020','Acompanhamento da adequação de segurança ou ergonomia','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-021','Validação da condição após implantação da melhoria','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('MEL-001','Evento Kaizen ou melhoria contínua','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-002','Melhoria de produtividade','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-003','Redução de custos','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-004','Redução de desperdício, refugo ou retrabalho','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-005','Melhoria de layout ou posto de trabalho','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-006','Padronização entre projetos','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-007','Desenvolvimento de dispositivo/gabaritos','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-008','Acompanhamento da fabricação de dispositivo','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-009','Try-out e ajuste de dispositivo','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-010','Validação e liberação de dispositivo','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-011','Automação ou digitalização de processo','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-012','Desenvolvimento de Power BI, Power Apps, SharePoint ou APP','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-013','Levantamento de oportunidade de melhoria','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-014','Estudo de viabilidade técnica e econômica','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-015','Mapeamento de fluxo de valor','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-016','Implantação ou auditoria de 5S','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-017','Desenvolvimento de trabalho padronizado','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-018','Desenvolvimento de poka-yoke','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-019','Análise e redução de tempo de setup','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-020','Implantação de Kanban ou gestão visual de fluxo','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('PCP-001','Planejamento da demanda de fabricação e montagem','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Não',true),
('PCP-002','Revisão do sequenciamento de produção','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Não',true),
('PCP-003','Análise de carga e capacidade por recurso','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Não',true),
('PCP-004','Acompanhamento da programação diária ou semanal','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Não',true),
('PCP-005','Verificação de disponibilidade de máquina, mão de obra e recurso','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Não',true),
('PCP-006','Atualização do cronograma de manufatura','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Não',true),
('PCP-007','Reunião e alinhamento com PCP','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Não',true),
('PCP-008','Definição de prioridade de ordens de produção','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Não',true),
('PCP-009','Análise de atraso e plano de recuperação','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Não',true),
('PCP-010','Controle de avanço físico por módulo ou sala','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Não',true),
('MAT-001','Análise de necessidade de material','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Não',true),
('MAT-002','Verificação de disponibilidade em estoque','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Não',true),
('MAT-003','Análise e aprovação de material alternativo','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Não',true),
('MAT-004','Elaboração de especificação técnica para compra','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Não',true),
('MAT-005','Solicitação ou requisição de compra técnica','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Não',true),
('MAT-006','Reunião técnica com fornecedor','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Não',true),
('MAT-007','Follow-up de fabricação ou entrega de fornecedor','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Não',true),
('MAT-008','Aprovação de amostra ou protótipo de fornecedor','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Não',true),
('MAT-009','Análise de nacionalização de componente ou fornecedor','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Não',true),
('DOC-001','Criação ou revisão de documentação técnica','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Não',true),
('DOC-002','Cadastro, publicação ou atualização de documento no sistema','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Não',true),
('DOC-003','Análise de documento recebido de outra área ou fornecedor','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Não',true),
('DOC-004','Revisão e atualização de desenho as-built','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Não',true),
('DOC-005','Controle e consolidação de Red Pen','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Não',true),
('DOC-006','Registro e acompanhamento de DANE ou mudança','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Não',true),
('DOC-007','Elaboração e atualização de lista de pendências','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Não',true),
('DOC-008','Organização de registros e evidências técnicas','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Não',true),
('DOC-009','Emissão de relatório técnico','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Não',true),
('DOC-010','Atualização de matriz ou índice de documentos','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Não',true),
('TST-001','Planejamento de teste ou FAT','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-002','Preparação de checklist, procedimento ou protocolo de teste','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-003','Verificação de pré-requisitos para teste','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-004','Acompanhamento de FAT / L1','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-005','Acompanhamento de SAT / L2 de fábrica ou pré-site','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-006','Apoio a startup e energização controlada','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-007','Acompanhamento de teste funcional','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-008','Verificação de continuidade e isolação — Testes/FAT','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-009','Verificação de torque e conexões','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-010','Teste de vedação, estanqueidade ou acabamento','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-011','Teste de pintura, espessura ou aderência','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-012','Tratativa e acompanhamento de punch list','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-013','Registro e organização de evidências de teste','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-014','Análise de falha identificada em teste','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-015','Liberação técnica após teste','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('FAB-021-FABRICACAO-M','Atendimento técnico Jateamento','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-022','Atendimento técnico Limpeza Laser','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-023','Atendimento técnico a Preparaçao de tintas','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true);

update public.activities a
set name=t.name,
    discipline_name=t.discipline_name,
    sector_principal=t.sector_principal,
    nature=t.nature,
    observation_requirement=t.observation_requirement,
    active=t.active
from tmp_v213_activities t
where a.code=t.code
   or (a.code is null and a.name=t.name);

insert into public.activities(
  code,name,discipline_name,sector_principal,nature,
  observation_requirement,usage_description,active,
  activity_type,frequency,responsible_name,backup_name
)
select
  t.code,t.name,t.discipline_name,t.sector_principal,t.nature,
  t.observation_requirement,
  'Registrar objetivamente a atividade executada e o resultado obtido.',
  t.active,'Demanda','','',''
from tmp_v213_activities t
where not exists (
  select 1 from public.activities a
  where a.code=t.code or a.name=t.name
);

create temporary table tmp_v213_activity_links (
  activity_code text not null,
  area_code text not null
) on commit drop;

insert into tmp_v213_activity_links(activity_code,area_code) values
('GES-001','ADM'),
('GES-002','ADM'),
('GES-003','ADM'),
('GES-004','ADM'),
('GES-005','ADM'),
('GES-006','ADM'),
('GES-007','ADM'),
('GES-008','ADM'),
('GES-009','ADM'),
('GES-010','ADM'),
('GES-011','ADM'),
('GES-012','ADM'),
('GES-013','ADM'),
('GES-014','ADM'),
('GES-015','ADM'),
('GES-016','ADM'),
('GES-020','ADM'),
('GES-021','ADM'),
('GES-022','ADM'),
('GES-023','ADM'),
('GES-024','ADM'),
('GES-025','ADM'),
('DFM-001','ADM'),
('DFM-002','ADM'),
('DFM-003','ADM'),
('DFM-004','ADM'),
('DFM-005','ADM'),
('DFM-006','ADM'),
('DFM-007','ADM'),
('DFM-008','ADM'),
('DFM-009','ADM'),
('DFM-010','ADM'),
('DFM-011','ADM'),
('DFM-012','ADM'),
('DFM-013','ADM'),
('DFM-014','ADM'),
('DFM-015','ADM'),
('DFM-016','ADM'),
('DFM-017','ADM'),
('DFM-018','ADM'),
('DFM-019','ADM'),
('DFM-020','ADM'),
('PRC-001','ADM'),
('PRC-002','ADM'),
('PRC-003','ADM'),
('PRC-004','ADM'),
('PRC-005','ADM'),
('PRC-006','ADM'),
('PRC-007','ADM'),
('PRC-008','ADM'),
('PRC-009','ADM'),
('PRC-010','ADM'),
('PRC-011','ADM'),
('PRC-012','ADM'),
('PRC-013','ADM'),
('PRC-014','ADM'),
('PRC-015','ADM'),
('PRC-016','ADM'),
('PRC-017','ADM'),
('PRC-018','ADM'),
('PRC-019','ADM'),
('PRC-020','ADM'),
('PRC-021','ADM'),
('PRC-022','ADM'),
('PRC-023','ADM'),
('SAP-001','ADM'),
('SAP-002','ADM'),
('SAP-003','ADM'),
('SAP-004','ADM'),
('SAP-005','ADM'),
('SAP-006','ADM'),
('SAP-007','ADM'),
('SAP-008','ADM'),
('SAP-009','ADM'),
('SAP-010','ADM'),
('SAP-011','ADM'),
('SAP-012','ADM'),
('SAP-013','ADM'),
('SAP-014','ADM'),
('SAP-015','ADM'),
('SAP-016','ADM'),
('SAP-017','ADM'),
('SAP-018','ADM'),
('SAP-019','ADM'),
('SAP-020','ADM'),
('SAP-021','ADM'),
('SAP-022','ADM'),
('SAP-023','ADM'),
('SAP-024','ADM'),
('SAP-025','ADM'),
('LTK-001','FAB'),
('LTK-002','FAB'),
('LTK-003','FAB'),
('LTK-004','FAB'),
('LTK-005','FAB'),
('LTK-006','FAB'),
('LTK-007','FAB'),
('LTK-008','FAB'),
('LTK-009','FAB'),
('LTK-010','FAB'),
('LTK-011','FAB'),
('LTK-012','FAB'),
('LTK-013','FAB'),
('FAB-001','FAB'),
('FAB-002','FAB'),
('FAB-003','FAB'),
('FAB-004','FAB'),
('FAB-005','FAB'),
('FAB-006','FAB'),
('FAB-007','FAB'),
('FAB-008','FAB'),
('FAB-009','FAB'),
('FAB-010','FAB'),
('FAB-011','FAB'),
('FAB-012','FAB'),
('FAB-013','FAB'),
('FAB-014','FAB'),
('FAB-015','FAB'),
('FAB-016','FAB'),
('FAB-017','FAB'),
('FAB-018','FAB'),
('FAB-019','FAB'),
('FAB-020','FAB'),
('FAB-021','FAB'),
('FAB-021','MFI'),
('PIN-002','FAB'),
('PIN-002','MFI'),
('PIN-003','FAB'),
('PIN-003','MFI'),
('PIN-004','FAB'),
('PIN-004','MFI'),
('PIN-005','FAB'),
('PIN-005','MFI'),
('PIN-006','FAB'),
('PIN-006','MFI'),
('PIN-007','FAB'),
('PIN-007','MFI'),
('PIN-008','FAB'),
('PIN-008','MFI'),
('PIN-009','FAB'),
('PIN-009','MFI'),
('PIN-010','FAB'),
('PIN-010','MFI'),
('PIN-011','FAB'),
('PIN-011','MFI'),
('PIN-012','FAB'),
('PIN-012','MFI'),
('PIN-013','FAB'),
('PIN-013','MFI'),
('MES-001','MES'),
('MES-002','MES'),
('MES-003','MES'),
('MES-004','MES'),
('MES-005','MES'),
('MES-006','MES'),
('MES-007','MES'),
('MES-008','MES'),
('MES-009','MES'),
('MFI-001','MFI'),
('MFI-002','MFI'),
('MFI-003','MFI'),
('MFI-004','MFI'),
('MFI-005','MFI'),
('MFI-006','MFI'),
('MFI-007','MFI'),
('MFI-008','MFI'),
('MFI-009','MFI'),
('MFI-010','MFI'),
('MFI-011','MFI'),
('MFI-012','MFI'),
('MFI-013','MFI'),
('MFI-014','MFI'),
('MFI-015','MFI'),
('MFI-016','MFI'),
('MFI-017','MFI'),
('MFI-018','MFI'),
('MFI-019','MFI'),
('MFI-020','MFI'),
('MFI-021','MFI'),
('MFI-022','MFI'),
('MFI-023','MFI'),
('MFI-024','MFI'),
('MFI-025','MFI'),
('MFI-026','MFI'),
('MFI-027','MFI'),
('MPA-001','MPA'),
('MPA-002','MPA'),
('MPA-003','MPA'),
('MPA-004','MPA'),
('MPA-005','MPA'),
('MPA-006','MPA'),
('MPA-007','MPA'),
('MPA-008','MPA'),
('MPA-009','MPA'),
('MPA-010','MPA'),
('MPA-011','MPA'),
('MPA-012','MPA'),
('MPA-013','MPA'),
('MPA-014','MPA'),
('MPA-015','MPA'),
('MPA-016','MPA'),
('MPA-017','MPA'),
('MPA-018','MPA'),
('MPA-019','MPA'),
('MPA-020','MPA'),
('MPA-021','MPA'),
('MPA-022','MPA'),
('QLD-001','ADM'),
('QLD-002','ADM'),
('QLD-003','ADM'),
('QLD-004','ADM'),
('QLD-005','ADM'),
('QLD-006','ADM'),
('QLD-007','ADM'),
('QLD-008','ADM'),
('QLD-009','ADM'),
('QLD-010','ADM'),
('QLD-011','ADM'),
('QLD-012','ADM'),
('QLD-013','ADM'),
('QLD-014','ADM'),
('QLD-015','ADM'),
('QLD-016','ADM'),
('QLD-017','ADM'),
('QLD-018','ADM'),
('QLD-019','ADM'),
('QLD-020','ADM'),
('QLD-021','ADM'),
('QLD-022','ADM'),
('QLD-023','ADM'),
('QLD-024','ADM'),
('QLD-025','ADM'),
('QLD-026','ADM'),
('QLD-027','ADM'),
('SST-001','ADM'),
('SST-002','ADM'),
('SST-003','ADM'),
('SST-004','ADM'),
('SST-005','ADM'),
('SST-006','ADM'),
('SST-007','ADM'),
('SST-008','ADM'),
('SST-009','ADM'),
('SST-010','ADM'),
('SST-011','ADM'),
('SST-012','ADM'),
('SST-013','ADM'),
('SST-014','ADM'),
('SST-015','ADM'),
('SST-016','ADM'),
('SST-017','ADM'),
('SST-018','ADM'),
('SST-019','ADM'),
('SST-020','ADM'),
('SST-021','ADM'),
('MEL-001','ADM'),
('MEL-002','ADM'),
('MEL-003','ADM'),
('MEL-004','ADM'),
('MEL-005','ADM'),
('MEL-006','ADM'),
('MEL-007','ADM'),
('MEL-008','ADM'),
('MEL-009','ADM'),
('MEL-010','ADM'),
('MEL-011','ADM'),
('MEL-012','ADM'),
('MEL-013','ADM'),
('MEL-014','ADM'),
('MEL-015','ADM'),
('MEL-016','ADM'),
('MEL-017','ADM'),
('MEL-018','ADM'),
('MEL-019','ADM'),
('MEL-020','ADM'),
('PCP-001','ADM'),
('PCP-002','ADM'),
('PCP-003','ADM'),
('PCP-004','ADM'),
('PCP-005','ADM'),
('PCP-006','ADM'),
('PCP-007','ADM'),
('PCP-008','ADM'),
('PCP-009','ADM'),
('PCP-010','ADM'),
('MAT-001','ADM'),
('MAT-002','ADM'),
('MAT-003','ADM'),
('MAT-004','ADM'),
('MAT-005','ADM'),
('MAT-006','ADM'),
('MAT-007','ADM'),
('MAT-008','ADM'),
('MAT-009','ADM'),
('DOC-001','ADM'),
('DOC-002','ADM'),
('DOC-003','ADM'),
('DOC-004','ADM'),
('DOC-005','ADM'),
('DOC-006','ADM'),
('DOC-007','ADM'),
('DOC-008','ADM'),
('DOC-009','ADM'),
('DOC-010','ADM'),
('TST-001','ADM'),
('TST-002','ADM'),
('TST-003','ADM'),
('TST-004','ADM'),
('TST-005','ADM'),
('TST-006','ADM'),
('TST-007','ADM'),
('TST-008','ADM'),
('TST-009','ADM'),
('TST-010','ADM'),
('TST-011','ADM'),
('TST-012','ADM'),
('TST-013','ADM'),
('TST-014','ADM'),
('TST-015','ADM'),
('FAB-021-FABRICACAO-M','FAB'),
('FAB-022','FAB'),
('FAB-023','FAB');

delete from public.activity_area_links l
using public.activities a, tmp_v213_activities t
where l.activity_id=a.id and a.code=t.code;

insert into public.activity_area_links(activity_id,area_code)
select a.id,l.area_code
from tmp_v213_activity_links l
join public.activities a on a.code=l.activity_code
on conflict(activity_id,area_code) do nothing;

create temporary table tmp_v213_project_rooms (
  project_code text not null,
  room_code text not null,
  display_name text not null,
  order_index integer not null,
  active boolean not null,
  primary key(project_code,room_code)
) on commit drop;

insert into tmp_v213_project_rooms(
  project_code,room_code,display_name,order_index,active
) values
('AWS','DH','DATAHALL',0,true),
('AWS','SE','SALA ELETRICA',0,true),
('AWS','SALA-SALA-CATCHER','SALA CATCHER',0,true),
('AWS','SALA-SALA-MEDIA','SALA MEDIA',0,true),
('AWS','SALA-SALA-DE-MAQUINAS','SALA DE MAQUINAS',0,true),
('TB11','PRJ-GERAL','Geral do projeto',0,true),
('UFG','SALA-MONOBLOCO','MONOBLOCO',0,true),
('PRODEB','SALA-MONOBLOCO','MONOBLOCO',0,true),
('BARBADOS','SALA-MONOBLOCO','MONOBLOCO',0,true),
('FOR','PRJ-GERAL','Geral do projeto',0,true),
('BOG','PRJ-GERAL','Geral do projeto',0,true),
('CRUSOE','PRJ-GERAL','Geral do projeto',0,true);

create temporary table tmp_v213_project_room_modules (
  project_code text not null,
  room_code text not null,
  module_code text not null,
  display_name text not null,
  order_index integer not null,
  active boolean not null,
  primary key(project_code,room_code,module_code)
) on commit drop;

insert into tmp_v213_project_room_modules(
  project_code,room_code,module_code,display_name,order_index,active
) values
('AWS','DH','MOD1','MOD1',0,true),
('AWS','DH','MOD2','MOD2',1,true),
('AWS','DH','MOD3','MOD3',2,true),
('AWS','DH','MOD4','MOD4',3,true),
('AWS','DH','MOD5','MOD5',4,true),
('AWS','DH','MOD6','MOD6',5,true),
('AWS','DH','MOD7','MOD7',6,true),
('AWS','DH','MOD8','MOD8',7,true),
('AWS','SE','MOD1','MOD1',12,true),
('AWS','SE','MOD2','MOD2',13,true),
('AWS','SE','MOD3','MOD3',14,true),
('AWS','SE','MOD4','MOD4',15,true),
('AWS','SE','MOD5','MOD5',16,true),
('AWS','SE','MOD6','MOD6',0,true),
('AWS','SALA-SALA-CATCHER','MOD1','MOD1',1,true),
('AWS','SALA-SALA-CATCHER','MOD2','MOD2',2,true),
('AWS','SALA-SALA-CATCHER','MOD3','MOD3',3,true),
('AWS','SALA-SALA-CATCHER','MOD4','MOD4',4,true),
('AWS','SALA-SALA-CATCHER','MOD5','MOD5',5,true),
('AWS','SALA-SALA-CATCHER','MOD6','MOD6',6,true),
('AWS','SALA-SALA-MEDIA','MOD1','MOD1',7,true),
('AWS','SALA-SALA-MEDIA','MOD2','MOD2',8,true),
('AWS','SALA-SALA-MEDIA','MOD3','MOD3',9,true),
('AWS','SALA-SALA-MEDIA','MOD4','MOD4',10,true),
('AWS','SALA-SALA-MEDIA','MOD5','MOD5',11,true),
('AWS','SALA-SALA-MEDIA','MOD6','MOD6',12,true),
('AWS','SALA-SALA-DE-MAQUINAS','MOD1','MOD1',13,true),
('AWS','SALA-SALA-DE-MAQUINAS','MOD2','MOD2',14,true),
('AWS','SALA-SALA-DE-MAQUINAS','MOD3','MOD3',15,true),
('AWS','SALA-SALA-DE-MAQUINAS','MOD4','MOD4',16,true),
('AWS','SALA-SALA-DE-MAQUINAS','MOD5','MOD5',0,true),
('AWS','SALA-SALA-DE-MAQUINAS','MOD6','MOD6',1,true),
('AWS','SALA-SALA-DE-MAQUINAS','MOD7','MOD7',2,true),
('AWS','SALA-SALA-DE-MAQUINAS','MOD8','MOD8',3,true),
('TB11','PRJ-GERAL','M04','Módulo 04',4,true),
('TB11','PRJ-GERAL','M05','Módulo 05',5,true),
('TB11','PRJ-GERAL','M06','Módulo 06',6,true),
('TB11','PRJ-GERAL','M07','Módulo 07',7,true),
('TB11','PRJ-GERAL','M08','Módulo 08',8,true),
('TB11','PRJ-GERAL','M09','Módulo 09',9,true),
('TB11','PRJ-GERAL','M10','Módulo 10',10,true),
('TB11','PRJ-GERAL','M11','Módulo 11',11,true),
('TB11','PRJ-GERAL','M12','Módulo 12',12,true),
('TB11','PRJ-GERAL','M13','Módulo 13',13,true),
('TB11','PRJ-GERAL','M14','Módulo 14',14,true),
('TB11','PRJ-GERAL','M15','Módulo 15',15,true),
('TB11','PRJ-GERAL','M16','Módulo 16',16,true),
('UFG','SALA-MONOBLOCO','MOD1','MOD1',16,true),
('PRODEB','SALA-MONOBLOCO','MOD1','MOD1',16,true),
('BARBADOS','SALA-MONOBLOCO','MOD1','MOD1',16,true),
('FOR','PRJ-GERAL','MOD-GERAL','Geral do projeto',0,true),
('FOR','PRJ-GERAL','M01','Módulo 01',1,true),
('FOR','PRJ-GERAL','M02','Módulo 02',2,true),
('FOR','PRJ-GERAL','M03','Módulo 03',3,true),
('FOR','PRJ-GERAL','M04','Módulo 04',4,true),
('FOR','PRJ-GERAL','M05','Módulo 05',5,true),
('FOR','PRJ-GERAL','M06','Módulo 06',6,true),
('FOR','PRJ-GERAL','M07','Módulo 07',7,true),
('FOR','PRJ-GERAL','M08','Módulo 08',8,true),
('FOR','PRJ-GERAL','M09','Módulo 09',9,true),
('FOR','PRJ-GERAL','M10','Módulo 10',10,true),
('FOR','PRJ-GERAL','M11','Módulo 11',11,true),
('FOR','PRJ-GERAL','M12','Módulo 12',12,true),
('FOR','PRJ-GERAL','M13','Módulo 13',13,true),
('FOR','PRJ-GERAL','M14','Módulo 14',14,true),
('FOR','PRJ-GERAL','M15','Módulo 15',15,true),
('FOR','PRJ-GERAL','M16','Módulo 16',16,true),
('BOG','PRJ-GERAL','MOD-GERAL','Geral do projeto',0,true),
('BOG','PRJ-GERAL','M01','Módulo 01',1,true),
('BOG','PRJ-GERAL','M02','Módulo 02',2,true),
('BOG','PRJ-GERAL','M03','Módulo 03',3,true),
('BOG','PRJ-GERAL','M04','Módulo 04',4,true),
('BOG','PRJ-GERAL','M05','Módulo 05',5,true),
('BOG','PRJ-GERAL','M06','Módulo 06',6,true),
('BOG','PRJ-GERAL','M07','Módulo 07',7,true),
('BOG','PRJ-GERAL','M08','Módulo 08',8,true),
('BOG','PRJ-GERAL','M09','Módulo 09',9,true),
('BOG','PRJ-GERAL','M10','Módulo 10',10,true),
('BOG','PRJ-GERAL','M11','Módulo 11',11,true),
('BOG','PRJ-GERAL','M12','Módulo 12',12,true),
('BOG','PRJ-GERAL','M13','Módulo 13',13,true),
('BOG','PRJ-GERAL','M14','Módulo 14',14,true),
('BOG','PRJ-GERAL','M15','Módulo 15',15,true),
('BOG','PRJ-GERAL','M16','Módulo 16',16,true),
('CRUSOE','PRJ-GERAL','MOD-GERAL','Geral do projeto',0,true),
('CRUSOE','PRJ-GERAL','M01','Módulo 01',1,true),
('CRUSOE','PRJ-GERAL','M02','Módulo 02',2,true),
('CRUSOE','PRJ-GERAL','M03','Módulo 03',3,true),
('CRUSOE','PRJ-GERAL','M04','Módulo 04',4,true),
('CRUSOE','PRJ-GERAL','M05','Módulo 05',5,true),
('CRUSOE','PRJ-GERAL','M06','Módulo 06',6,true),
('CRUSOE','PRJ-GERAL','M07','Módulo 07',7,true),
('CRUSOE','PRJ-GERAL','M08','Módulo 08',8,true),
('CRUSOE','PRJ-GERAL','M09','Módulo 09',9,true),
('CRUSOE','PRJ-GERAL','M10','Módulo 10',10,true),
('CRUSOE','PRJ-GERAL','M11','Módulo 11',11,true),
('CRUSOE','PRJ-GERAL','M12','Módulo 12',12,true),
('CRUSOE','PRJ-GERAL','M13','Módulo 13',13,true),
('CRUSOE','PRJ-GERAL','M14','Módulo 14',14,true),
('CRUSOE','PRJ-GERAL','M15','Módulo 15',15,true),
('CRUSOE','PRJ-GERAL','M16','Módulo 16',16,true);

update public.project_rooms pr
set active=false
where pr.project_id in (
  select p.id
  from public.projects p
  join (select distinct project_code from tmp_v213_project_rooms) t
    on t.project_code=p.code
);

insert into public.project_rooms(
  project_id,room_id,display_name,order_index,active
)
select p.id,r.id,t.display_name,t.order_index,t.active
from tmp_v213_project_rooms t
join public.projects p on p.code=t.project_code
join public.rooms r on r.code=t.room_code
on conflict(project_id,room_id) do update set
  display_name=excluded.display_name,
  order_index=excluded.order_index,
  active=excluded.active;

update public.project_room_modules prm
set active=false
where prm.project_id in (
  select p.id
  from public.projects p
  join (select distinct project_code from tmp_v213_project_room_modules) t
    on t.project_code=p.code
);

insert into public.project_room_modules(
  project_id,room_id,module_id,display_name,order_index,active
)
select p.id,r.id,m.id,t.display_name,t.order_index,t.active
from tmp_v213_project_room_modules t
join public.projects p on p.code=t.project_code
join public.rooms r on r.code=t.room_code
join public.modules m on m.code=t.module_code
on conflict(project_id,room_id,module_id) do update set
  display_name=excluded.display_name,
  order_index=excluded.order_index,
  active=excluded.active;

-- Mantém a tabela antiga project_modules sincronizada para compatibilidade.
insert into public.project_modules(
  project_id,module_id,display_name,order_index,active
)
select
  p.id,
  m.id,
  max(t.display_name),
  min(t.order_index),
  bool_or(t.active)
from tmp_v213_project_room_modules t
join public.projects p on p.code=t.project_code
join public.modules m on m.code=t.module_code
group by p.id,m.id
on conflict(project_id,module_id) do update set
  display_name=excluded.display_name,
  order_index=excluded.order_index,
  active=excluded.active;


create or replace function public.aponta_validate_entry_structure_v213()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.area_code='FAB' then
    if new.sector_id is null then
      raise exception 'Selecione o setor de fabricação.';
    end if;
    new.room_id:=null;
    new.module_id:=null;
    new.panel_type_id:=null;

  elsif new.area_code='MES' then
    if new.room_id is null then
      raise exception 'Selecione a sala do projeto.';
    end if;
    if new.module_id is null then
      raise exception 'Selecione o módulo da sala.';
    end if;
    if not exists (
      select 1
      from public.project_room_modules prm
      where prm.project_id=new.project_id
        and prm.room_id=new.room_id
        and prm.module_id=new.module_id
        and prm.active=true
    ) then
      raise exception 'O módulo selecionado não está vinculado a esta sala do projeto.';
    end if;
    new.sector_id:=null;
    new.panel_type_id:=null;

  elsif new.area_code='MPA' then
    if new.panel_type_id is null then
      raise exception 'Selecione o tipo de painel.';
    end if;
    new.sector_id:=null;
    new.room_id:=null;
    new.module_id:=null;

  elsif new.area_code='MFI' then
    if new.room_id is null then
      raise exception 'Selecione a sala do projeto.';
    end if;
    if not exists (
      select 1
      from public.project_rooms pr
      where pr.project_id=new.project_id
        and pr.room_id=new.room_id
        and pr.active=true
    ) then
      raise exception 'A sala selecionada não está vinculada a este projeto.';
    end if;
    new.sector_id:=null;
    new.module_id:=null;
    new.panel_type_id:=null;

  elsif new.area_code='ADM' then
    new.sector_id:=null;
    new.room_id:=null;
    new.module_id:=null;
    new.panel_type_id:=null;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_validate_entry_structure_v213 on public.time_entries;
create trigger trg_validate_entry_structure_v213
before insert or update of project_id,area_code,sector_id,room_id,module_id,panel_type_id
on public.time_entries
for each row execute function public.aponta_validate_entry_structure_v213();

notify pgrst, 'reload schema';

-- RESUMO DA PLANILHA APLICADA:
-- Projetos: 9
-- Áreas: 5
-- Setores: 19
-- Tipos de painel: 13
-- Salas do catálogo: 80
-- Vínculos Projeto × Sala: 12
-- Vínculos Projeto × Sala × Módulo: 101
-- Atividades: 309
