-- APONTA P3 MODULAR v2.6
-- Campos complementares para importar a aba Atividades.

alter table public.activities
  add column if not exists responsible_name text not null default '';

alter table public.activities
  add column if not exists backup_name text not null default '';
