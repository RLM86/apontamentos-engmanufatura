-- APONTA P3 v2.18.3
-- CARGA COMPLETA DAS ÁREAS AGRUPADA POR ATIVIDADE
-- Execute todo este arquivo no SQL Editor do Supabase.

begin;

create or replace function public.aponta_list_activity_areas_grouped_v2183()
returns table(
  activity_id uuid,
  area_codes text[]
)
language sql
stable
security definer
set search_path = public
as $$
  select
    a.id as activity_id,
    coalesce(
      array_agg(
        distinct l.area_code
        order by l.area_code
      ) filter (
        where l.area_code is not null
      ),
      array[]::text[]
    ) as area_codes
  from public.activities a
  left join public.activity_area_links l
    on l.activity_id = a.id
  group by a.id, a.name
  order by a.name, a.id;
$$;

revoke all on function public.aponta_list_activity_areas_grouped_v2183()
from public;

grant execute on function public.aponta_list_activity_areas_grouped_v2183()
to authenticated;

commit;

-- ============================================================
-- CONFERÊNCIA
-- ============================================================

-- Quantidade total de atividades, atividades com áreas e vínculos:
select
  (select count(*) from public.activities) as total_atividades,
  (
    select count(distinct activity_id)
    from public.activity_area_links
  ) as atividades_com_areas,
  (
    select count(*)
    from public.activity_area_links
  ) as total_vinculos_de_areas;

-- Verificar especificamente as atividades TST:
select
  a.code,
  a.name,
  coalesce(
    array_agg(
      l.area_code
      order by l.area_code
    ) filter (
      where l.area_code is not null
    ),
    array[]::text[]
  ) as areas
from public.activities a
left join public.activity_area_links l
  on l.activity_id = a.id
where upper(coalesce(a.code,'')) like 'TST-%'
group by a.id, a.code, a.name
order by a.code;

-- Conferir a função agrupada:
select *
from public.aponta_list_activity_areas_grouped_v2183()
limit 20;
