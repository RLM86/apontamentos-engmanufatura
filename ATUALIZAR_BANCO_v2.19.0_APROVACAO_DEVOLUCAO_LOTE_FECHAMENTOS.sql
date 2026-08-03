-- APONTA HORAS v2.19.0
-- APROVAÇÃO E DEVOLUÇÃO EM LOTE DOS FECHAMENTOS ENVIADOS
-- Execute todo este arquivo no SQL Editor do Supabase.

begin;

create or replace function public.aponta_review_monthly_closings_bulk_v2190(
  p_closing_ids uuid[],
  p_status text,
  p_review_note text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_active boolean;
  v_note text;
  v_selected_count integer := 0;
  v_closings_processed integer := 0;
  v_entries_updated integer := 0;
  v_entries_current integer := 0;
  v_closing public.monthly_closings%rowtype;
begin
  select
    lower(trim(coalesce(role, ''))),
    coalesce(active, false)
  into
    v_role,
    v_active
  from public.profiles
  where id = auth.uid();

  if auth.uid() is null then
    raise exception 'Usuário não autenticado.';
  end if;

  if not found or not v_active then
    raise exception 'Perfil inexistente ou inativo.';
  end if;

  if v_role not in ('gestor', 'administrador') then
    raise exception 'Somente Gestor ou Administrador pode analisar fechamentos.';
  end if;

  if p_status not in ('aprovado', 'devolvido') then
    raise exception 'Situação inválida. Use aprovado ou devolvido.';
  end if;

  if p_closing_ids is null or cardinality(p_closing_ids) = 0 then
    raise exception 'Selecione pelo menos um fechamento.';
  end if;

  v_note := trim(coalesce(p_review_note, ''));

  if p_status = 'devolvido' and v_note = '' then
    raise exception 'Informe o motivo da devolução em lote.';
  end if;

  select count(*)
    into v_selected_count
  from (
    select distinct unnest(p_closing_ids) as id
  ) selected;

  for v_closing in
    select mc.*
    from public.monthly_closings mc
    join (
      select distinct unnest(p_closing_ids) as id
    ) selected on selected.id = mc.id
    where mc.status = 'enviado'
    order by mc.month_ref, mc.user_id
    for update of mc
  loop
    update public.monthly_closings
    set
      status = p_status,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      review_note = v_note
    where id = v_closing.id;

    update public.time_entries
    set
      status = p_status,
      updated_at = now()
    where user_id = v_closing.user_id
      and entry_date >= v_closing.month_ref
      and entry_date < (v_closing.month_ref + interval '1 month')::date
      and status = 'enviado';

    get diagnostics v_entries_current = row_count;
    v_entries_updated := v_entries_updated + v_entries_current;
    v_closings_processed := v_closings_processed + 1;
  end loop;

  return jsonb_build_object(
    'requested_status', p_status,
    'closings_selected', v_selected_count,
    'closings_processed', v_closings_processed,
    'closings_skipped', greatest(v_selected_count - v_closings_processed, 0),
    'entries_updated', v_entries_updated,
    'reviewed_by', auth.uid(),
    'reviewed_at', now()
  );
end;
$$;

revoke all on function public.aponta_review_monthly_closings_bulk_v2190(
  uuid[],
  text,
  text
) from public;

grant execute on function public.aponta_review_monthly_closings_bulk_v2190(
  uuid[],
  text,
  text
) to authenticated;

commit;

-- Conferência da instalação
select
  routine_name,
  security_type
from information_schema.routines
where routine_schema = 'public'
  and routine_name = 'aponta_review_monthly_closings_bulk_v2190';
