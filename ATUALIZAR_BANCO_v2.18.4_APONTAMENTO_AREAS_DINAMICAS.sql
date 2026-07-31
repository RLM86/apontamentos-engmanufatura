-- APONTA P3 v2.18.4
-- LIBERA ÁREAS CADASTRADAS DINAMICAMENTE NOS APONTAMENTOS
-- Execute todo este arquivo no SQL Editor do Supabase.

begin;

create or replace function public.aponta_validate_entry_dynamic_v2184()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_detail_type text;
  v_room_id uuid;
  v_legacy_module_id uuid;
  v_lower boolean;
  v_upper boolean;
  v_is_monoblock boolean := false;
begin
  if new.area_code is null then
    return new;
  end if;

  select wa.detail_type
    into v_detail_type
  from public.work_areas wa
  where wa.code = new.area_code;

  if not found then
    raise exception 'Área não cadastrada: %.', new.area_code;
  end if;

  if not exists (
    select 1
    from public.activity_area_links l
    where l.activity_id = new.activity_id
      and l.area_code = new.area_code
  ) then
    raise exception 'A atividade selecionada não pertence à área informada.';
  end if;

  if v_detail_type = 'sector' then
    if new.sector_id is null then
      raise exception 'Selecione o setor para a área %.', new.area_code;
    end if;

    new.room_id := null;
    new.module_id := null;
    new.panel_type_id := null;
    new.project_room_instance_id := null;
    new.project_room_instance_module_id := null;
    new.module_part := null;

  elsif v_detail_type = 'module' then
    if new.project_room_instance_id is null and new.room_id is not null then
      select pri.id
        into new.project_room_instance_id
      from public.project_room_instances pri
      where pri.project_id = new.project_id
        and pri.room_id = new.room_id
        and pri.active = true
      order by pri.instance_number
      limit 1;
    end if;

    if new.project_room_instance_id is null then
      raise exception 'Selecione a sala específica do projeto.';
    end if;

    select
      pri.room_id,
      (
        upper(coalesce(r.code, '')) in ('MONO', 'MONOBLOCO')
        or upper(coalesce(r.name, '')) like '%MONOBLOCO%'
      )
      into v_room_id, v_is_monoblock
    from public.project_room_instances pri
    join public.rooms r on r.id = pri.room_id
    where pri.id = new.project_room_instance_id
      and pri.project_id = new.project_id
      and pri.active = true;

    if v_room_id is null then
      raise exception 'A sala selecionada não pertence a este projeto.';
    end if;

    if new.project_room_instance_module_id is null and new.module_id is not null then
      select prim.id
        into new.project_room_instance_module_id
      from public.project_room_instance_modules prim
      where prim.room_instance_id = new.project_room_instance_id
        and prim.legacy_module_id = new.module_id
        and prim.active = true
      order by prim.module_number
      limit 1;
    end if;

    if new.project_room_instance_module_id is null then
      raise exception 'Selecione o módulo da sala.';
    end if;

    select
      prim.legacy_module_id,
      prim.has_lower_part,
      prim.has_upper_part
      into v_legacy_module_id, v_lower, v_upper
    from public.project_room_instance_modules prim
    where prim.id = new.project_room_instance_module_id
      and prim.room_instance_id = new.project_room_instance_id
      and prim.active = true;

    if not found then
      raise exception 'O módulo selecionado não pertence a esta sala.';
    end if;

    if v_is_monoblock then
      new.module_part := null;
    else
      if new.module_part not in ('inferior', 'superior') then
        raise exception 'Selecione a parte inferior ou superior do módulo.';
      end if;

      if new.module_part = 'inferior' and coalesce(v_lower, false) = false then
        raise exception 'A parte inferior não está habilitada neste módulo.';
      end if;

      if new.module_part = 'superior' and coalesce(v_upper, false) = false then
        raise exception 'A parte superior não está habilitada neste módulo.';
      end if;
    end if;

    new.room_id := v_room_id;
    new.module_id := v_legacy_module_id;
    new.sector_id := null;
    new.panel_type_id := null;

  elsif v_detail_type = 'panel_type' then
    if new.panel_type_id is null then
      raise exception 'Selecione o tipo de painel para a área %.', new.area_code;
    end if;

    new.sector_id := null;
    new.room_id := null;
    new.module_id := null;
    new.project_room_instance_id := null;
    new.project_room_instance_module_id := null;
    new.module_part := null;

  elsif v_detail_type = 'room' then
    if new.project_room_instance_id is null and new.room_id is not null then
      select pri.id
        into new.project_room_instance_id
      from public.project_room_instances pri
      where pri.project_id = new.project_id
        and pri.room_id = new.room_id
        and pri.active = true
      order by pri.instance_number
      limit 1;
    end if;

    if new.project_room_instance_id is null then
      raise exception 'Selecione a sala específica do projeto.';
    end if;

    select pri.room_id
      into v_room_id
    from public.project_room_instances pri
    where pri.id = new.project_room_instance_id
      and pri.project_id = new.project_id
      and pri.active = true;

    if v_room_id is null then
      raise exception 'A sala selecionada não pertence a este projeto.';
    end if;

    new.room_id := v_room_id;
    new.sector_id := null;
    new.module_id := null;
    new.panel_type_id := null;
    new.project_room_instance_module_id := null;
    new.module_part := null;

  elsif v_detail_type = 'none' then
    new.sector_id := null;
    new.room_id := null;
    new.module_id := null;
    new.panel_type_id := null;
    new.project_room_instance_id := null;
    new.project_room_instance_module_id := null;
    new.module_part := null;

  else
    raise exception 'Fluxo inválido para a área %: %.',
      new.area_code,
      coalesce(v_detail_type, 'não informado');
  end if;

  return new;
end;
$$;

drop trigger if exists trg_validate_entry_flow_v212 on public.time_entries;
drop trigger if exists trg_validate_entry_structure_v213 on public.time_entries;
drop trigger if exists trg_validate_entry_structure_v216 on public.time_entries;
drop trigger if exists trg_validate_entry_dynamic_v2184 on public.time_entries;

create trigger trg_validate_entry_dynamic_v2184
before insert or update of
  project_id,
  activity_id,
  area_code,
  sector_id,
  room_id,
  module_id,
  panel_type_id,
  project_room_instance_id,
  project_room_instance_module_id,
  module_part
on public.time_entries
for each row
execute function public.aponta_validate_entry_dynamic_v2184();

commit;

-- CONFERÊNCIA
select code, name, detail_type, active
from public.work_areas
where code = 'COM';

select a.code, a.name, l.area_code
from public.activities a
join public.activity_area_links l on l.activity_id = a.id
where l.area_code = 'COM'
order by a.code, a.name
limit 30;

select trigger_name, event_manipulation
from information_schema.triggers
where event_object_schema = 'public'
  and event_object_table = 'time_entries'
  and trigger_name like '%entry%'
order by trigger_name, event_manipulation;
