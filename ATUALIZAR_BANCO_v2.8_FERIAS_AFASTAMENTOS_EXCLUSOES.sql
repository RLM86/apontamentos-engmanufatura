-- APONTA P3 MODULAR v2.8
-- Férias, afastamentos individuais e exclusões seguras.
-- Para atualizar uma instalação v2.7, execute este arquivo no SQL Editor do Supabase.

begin;

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

commit;

select 'Aponta P3 v2.8 instalado' as resultado;
