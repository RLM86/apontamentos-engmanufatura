-- APONTA P3 v2.18.7
-- CONSULTA SEGURA DOS APONTAMENTOS PARA PAINEL, HISTÓRICO E RELATÓRIOS
-- Execute todo este arquivo no SQL Editor do Supabase.

begin;

create or replace function public.aponta_select_time_entries_v2187(
  p_start_date date,
  p_end_date date,
  p_user_id uuid default null,
  p_project_id uuid default null
)
returns setof public.time_entries
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_current_user uuid;
  v_role text;
  v_active boolean;
begin
  v_current_user := auth.uid();

  if v_current_user is null then
    raise exception 'Usuário não autenticado.';
  end if;

  if p_start_date is null or p_end_date is null then
    raise exception 'Informe o período inicial e final.';
  end if;

  if p_end_date < p_start_date then
    raise exception 'A data final não pode ser menor que a data inicial.';
  end if;

  select
    lower(trim(coalesce(p.role, ''))),
    coalesce(p.active, false)
  into
    v_role,
    v_active
  from public.profiles p
  where p.id = v_current_user;

  if not found or not v_active then
    raise exception 'Perfil inexistente ou inativo.';
  end if;

  -- Administrador e Gestor visualizam todos os colaboradores.
  if v_role in ('administrador', 'gestor') then
    return query
    select te.*
    from public.time_entries te
    where te.entry_date >= p_start_date
      and te.entry_date <= p_end_date
      and (
        p_user_id is null
        or te.user_id = p_user_id
      )
      and (
        p_project_id is null
        or te.project_id = p_project_id
      )
    order by
      te.entry_date desc,
      te.created_at desc,
      te.id desc;

    return;
  end if;

  -- Colaborador visualiza somente os próprios registros.
  return query
  select te.*
  from public.time_entries te
  where te.user_id = v_current_user
    and te.entry_date >= p_start_date
    and te.entry_date <= p_end_date
    and (
      p_user_id is null
      or p_user_id = v_current_user
    )
    and (
      p_project_id is null
      or te.project_id = p_project_id
    )
  order by
    te.entry_date desc,
    te.created_at desc,
    te.id desc;
end;
$$;

revoke all on function public.aponta_select_time_entries_v2187(
  date,
  date,
  uuid,
  uuid
) from public;

grant execute on function public.aponta_select_time_entries_v2187(
  date,
  date,
  uuid,
  uuid
) to authenticated;

commit;

-- ============================================================
-- CONFERÊNCIA
-- ============================================================

-- A função deve aparecer abaixo:
select
  routine_name,
  security_type
from information_schema.routines
where routine_schema = 'public'
  and routine_name = 'aponta_select_time_entries_v2187';

-- Conferência administrativa no próprio SQL Editor:
-- O SQL Editor não possui a sessão do usuário do aplicativo,
-- portanto a função deve ser testada pelo app depois da publicação.

-- Conferir diretamente os lançamentos de agosto:
select
  te.entry_date,
  p.full_name as colaborador,
  pr.name as projeto,
  te.area_code,
  te.hours,
  te.status
from public.time_entries te
left join public.profiles p
  on p.id = te.user_id
left join public.projects pr
  on pr.id = te.project_id
where te.entry_date >= date '2026-08-01'
  and te.entry_date <= date '2026-08-31'
order by te.entry_date desc, p.full_name;
