-- APONTA P3 MODULAR v2.5
-- Bloqueia apontamentos em datas futuras diretamente no Supabase.
-- Execute este arquivo no SQL Editor do projeto.

create or replace function public.prevent_future_time_entry()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.entry_date > current_date then
    raise exception 'Não é permitido realizar apontamentos em datas futuras.'
      using errcode = '22007';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_prevent_future_time_entry on public.time_entries;

create trigger trg_prevent_future_time_entry
before insert or update of entry_date
on public.time_entries
for each row
execute function public.prevent_future_time_entry();
