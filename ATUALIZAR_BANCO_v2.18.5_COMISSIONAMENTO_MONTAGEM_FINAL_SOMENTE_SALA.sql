-- APONTA P3 v2.18.5
-- COMISSIONAMENTO E MONTAGEM FINAL UTILIZAM SOMENTE SALA
-- Execute todo este arquivo no SQL Editor do Supabase.

begin;

-- ============================================================
-- 1. REGRA DE BANCO PARA IMPEDIR O RETORNO AO FLUXO DE MÓDULOS
-- ============================================================

create or replace function public.aponta_enforce_room_only_work_areas_v2185()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if upper(trim(coalesce(new.code, ''))) in ('COM','MFI')
     or lower(trim(coalesce(new.name, ''))) in (
       'comissionamento',
       'montagem final'
     )
  then
    new.detail_type := 'room';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_room_only_work_areas_v2185
on public.work_areas;

create trigger trg_enforce_room_only_work_areas_v2185
before insert or update of
  code,
  name,
  detail_type
on public.work_areas
for each row
execute function public.aponta_enforce_room_only_work_areas_v2185();


-- ============================================================
-- 2. CORRIGIR AS ÁREAS JÁ CADASTRADAS
-- ============================================================

update public.work_areas
set detail_type = 'room'
where upper(trim(coalesce(code, ''))) in ('COM','MFI')
   or lower(trim(coalesce(name, ''))) in (
     'comissionamento',
     'montagem final'
   );


-- ============================================================
-- 3. FUNÇÃO ADMINISTRATIVA ATUALIZADA
-- ============================================================

create or replace function public.aponta_save_work_area_v2185(
  p_original_code text,
  p_code text,
  p_name text,
  p_detail_type text,
  p_order_index integer,
  p_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_original_code text;
  v_code text;
  v_name text;
  v_detail_type text;
  v_created boolean := false;
begin
  select lower(trim(coalesce(role, '')))
    into v_role
  from public.profiles
  where id = auth.uid();

  if coalesce(v_role, '') <> 'administrador' then
    raise exception 'Somente o Administrador pode cadastrar ou editar áreas.';
  end if;

  v_original_code := nullif(
    upper(trim(coalesce(p_original_code, ''))),
    ''
  );

  v_code := upper(
    regexp_replace(
      trim(coalesce(p_code, '')),
      '[^A-Za-z0-9_-]+',
      '-',
      'g'
    )
  );

  v_code := trim(both '-' from v_code);
  v_name := trim(coalesce(p_name, ''));
  v_detail_type := lower(trim(coalesce(p_detail_type, 'none')));

  if v_code = '' then
    raise exception 'Informe um código válido para a área.';
  end if;

  if length(v_code) > 12 then
    raise exception 'O código da área deve ter no máximo 12 caracteres.';
  end if;

  if v_name = '' then
    raise exception 'Informe o nome da área.';
  end if;

  -- Regra obrigatória solicitada:
  if v_code in ('COM','MFI')
     or lower(v_name) in ('comissionamento','montagem final')
  then
    v_detail_type := 'room';
  end if;

  if v_detail_type not in (
    'sector',
    'module',
    'panel_type',
    'room',
    'none'
  ) then
    raise exception 'Fluxo da área inválido.';
  end if;

  if v_original_code is null then
    if exists (
      select 1
      from public.work_areas
      where code = v_code
    ) then
      raise exception 'O código % já está cadastrado.', v_code;
    end if;

    if exists (
      select 1
      from public.work_areas
      where lower(trim(name)) = lower(v_name)
    ) then
      raise exception 'O nome da área já está cadastrado.';
    end if;

    insert into public.work_areas(
      code,
      name,
      detail_type,
      order_index,
      active
    )
    values(
      v_code,
      v_name,
      v_detail_type,
      greatest(coalesce(p_order_index, 0), 0),
      coalesce(p_active, true)
    );

    v_created := true;
  else
    if v_original_code <> v_code then
      raise exception
        'O código de uma área existente não pode ser alterado.';
    end if;

    if not exists (
      select 1
      from public.work_areas
      where code = v_original_code
    ) then
      raise exception 'Área não encontrada.';
    end if;

    if exists (
      select 1
      from public.work_areas
      where lower(trim(name)) = lower(v_name)
        and code <> v_original_code
    ) then
      raise exception 'O nome da área já está cadastrado.';
    end if;

    update public.work_areas
    set
      name = v_name,
      detail_type = v_detail_type,
      order_index = greatest(coalesce(p_order_index, 0), 0),
      active = coalesce(p_active, true)
    where code = v_original_code;
  end if;

  return jsonb_build_object(
    'code', v_code,
    'name', v_name,
    'detail_type', v_detail_type,
    'order_index', greatest(coalesce(p_order_index, 0), 0),
    'active', coalesce(p_active, true),
    'created', v_created
  );
end;
$$;

revoke all on function public.aponta_save_work_area_v2185(
  text,
  text,
  text,
  text,
  integer,
  boolean
) from public;

grant execute on function public.aponta_save_work_area_v2185(
  text,
  text,
  text,
  text,
  integer,
  boolean
) to authenticated;


-- Compatibilidade com versões antigas ainda armazenadas no cache.
create or replace function public.aponta_save_work_area_v2182(
  p_original_code text,
  p_code text,
  p_name text,
  p_detail_type text,
  p_order_index integer,
  p_active boolean
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.aponta_save_work_area_v2185(
    p_original_code,
    p_code,
    p_name,
    p_detail_type,
    p_order_index,
    p_active
  );
$$;

revoke all on function public.aponta_save_work_area_v2182(
  text,
  text,
  text,
  text,
  integer,
  boolean
) from public;

grant execute on function public.aponta_save_work_area_v2182(
  text,
  text,
  text,
  text,
  integer,
  boolean
) to authenticated;

commit;


-- ============================================================
-- CONFERÊNCIA
-- ============================================================

select
  code,
  name,
  detail_type,
  case
    when detail_type = 'room'
      then 'Projeto > Área > Sala > Atividade'
    else detail_type
  end as fluxo_apontamento
from public.work_areas
where upper(trim(coalesce(code, ''))) in ('COM','MFI')
   or lower(trim(coalesce(name, ''))) in (
     'comissionamento',
     'montagem final'
   )
order by code;

select
  routine_name
from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
    'aponta_save_work_area_v2185',
    'aponta_enforce_room_only_work_areas_v2185'
  )
order by routine_name;
