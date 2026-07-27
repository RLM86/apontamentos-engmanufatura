-- APONTA P3 v2.11
-- APROVAÇÃO DE INSCRIÇÃO PARA LIBERAR APONTAMENTOS
--
-- Fluxo:
-- 1. Usuário cria a conta.
-- 2. Perfil entra como PENDENTE.
-- 3. Gestor ou Administrador aprova ou rejeita.
-- 4. Somente perfil APROVADO pode criar/alterar os próprios apontamentos.
--
-- Execute no Supabase:
-- SQL Editor > New query > Run

begin;

-- ============================================================
-- 1. CAMPOS DE APROVAÇÃO DA INSCRIÇÃO
-- ============================================================

alter table public.profiles
  add column if not exists registration_status text;

alter table public.profiles
  add column if not exists registration_reviewed_by uuid
  references public.profiles(id) on delete set null;

alter table public.profiles
  add column if not exists registration_reviewed_at timestamptz;

alter table public.profiles
  add column if not exists registration_review_note text not null default '';

-- Preserva os usuários que já utilizam o sistema.
update public.profiles
   set registration_status = 'aprovado',
       registration_reviewed_at = coalesce(registration_reviewed_at, created_at)
 where registration_status is null
    or trim(registration_status) = '';

alter table public.profiles
  alter column registration_status set default 'pendente';

alter table public.profiles
  alter column registration_status set not null;

alter table public.profiles
  drop constraint if exists profiles_registration_status_check_v211;

alter table public.profiles
  add constraint profiles_registration_status_check_v211
  check (registration_status in ('pendente', 'aprovado', 'rejeitado'));

create index if not exists idx_profiles_registration_status_v211
  on public.profiles(registration_status, active, full_name);

-- ============================================================
-- 2. NOVOS USUÁRIOS ENTRAM COMO PENDENTES
-- ============================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  first_user boolean;
begin
  select not exists(select 1 from public.profiles) into first_user;

  insert into public.profiles(
    id,
    full_name,
    email,
    role,
    active,
    registration_status,
    registration_reviewed_at,
    registration_review_note
  )
  values(
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)),
    coalesce(new.email,''),
    case when first_user then 'administrador' else 'colaborador' end,
    true,
    case when first_user then 'aprovado' else 'pendente' end,
    case when first_user then now() else null end,
    ''
  );

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_user();

-- ============================================================
-- 3. FUNÇÃO QUE CONFERE SE O PERFIL PODE APONTAR
-- ============================================================

create or replace function public.aponta_can_make_entries_v211(
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
      from public.profiles
     where id = p_user_id
       and active = true
       and registration_status = 'aprovado'
  );
$$;

revoke all
  on function public.aponta_can_make_entries_v211(uuid)
  from public;

grant execute
  on function public.aponta_can_make_entries_v211(uuid)
  to authenticated;

-- ============================================================
-- 4. GESTOR OU ADMINISTRADOR APROVA/REJEITA
-- ============================================================

create or replace function public.aponta_review_registration_v211(
  p_user_id uuid,
  p_decision text,
  p_note text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_target_role text;
  v_decision text;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado.';
  end if;

  v_role := public.aponta_current_role_v28();

  if v_role not in ('administrador', 'gestor') then
    raise exception 'Somente Gestor ou Administrador pode analisar inscrições.';
  end if;

  if not public.aponta_can_make_entries_v211(auth.uid()) then
    raise exception 'Seu próprio cadastro ainda não está aprovado.';
  end if;

  v_decision := lower(trim(coalesce(p_decision, '')));

  if v_decision not in ('aprovado', 'rejeitado') then
    raise exception 'Decisão inválida. Use aprovado ou rejeitado.';
  end if;

  select role into v_target_role
    from public.profiles
   where id = p_user_id;

  if v_target_role is null then
    raise exception 'Usuário não encontrado.';
  end if;

  -- Gestor pode analisar somente inscrições de colaboradores.
  if v_role = 'gestor' and v_target_role <> 'colaborador' then
    raise exception 'Gestor pode analisar somente inscrições de colaboradores.';
  end if;

  if p_user_id = auth.uid() and v_decision = 'rejeitado' then
    raise exception 'Você não pode rejeitar o próprio cadastro.';
  end if;

  update public.profiles
     set registration_status = v_decision,
         registration_reviewed_by = auth.uid(),
         registration_reviewed_at = now(),
         registration_review_note = trim(coalesce(p_note, ''))
   where id = p_user_id;
end;
$$;

revoke all
  on function public.aponta_review_registration_v211(uuid, text, text)
  from public;

grant execute
  on function public.aponta_review_registration_v211(uuid, text, text)
  to authenticated;

-- ============================================================
-- 5. BLOQUEIO NO BANCO DOS APONTAMENTOS
-- ============================================================

drop policy if exists entries_insert on public.time_entries;
create policy entries_insert
on public.time_entries
for insert
to authenticated
with check (
  (
    auth.uid() = user_id
    or (select public.is_manager())
  )
  and public.aponta_can_make_entries_v211(user_id)
);

drop policy if exists entries_update on public.time_entries;
create policy entries_update
on public.time_entries
for update
to authenticated
using (
  (
    auth.uid() = user_id
    and status in ('rascunho','devolvido')
    and public.aponta_can_make_entries_v211(auth.uid())
  )
  or (select public.is_manager())
)
with check (
  (
    auth.uid() = user_id
    and public.aponta_can_make_entries_v211(auth.uid())
  )
  or (select public.is_manager())
);

drop policy if exists entries_delete on public.time_entries;
create policy entries_delete
on public.time_entries
for delete
to authenticated
using (
  (
    auth.uid() = user_id
    and status in ('rascunho','devolvido')
    and public.aponta_can_make_entries_v211(auth.uid())
  )
  or (select public.is_manager())
);

-- Também protege o envio do fechamento pelo próprio colaborador.
drop policy if exists closings_insert on public.monthly_closings;
create policy closings_insert
on public.monthly_closings
for insert
to authenticated
with check (
  (
    auth.uid() = user_id
    and public.aponta_can_make_entries_v211(auth.uid())
  )
  or (select public.is_manager())
);

drop policy if exists closings_update on public.monthly_closings;
create policy closings_update
on public.monthly_closings
for update
to authenticated
using (
  (
    auth.uid() = user_id
    and status in ('aberto','devolvido')
    and public.aponta_can_make_entries_v211(auth.uid())
  )
  or (select public.is_manager())
)
with check (
  (
    auth.uid() = user_id
    and public.aponta_can_make_entries_v211(auth.uid())
  )
  or (select public.is_manager())
);

-- Defesa adicional contra inserção direta fora da tela do aplicativo.
create or replace function public.aponta_block_unapproved_entry_v211()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Permite operações administrativas internas com service_role,
  -- onde auth.uid() é nulo, como restauração de backup.
  if auth.uid() is not null
     and not public.aponta_can_make_entries_v211(new.user_id) then
    raise exception
      'Este usuário ainda não foi aprovado para realizar apontamentos.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_block_unapproved_entry_v211
  on public.time_entries;

create trigger trg_block_unapproved_entry_v211
before insert
on public.time_entries
for each row
execute function public.aponta_block_unapproved_entry_v211();

-- ============================================================
-- 6. VISIBILIDADE DE PERFIS
-- ============================================================

drop policy if exists profiles_select on public.profiles;
create policy profiles_select
on public.profiles
for select
to authenticated
using (
  id = auth.uid()
  or (select public.is_manager())
  or public.aponta_can_make_entries_v211(auth.uid())
);

notify pgrst, 'reload schema';

commit;

select
  'APONTA P3 v2.11 INSTALADO COM SUCESSO' as resultado,
  count(*) filter (where registration_status = 'pendente') as pendentes,
  count(*) filter (where registration_status = 'aprovado') as aprovados,
  count(*) filter (where registration_status = 'rejeitado') as rejeitados
from public.profiles;
