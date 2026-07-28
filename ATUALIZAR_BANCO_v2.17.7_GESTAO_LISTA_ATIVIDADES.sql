-- APONTA P3 v2.17.7
-- EXCLUSÃO EM MASSA E IMPORTAÇÃO DA LISTA DE ATIVIDADES
-- Execute todo este arquivo no SQL Editor do Supabase.

begin;

create or replace function public.aponta_bulk_delete_activities_v2177(
  p_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_deleted integer := 0;
  v_blocked jsonb := '[]'::jsonb;
begin
  select lower(trim(coalesce(role, '')))
    into v_role
  from public.profiles
  where id = auth.uid();

  if coalesce(v_role, '') <> 'administrador' then
    raise exception 'Somente o Administrador pode excluir atividades em massa.';
  end if;

  if coalesce(array_length(p_ids, 1), 0) = 0 then
    return jsonb_build_object(
      'requested', 0,
      'deleted', 0,
      'blocked', '[]'::jsonb
    );
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', a.id,
        'code', a.code,
        'name', a.name
      )
      order by a.name
    ),
    '[]'::jsonb
  )
  into v_blocked
  from public.activities a
  where a.id = any(p_ids)
    and exists (
      select 1
      from public.time_entries te
      where te.activity_id = a.id
    );

  delete from public.activities a
  where a.id = any(p_ids)
    and not exists (
      select 1
      from public.time_entries te
      where te.activity_id = a.id
    );

  get diagnostics v_deleted = row_count;

  return jsonb_build_object(
    'requested', coalesce(array_length(p_ids, 1), 0),
    'deleted', v_deleted,
    'blocked', v_blocked
  );
end;
$$;

revoke all on function public.aponta_bulk_delete_activities_v2177(uuid[])
from public;

grant execute on function public.aponta_bulk_delete_activities_v2177(uuid[])
to authenticated;


create or replace function public.aponta_import_activities_v2177(
  p_rows jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_item record;
  v_row jsonb;
  v_row_number integer;
  v_id_text text;
  v_activity_id uuid;
  v_code text;
  v_name text;
  v_discipline_name text;
  v_nature text;
  v_usage_description text;
  v_active boolean;
  v_areas jsonb;
  v_area text;
  v_sector_principal text;
  v_code_id uuid;
  v_name_id uuid;
  v_created integer := 0;
  v_updated integer := 0;
begin
  select lower(trim(coalesce(role, '')))
    into v_role
  from public.profiles
  where id = auth.uid();

  if coalesce(v_role, '') <> 'administrador' then
    raise exception 'Somente o Administrador pode importar a lista de atividades.';
  end if;

  if jsonb_typeof(p_rows) <> 'array' then
    raise exception 'O arquivo de atividades não possui uma lista válida.';
  end if;

  for v_item in
    select value, ordinality
    from jsonb_array_elements(p_rows) with ordinality
  loop
    begin
      v_row := v_item.value;
      v_row_number := coalesce(
        nullif(v_row->>'row_number', '')::integer,
        v_item.ordinality::integer + 1
      );

      v_id_text := nullif(trim(coalesce(v_row->>'id', '')), '');

      if v_id_text is not null
         and v_id_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then
        v_activity_id := v_id_text::uuid;
      else
        v_activity_id := null;
      end if;

      v_code := nullif(
        upper(
          regexp_replace(
            trim(coalesce(v_row->>'code', '')),
            '^EM-',
            '',
            'i'
          )
        ),
        ''
      );

      v_name := trim(coalesce(v_row->>'name', ''));
      v_discipline_name := trim(coalesce(v_row->>'discipline_name', ''));
      v_nature := trim(coalesce(v_row->>'nature', ''));
      v_usage_description := trim(coalesce(v_row->>'usage_description', ''));
      v_active := coalesce((v_row->>'active')::boolean, true);
      v_areas := coalesce(v_row->'areas', '[]'::jsonb);

      if v_name = '' then
        raise exception 'Linha %: informe o nome da atividade.', v_row_number;
      end if;

      if jsonb_typeof(v_areas) <> 'array'
         or jsonb_array_length(v_areas) = 0
      then
        raise exception 'Linha %: informe pelo menos uma área aplicável.', v_row_number;
      end if;

      for v_area in
        select value
        from jsonb_array_elements_text(v_areas)
      loop
        if not exists (
          select 1
          from public.work_areas wa
          where wa.code = v_area
        ) then
          raise exception 'Linha %: área inválida: %.', v_row_number, v_area;
        end if;
      end loop;

      select a.id
        into v_code_id
      from public.activities a
      where v_code is not null
        and upper(coalesce(a.code, '')) = v_code
      limit 1;

      select a.id
        into v_name_id
      from public.activities a
      where lower(trim(a.name)) = lower(v_name)
      limit 1;

      if v_activity_id is not null
         and not exists (
           select 1 from public.activities where id = v_activity_id
         )
      then
        v_activity_id := null;
      end if;

      if v_activity_id is null then
        if v_code_id is not null
           and v_name_id is not null
           and v_code_id <> v_name_id
        then
          raise exception
            'Linha %: o código e o nome pertencem a atividades diferentes.',
            v_row_number;
        end if;

        v_activity_id := coalesce(v_code_id, v_name_id);
      end if;

      select string_agg(wa.name, ' / ' order by wa.order_index, wa.name)
        into v_sector_principal
      from public.work_areas wa
      where wa.code in (
        select value
        from jsonb_array_elements_text(v_areas)
      );

      if v_activity_id is null then
        insert into public.activities(
          code,
          name,
          activity_type,
          frequency,
          responsible_name,
          backup_name,
          discipline_code,
          discipline_name,
          sector_principal,
          nature,
          usage_description,
          observation_requirement,
          active,
          created_by
        )
        values(
          v_code,
          v_name,
          'Demanda',
          '',
          '',
          '',
          coalesce(split_part(v_code, '-', 1), ''),
          v_discipline_name,
          coalesce(v_sector_principal, ''),
          v_nature,
          v_usage_description,
          'Opcional',
          v_active,
          auth.uid()
        )
        returning id into v_activity_id;

        v_created := v_created + 1;
      else
        update public.activities
        set
          code = v_code,
          name = v_name,
          discipline_code = coalesce(split_part(v_code, '-', 1), ''),
          discipline_name = v_discipline_name,
          sector_principal = coalesce(v_sector_principal, ''),
          nature = v_nature,
          usage_description = v_usage_description,
          observation_requirement = 'Opcional',
          active = v_active
        where id = v_activity_id;

        v_updated := v_updated + 1;
      end if;

      delete from public.activity_area_links
      where activity_id = v_activity_id;

      insert into public.activity_area_links(activity_id, area_code)
      select
        v_activity_id,
        value
      from jsonb_array_elements_text(v_areas)
      on conflict do nothing;

    exception
      when unique_violation then
        raise exception
          'Linha %: código ou nome de atividade duplicado.',
          coalesce(v_row_number, v_item.ordinality::integer + 1);
      when others then
        if position('Linha ' in sqlerrm) = 1 then
          raise;
        end if;

        raise exception
          'Linha %: %',
          coalesce(v_row_number, v_item.ordinality::integer + 1),
          sqlerrm;
    end;
  end loop;

  return jsonb_build_object(
    'received', jsonb_array_length(p_rows),
    'created', v_created,
    'updated', v_updated
  );
end;
$$;

revoke all on function public.aponta_import_activities_v2177(jsonb)
from public;

grant execute on function public.aponta_import_activities_v2177(jsonb)
to authenticated;

commit;

-- Conferência
select routine_name
from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
    'aponta_bulk_delete_activities_v2177',
    'aponta_import_activities_v2177'
  )
order by routine_name;
