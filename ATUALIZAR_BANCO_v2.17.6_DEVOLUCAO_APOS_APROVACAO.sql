-- APONTA P3 v2.17.6
-- DEVOLUÇÃO ADMINISTRATIVA DE FECHAMENTO JÁ APROVADO
-- Execute todo este arquivo no SQL Editor do Supabase.

begin;

create or replace function public.aponta_admin_return_approved_closing_v2176(
  p_closing_id uuid,
  p_destination text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_closing public.monthly_closings%rowtype;
  v_new_status text;
  v_entries_updated integer := 0;
  v_reason text;
begin
  select lower(trim(coalesce(role, '')))
    into v_role
  from public.profiles
  where id = auth.uid();

  if coalesce(v_role, '') <> 'administrador' then
    raise exception 'Somente o Administrador pode devolver um período depois da aprovação.';
  end if;

  if p_destination not in ('colaborador', 'gestor') then
    raise exception 'Destino inválido. Use colaborador ou gestor.';
  end if;

  v_reason := trim(coalesce(p_reason, ''));

  if v_reason = '' then
    raise exception 'Informe o motivo da devolução.';
  end if;

  select *
    into v_closing
  from public.monthly_closings
  where id = p_closing_id
  for update;

  if not found then
    raise exception 'Fechamento mensal não encontrado.';
  end if;

  if v_closing.status <> 'aprovado' then
    raise exception 'Somente um fechamento aprovado pode ser devolvido por esta função.';
  end if;

  v_new_status := case
    when p_destination = 'colaborador' then 'devolvido'
    else 'enviado'
  end;

  update public.monthly_closings
  set
    status = v_new_status,
    reviewed_by = auth.uid(),
    reviewed_at = now(),
    submitted_at = case
      when p_destination = 'gestor' then now()
      else submitted_at
    end,
    review_note = v_reason
  where id = v_closing.id;

  update public.time_entries
  set
    status = v_new_status,
    updated_at = now()
  where user_id = v_closing.user_id
    and entry_date >= v_closing.month_ref
    and entry_date < (v_closing.month_ref + interval '1 month')::date
    and status = 'aprovado';

  get diagnostics v_entries_updated = row_count;

  return jsonb_build_object(
    'closing_id', v_closing.id,
    'user_id', v_closing.user_id,
    'month_ref', v_closing.month_ref,
    'destination', p_destination,
    'new_status', v_new_status,
    'entries_updated', v_entries_updated,
    'returned_by', auth.uid(),
    'returned_at', now()
  );
end;
$$;

revoke all on function public.aponta_admin_return_approved_closing_v2176(
  uuid,
  text,
  text
) from public;

grant execute on function public.aponta_admin_return_approved_closing_v2176(
  uuid,
  text,
  text
) to authenticated;

commit;

-- Conferência da função
select
  routine_name
from information_schema.routines
where routine_schema = 'public'
  and routine_name = 'aponta_admin_return_approved_closing_v2176';
