-- APONTA P3 v2.11.4 — CONFERIR INSCRIÇÕES PENDENTES
select
  id,
  full_name,
  email,
  role,
  active,
  registration_status,
  registration_reviewed_at
from public.profiles
where registration_status = 'pendente'
order by full_name;
