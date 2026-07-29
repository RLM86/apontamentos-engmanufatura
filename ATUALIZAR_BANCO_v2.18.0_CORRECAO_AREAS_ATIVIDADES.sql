-- APONTA P3 v2.18.0
-- CORREÇÃO DEFINITIVA DO SALVAMENTO DAS ÁREAS DAS ATIVIDADES
-- Execute todo este arquivo no SQL Editor do Supabase.

begin;

create or replace function public.aponta_save_activity_v2180(
  p_activity_id uuid,
  p_code text,
  p_name text,
  p_discipline_name text,
  p_nature text,
  p_usage_description text,
  p_observation_requirement text,
  p_active boolean,
  p_areas text[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_id uuid;
  v_created boolean := false;
  v_code text;
  v_name text;
  v_observation text;
  v_areas text[];
  v_invalid_area text;
  v_sector_principal text;
  v_saved_areas text[];
begin
  select lower(trim(coalesce(role, '')))
    into v_role
  from public.profiles
  where id = auth.uid();

  if coalesce(v_role, '') <> 'administrador' then
    raise exception 'Somente o Administrador pode cadastrar ou editar atividades.';
  end if;

  v_code := nullif(
    upper(regexp_replace(trim(coalesce(p_code, '')), '^EM-', '', 'i')),
    ''
  );
  v_name := trim(coalesce(p_name, ''));

  select array_agg(area_code order by area_code)
    into v_areas
  from (
    select distinct upper(trim(u.area_code)) as area_code
    from unnest(coalesce(p_areas, array[]::text[])) as u(area_code)
    where trim(coalesce(u.area_code, '')) <> ''
  ) normalized;

  if v_name = '' then
    raise exception 'Informe o nome da atividade.';
  end if;

  if coalesce(array_length(v_areas, 1), 0) = 0 then
    raise exception 'Selecione pelo menos uma área para a atividade.';
  end if;

  select u.area_code
    into v_invalid_area
  from unnest(v_areas) as u(area_code)
  where not exists (
    select 1
    from public.work_areas wa
    where wa.code = u.area_code
  )
  limit 1;

  if v_invalid_area is not null then
    raise exception 'Área inválida: %.', v_invalid_area;
  end if;

  v_observation := case
    when lower(trim(coalesce(p_observation_requirement, ''))) in (
      'obrigatória','obrigatoria','obrigatório','obrigatorio','sim','s'
    ) then 'Obrigatória'
    else 'Opcional'
  end;

  if exists (
    select 1
    from public.activities a
    where v_code is not null
      and upper(coalesce(a.code, '')) = v_code
      and a.id is distinct from p_activity_id
  ) then
    raise exception 'O código % já pertence a outra atividade.', v_code;
  end if;

  if exists (
    select 1
    from public.activities a
    where lower(trim(a.name)) = lower(v_name)
      and a.id is distinct from p_activity_id
  ) then
    raise exception 'O nome da atividade já está cadastrado.';
  end if;

  select string_agg(wa.name, ' / ' order by wa.order_index, wa.name)
    into v_sector_principal
  from public.work_areas wa
  where wa.code = any(v_areas);

  if p_activity_id is null then
    insert into public.activities(
      code,name,activity_type,frequency,responsible_name,backup_name,
      discipline_code,discipline_name,sector_principal,nature,
      usage_description,observation_requirement,active,created_by
    ) values(
      v_code,v_name,'Demanda','','','',
      coalesce(split_part(v_code, '-', 1), ''),
      trim(coalesce(p_discipline_name, '')),
      coalesce(v_sector_principal, ''),
      trim(coalesce(p_nature, '')),
      trim(coalesce(p_usage_description, '')),
      v_observation,coalesce(p_active,true),auth.uid()
    ) returning id into v_id;
    v_created := true;
  else
    select id into v_id
    from public.activities
    where id = p_activity_id
    for update;

    if v_id is null then
      raise exception 'Atividade não encontrada.';
    end if;

    update public.activities
    set code=v_code,
        name=v_name,
        discipline_code=coalesce(split_part(v_code, '-', 1), ''),
        discipline_name=trim(coalesce(p_discipline_name, '')),
        sector_principal=coalesce(v_sector_principal, ''),
        nature=trim(coalesce(p_nature, '')),
        usage_description=trim(coalesce(p_usage_description, '')),
        observation_requirement=v_observation,
        active=coalesce(p_active,true)
    where id=v_id;
  end if;

  delete from public.activity_area_links
  where activity_id = v_id;

  insert into public.activity_area_links(activity_id, area_code)
  select v_id, u.area_code
  from unnest(v_areas) as u(area_code)
  join public.work_areas wa on wa.code = u.area_code
  on conflict do nothing;

  select array_agg(l.area_code order by l.area_code)
    into v_saved_areas
  from public.activity_area_links l
  where l.activity_id = v_id;

  if coalesce(array_length(v_saved_areas,1),0) <> coalesce(array_length(v_areas,1),0) then
    raise exception 'Nem todas as áreas selecionadas foram gravadas.';
  end if;

  return jsonb_build_object(
    'id',v_id,
    'created',v_created,
    'observation_requirement',v_observation,
    'areas',to_jsonb(coalesce(v_saved_areas,array[]::text[]))
  );
end;
$$;

revoke all on function public.aponta_save_activity_v2180(
  uuid,text,text,text,text,text,text,boolean,text[]
) from public;
grant execute on function public.aponta_save_activity_v2180(
  uuid,text,text,text,text,text,text,boolean,text[]
) to authenticated;

create or replace function public.aponta_import_activities_v2180(p_rows jsonb)
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
  v_observation text;
  v_active boolean;
  v_areas_json jsonb;
  v_areas text[];
  v_code_id uuid;
  v_name_id uuid;
  v_result jsonb;
  v_created integer := 0;
  v_updated integer := 0;
begin
  select lower(trim(coalesce(role, ''))) into v_role
  from public.profiles where id = auth.uid();

  if coalesce(v_role,'') <> 'administrador' then
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
      v_row_number := coalesce(nullif(v_row->>'row_number','')::integer,v_item.ordinality::integer+1);
      v_id_text := nullif(trim(coalesce(v_row->>'id','')),'');

      if v_id_text is not null and v_id_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then v_activity_id := v_id_text::uuid;
      else v_activity_id := null;
      end if;

      v_code := nullif(upper(regexp_replace(trim(coalesce(v_row->>'code','')),'^EM-','','i')),'');
      v_name := trim(coalesce(v_row->>'name',''));
      v_discipline_name := trim(coalesce(v_row->>'discipline_name',''));
      v_nature := trim(coalesce(v_row->>'nature',''));
      v_usage_description := trim(coalesce(v_row->>'usage_description',''));
      v_observation := trim(coalesce(v_row->>'observation_requirement','Opcional'));
      v_active := coalesce((v_row->>'active')::boolean,true);
      v_areas_json := coalesce(v_row->'areas','[]'::jsonb);

      if v_name='' then raise exception 'Linha %: informe o nome da atividade.',v_row_number; end if;
      if jsonb_typeof(v_areas_json)<>'array' or jsonb_array_length(v_areas_json)=0 then
        raise exception 'Linha %: informe pelo menos uma área aplicável.',v_row_number;
      end if;

      select array_agg(value) into v_areas from jsonb_array_elements_text(v_areas_json);
      select a.id into v_code_id from public.activities a where v_code is not null and upper(coalesce(a.code,''))=v_code limit 1;
      select a.id into v_name_id from public.activities a where lower(trim(a.name))=lower(v_name) limit 1;

      if v_activity_id is not null and not exists(select 1 from public.activities where id=v_activity_id) then
        v_activity_id := null;
      end if;

      if v_activity_id is null then
        if v_code_id is not null and v_name_id is not null and v_code_id<>v_name_id then
          raise exception 'Linha %: o código e o nome pertencem a atividades diferentes.',v_row_number;
        end if;
        v_activity_id := coalesce(v_code_id,v_name_id);
      end if;

      v_result := public.aponta_save_activity_v2180(
        v_activity_id,v_code,v_name,v_discipline_name,v_nature,
        v_usage_description,v_observation,v_active,v_areas
      );

      if coalesce((v_result->>'created')::boolean,false) then
        v_created:=v_created+1;
      else
        v_updated:=v_updated+1;
      end if;
    exception when others then
      if position('Linha ' in sqlerrm)=1 then raise; end if;
      raise exception 'Linha %: %',coalesce(v_row_number,v_item.ordinality::integer+1),sqlerrm;
    end;
  end loop;

  return jsonb_build_object('received',jsonb_array_length(p_rows),'created',v_created,'updated',v_updated);
end;
$$;

revoke all on function public.aponta_import_activities_v2180(jsonb) from public;
grant execute on function public.aponta_import_activities_v2180(jsonb) to authenticated;

commit;

select routine_name
from information_schema.routines
where routine_schema='public'
  and routine_name in ('aponta_save_activity_v2180','aponta_import_activities_v2180')
order by routine_name;
