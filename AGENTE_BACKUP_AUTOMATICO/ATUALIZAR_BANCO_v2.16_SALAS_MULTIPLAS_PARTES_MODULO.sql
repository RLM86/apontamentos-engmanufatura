-- APONTA P3 v2.16.0 — SALAS MÚLTIPLAS E PARTES DO MÓDULO
-- Execute este arquivo inteiro no SQL Editor do Supabase antes de publicar o app v2.16.0.

begin;

create extension if not exists pgcrypto;

create table if not exists public.project_room_instances (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  room_id uuid not null references public.rooms(id) on delete restrict,
  instance_number integer not null check (instance_number > 0),
  code text not null default '',
  display_name text not null default '',
  order_index integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id, room_id, instance_number)
);

create table if not exists public.project_room_instance_modules (
  id uuid primary key default gen_random_uuid(),
  room_instance_id uuid not null references public.project_room_instances(id) on delete cascade,
  module_number integer not null check (module_number > 0),
  legacy_module_id uuid references public.modules(id) on delete set null,
  code text not null default '',
  display_name text not null default '',
  order_index integer not null default 0,
  has_lower_part boolean not null default true,
  has_upper_part boolean not null default true,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(room_instance_id, module_number),
  unique(room_instance_id, code)
);

create index if not exists idx_project_room_instances_project_v216
  on public.project_room_instances(project_id, active, order_index);
create index if not exists idx_room_instance_modules_room_v216
  on public.project_room_instance_modules(room_instance_id, active, order_index);

alter table public.time_entries
  add column if not exists project_room_instance_id uuid,
  add column if not exists project_room_instance_module_id uuid,
  add column if not exists module_part text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='time_entries_room_instance_fk_v216') then
    alter table public.time_entries add constraint time_entries_room_instance_fk_v216
      foreign key(project_room_instance_id) references public.project_room_instances(id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname='time_entries_room_instance_module_fk_v216') then
    alter table public.time_entries add constraint time_entries_room_instance_module_fk_v216
      foreign key(project_room_instance_module_id) references public.project_room_instance_modules(id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname='time_entries_module_part_check_v216') then
    alter table public.time_entries add constraint time_entries_module_part_check_v216
      check(module_part is null or module_part in ('inferior','superior'));
  end if;
end $$;

alter table public.project_room_instances enable row level security;
alter table public.project_room_instance_modules enable row level security;
grant select,insert,update,delete on public.project_room_instances,public.project_room_instance_modules to authenticated;

drop policy if exists room_instances_select_v216 on public.project_room_instances;
create policy room_instances_select_v216 on public.project_room_instances for select to authenticated using(true);
drop policy if exists room_instances_insert_v216 on public.project_room_instances;
create policy room_instances_insert_v216 on public.project_room_instances for insert to authenticated with check((select public.is_manager()));
drop policy if exists room_instances_update_v216 on public.project_room_instances;
create policy room_instances_update_v216 on public.project_room_instances for update to authenticated using((select public.is_manager())) with check((select public.is_manager()));
drop policy if exists room_instances_delete_v216 on public.project_room_instances;
create policy room_instances_delete_v216 on public.project_room_instances for delete to authenticated using((select public.is_manager()));

drop policy if exists room_instance_modules_select_v216 on public.project_room_instance_modules;
create policy room_instance_modules_select_v216 on public.project_room_instance_modules for select to authenticated using(true);
drop policy if exists room_instance_modules_insert_v216 on public.project_room_instance_modules;
create policy room_instance_modules_insert_v216 on public.project_room_instance_modules for insert to authenticated with check((select public.is_manager()));
drop policy if exists room_instance_modules_update_v216 on public.project_room_instance_modules;
create policy room_instance_modules_update_v216 on public.project_room_instance_modules for update to authenticated using((select public.is_manager())) with check((select public.is_manager()));
drop policy if exists room_instance_modules_delete_v216 on public.project_room_instance_modules;
create policy room_instance_modules_delete_v216 on public.project_room_instance_modules for delete to authenticated using((select public.is_manager()));

-- Migra cada vínculo antigo Projeto > Sala como a primeira ocorrência daquela sala.
insert into public.project_room_instances(project_id,room_id,instance_number,code,display_name,order_index,active)
select pr.project_id,pr.room_id,1,
  coalesce(nullif(r.code,''),'SALA')||'-01',
  coalesce(nullif(pr.display_name,''),r.name)||case when coalesce(nullif(pr.display_name,''),r.name) ~ '[0-9]$' then '' else ' 01' end,
  pr.order_index,pr.active
from public.project_rooms pr
join public.rooms r on r.id=pr.room_id
on conflict(project_id,room_id,instance_number) do update set
  display_name=excluded.display_name,
  order_index=excluded.order_index,
  active=excluded.active,
  updated_at=now();

-- Migra os módulos antigos para a primeira ocorrência da sala.
with ranked as (
  select prm.*,m.code as module_code,m.name as module_name,
    row_number() over(partition by prm.project_id,prm.room_id order by prm.order_index,m.code,m.id)::integer as module_number
  from public.project_room_modules prm
  join public.modules m on m.id=prm.module_id
)
insert into public.project_room_instance_modules(
  room_instance_id,module_number,legacy_module_id,code,display_name,order_index,has_lower_part,has_upper_part,active
)
select pri.id,rk.module_number,rk.module_id,
  coalesce(nullif(rk.module_code,''),'MOD-'||lpad(rk.module_number::text,2,'0')),
  coalesce(nullif(rk.display_name,''),rk.module_name,'Módulo '||lpad(rk.module_number::text,2,'0')),
  rk.order_index,true,true,rk.active
from ranked rk
join public.project_room_instances pri
  on pri.project_id=rk.project_id and pri.room_id=rk.room_id and pri.instance_number=1
on conflict(room_instance_id,module_number) do update set
  legacy_module_id=excluded.legacy_module_id,
  code=excluded.code,
  display_name=excluded.display_name,
  order_index=excluded.order_index,
  active=excluded.active,
  updated_at=now();

-- Relaciona apontamentos antigos à primeira ocorrência da sala/módulo.
update public.time_entries te
set project_room_instance_id=pri.id
from public.project_room_instances pri
where te.project_room_instance_id is null
  and te.project_id=pri.project_id
  and te.room_id=pri.room_id
  and pri.instance_number=1;

update public.time_entries te
set project_room_instance_module_id=prim.id
from public.project_room_instance_modules prim
where te.project_room_instance_module_id is null
  and te.project_room_instance_id=prim.room_instance_id
  and te.module_id=prim.legacy_module_id;

create or replace function public.aponta_validate_entry_structure_v216()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_room_id uuid;
  v_legacy_module_id uuid;
  v_lower boolean;
  v_upper boolean;
begin
  if new.area_code='FAB' then
    if new.sector_id is null then raise exception 'Selecione o setor de fabricação.'; end if;
    new.room_id:=null; new.module_id:=null; new.panel_type_id:=null;
    new.project_room_instance_id:=null; new.project_room_instance_module_id:=null; new.module_part:=null;

  elsif new.area_code='MES' then
    -- Compatibilidade temporária com versões antigas durante a publicação.
    if new.project_room_instance_id is null and new.room_id is not null then
      select id into new.project_room_instance_id
      from public.project_room_instances
      where project_id=new.project_id and room_id=new.room_id and active=true
      order by instance_number limit 1;
    end if;
    if new.project_room_instance_id is null then raise exception 'Selecione a sala específica do projeto.'; end if;

    select room_id into v_room_id from public.project_room_instances
    where id=new.project_room_instance_id and project_id=new.project_id and active=true;
    if v_room_id is null then raise exception 'A sala selecionada não pertence a este projeto.'; end if;

    if new.project_room_instance_module_id is null and new.module_id is not null then
      select id into new.project_room_instance_module_id
      from public.project_room_instance_modules
      where room_instance_id=new.project_room_instance_id and legacy_module_id=new.module_id and active=true
      order by module_number limit 1;
    end if;
    if new.project_room_instance_module_id is null then raise exception 'Selecione o módulo da sala.'; end if;

    select legacy_module_id,has_lower_part,has_upper_part
      into v_legacy_module_id,v_lower,v_upper
    from public.project_room_instance_modules
    where id=new.project_room_instance_module_id
      and room_instance_id=new.project_room_instance_id and active=true;
    if not found then raise exception 'O módulo selecionado não pertence a esta sala.'; end if;

    if new.module_part is null then new.module_part:='inferior'; end if;
    if new.module_part='inferior' and not v_lower then raise exception 'A parte inferior não está habilitada neste módulo.'; end if;
    if new.module_part='superior' and not v_upper then raise exception 'A parte superior não está habilitada neste módulo.'; end if;

    new.room_id:=v_room_id;
    new.module_id:=v_legacy_module_id;
    new.sector_id:=null; new.panel_type_id:=null;

  elsif new.area_code='MPA' then
    if new.panel_type_id is null then raise exception 'Selecione o tipo de painel.'; end if;
    new.sector_id:=null; new.room_id:=null; new.module_id:=null;
    new.project_room_instance_id:=null; new.project_room_instance_module_id:=null; new.module_part:=null;

  elsif new.area_code='MFI' then
    if new.project_room_instance_id is null and new.room_id is not null then
      select id into new.project_room_instance_id
      from public.project_room_instances
      where project_id=new.project_id and room_id=new.room_id and active=true
      order by instance_number limit 1;
    end if;
    if new.project_room_instance_id is null then raise exception 'Selecione a sala específica do projeto.'; end if;
    select room_id into v_room_id from public.project_room_instances
    where id=new.project_room_instance_id and project_id=new.project_id and active=true;
    if v_room_id is null then raise exception 'A sala selecionada não pertence a este projeto.'; end if;
    new.room_id:=v_room_id;
    new.sector_id:=null; new.module_id:=null; new.panel_type_id:=null;
    new.project_room_instance_module_id:=null; new.module_part:=null;

  elsif new.area_code='ADM' then
    new.sector_id:=null; new.room_id:=null; new.module_id:=null; new.panel_type_id:=null;
    new.project_room_instance_id:=null; new.project_room_instance_module_id:=null; new.module_part:=null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validate_entry_structure_v213 on public.time_entries;
drop trigger if exists trg_validate_entry_structure_v216 on public.time_entries;
create trigger trg_validate_entry_structure_v216
before insert or update of project_id,area_code,sector_id,room_id,module_id,panel_type_id,
  project_room_instance_id,project_room_instance_module_id,module_part
on public.time_entries
for each row execute function public.aponta_validate_entry_structure_v216();

notify pgrst,'reload schema';
commit;
