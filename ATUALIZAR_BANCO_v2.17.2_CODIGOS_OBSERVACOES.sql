-- APONTA P3 v2.17.2
-- CÓDIGOS SEM EM- E OBSERVAÇÕES OPCIONAIS
-- Execute todo o arquivo no SQL Editor do Supabase.

begin;

-- Nenhuma atividade deverá exigir observação.
update public.activities
set observation_requirement = 'Opcional'
where observation_requirement is distinct from 'Opcional';

-- Remove o prefixo inicial EM- dos códigos existentes.
-- Caso o código sem EM- já exista, o cadastro antigo é mantido como legado
-- e inativado, preservando os apontamentos históricos.
do $$
declare
  item record;
  new_code text;
  duplicate_id public.activities.id%type;
begin
  for item in
    select id, code
    from public.activities
    where code is not null
      and trim(code) ~* '^EM-'
    order by created_at nulls last, id
  loop
    new_code := upper(regexp_replace(trim(item.code), '^EM-', '', 'i'));

    select id
      into duplicate_id
    from public.activities
    where id <> item.id
      and lower(trim(code)) = lower(new_code)
    limit 1;

    if duplicate_id is null then
      update public.activities
      set code = new_code,
          observation_requirement = 'Opcional'
      where id = item.id;
    else
      update public.activities
      set code = 'LEGADO-' || substr(item.id::text, 1, 8) || '-' || new_code,
          active = false,
          observation_requirement = 'Opcional'
      where id = item.id;
    end if;
  end loop;
end
$$;

commit;

-- Conferência:
select
  count(*) filter (where code ~* '^EM-') as codigos_ainda_com_em,
  count(*) filter (
    where coalesce(observation_requirement, '') <> 'Opcional'
  ) as observacoes_nao_opcionais,
  count(*) as total_atividades
from public.activities;
