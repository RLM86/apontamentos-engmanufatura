-- APONTA P3 MODULAR v2.10
-- Aprovação de férias e afastamentos.
-- Após a aprovação, o colaborador não pode editar nem excluir.
-- Gestores e Administradores continuam podendo alterar ou excluir.

begin;

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

commit;

select 'Aponta P3 v2.10 instalado: aprovação de férias e afastamentos ativa.' as resultado;
