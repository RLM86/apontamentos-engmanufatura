-- APONTA P3 v2.1
-- Execute este arquivo no SQL Editor do Supabase após já ter executado o schema.sql.

create or replace function public.update_my_profile(
  p_full_name text,
  p_daily_hours numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado';
  end if;

  if length(trim(coalesce(p_full_name, ''))) < 2 then
    raise exception 'Informe um nome válido';
  end if;

  if p_daily_hours <= 0 or p_daily_hours > 24 then
    raise exception 'A jornada deve estar entre 1 e 24 horas';
  end if;

  update public.profiles
     set full_name = trim(p_full_name),
         daily_hours = p_daily_hours
   where id = auth.uid();
end;
$$;

grant execute on function public.update_my_profile(text, numeric) to authenticated;
