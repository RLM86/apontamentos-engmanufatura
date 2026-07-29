-- APONTA P3 v2.18.1
-- LEITURA CONSISTENTE DOS VÍNCULOS DE ÁREAS DAS ATIVIDADES
-- Execute todo este arquivo no SQL Editor do Supabase.

begin;

create or replace function public.aponta_list_activity_area_links_v2181()
returns table(
  activity_id uuid,
  area_code text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    l.activity_id,
    l.area_code
  from public.activity_area_links l
  join public.activities a
    on a.id = l.activity_id
  join public.work_areas wa
    on wa.code = l.area_code
  order by
    a.name,
    wa.order_index,
    wa.name;
$$;

revoke all on function public.aponta_list_activity_area_links_v2181()
from public;

grant execute on function public.aponta_list_activity_area_links_v2181()
to authenticated;

commit;

-- Conferência das funções
select
  routine_name
from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
    'aponta_save_activity_v2180',
    'aponta_list_activity_area_links_v2181'
  )
order by routine_name;

-- Conferência opcional de uma atividade específica:
-- select
--   a.code,
--   a.name,
--   array_agg(l.area_code order by l.area_code) as areas
-- from public.activities a
-- left join public.activity_area_links l
--   on l.activity_id = a.id
-- where a.code = 'TST-004'
-- group by a.code, a.name;
