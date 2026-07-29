-- APONTA P3 v2.18.2
-- CADASTRO, EDIÇÃO, INATIVAÇÃO E EXCLUSÃO SEGURA DE ÁREAS
-- Execute todo este arquivo no SQL Editor do Supabase.

begin;

alter table public.work_areas
  add column if not exists detail_type text not null default 'none';

alter table public.work_areas
  add column if not exists order_index integer not null default 0;

alter table public.work_areas
  add column if not exists active boolean not null default true;

do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conrelid = 'public.work_areas'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%detail_type%'
  ) then
    null;
  else
    alter table public.work_areas
      add constraint work_areas_detail_type_check_v2182
      check (
        detail_type in (
          'sector',
          'module',
          'panel_type',
          'room',
          'none'
        )
      );
  end if;
end
$$;


create or replace function public.aponta_save_work_area_v2182(
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


create or replace function public.aponta_delete_work_area_v2182(
  p_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_code text;
  v_name text;
begin
  select lower(trim(coalesce(role, '')))
    into v_role
  from public.profiles
  where id = auth.uid();

  if coalesce(v_role, '') <> 'administrador' then
    raise exception 'Somente o Administrador pode excluir áreas.';
  end if;

  v_code := upper(trim(coalesce(p_code, '')));

  select name
    into v_name
  from public.work_areas
  where code = v_code
  for update;

  if v_name is null then
    raise exception 'Área não encontrada.';
  end if;

  if v_code in ('FAB','MES','MPA','MFI','ADM') then
    raise exception
      'A área padrão % não pode ser excluída. Utilize Inativar.',
      v_code;
  end if;

  if exists (
    select 1
    from public.time_entries
    where area_code = v_code
  ) then
    raise exception
      'A área possui apontamentos e deve ser apenas inativada.';
  end if;

  if exists (
    select 1
    from public.activity_area_links
    where area_code = v_code
  ) then
    raise exception
      'A área está vinculada a atividades. Remova os vínculos ou inative a área.';
  end if;

  delete from public.work_areas
  where code = v_code;

  return jsonb_build_object(
    'deleted', true,
    'code', v_code,
    'name', v_name
  );
end;
$$;

revoke all on function public.aponta_delete_work_area_v2182(text)
from public;

grant execute on function public.aponta_delete_work_area_v2182(text)
to authenticated;

commit;

-- Conferência
select
  code,
  name,
  detail_type,
  order_index,
  active
from public.work_areas
order by order_index, name;

select routine_name
from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
    'aponta_save_work_area_v2182',
    'aponta_delete_work_area_v2182'
  )
order by routine_name;
