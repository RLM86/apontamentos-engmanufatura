-- APONTA P3 v2.19.25 - ATIVIDADE MACRO
-- Execute no SQL Editor do Supabase uma unica vez.
begin;

create table if not exists public.macro_atividades (
  id uuid primary key default gen_random_uuid(),
  nome text not null unique,
  ordem integer not null default 0,
  ativo boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.disciplina_macro_map (
  disciplina_nome text primary key,
  macro_atividade_id uuid not null references public.macro_atividades(id) on delete restrict,
  updated_at timestamptz not null default now()
);

alter table public.activities add column if not exists macro_atividade_id uuid references public.macro_atividades(id) on delete set null;
alter table public.time_entries add column if not exists macro_atividade_id uuid references public.macro_atividades(id) on delete set null;

insert into public.macro_atividades(nome,ordem) values
('ENGENHARIA DE PRODUTO',1),
('PROCESSOS E MANUFATURA',2),
('PLANEJAMENTO E MATERIAIS',3),
('MONTAGEM , FABRICAÇÃO E INTEGRAÇÃO',4),
('QUALIDADE, TESTES E SEGURANÇA',5),
('GESTAO E MELHORIAS',6)
on conflict(nome) do update set ordem=excluded.ordem, ativo=true;

with m(disciplina,macro) as (values
('Produto, DFMA e Fusion','ENGENHARIA DE PRODUTO'),
('Documentação Técnica e Controle de Mudanças','ENGENHARIA DE PRODUTO'),
('Processo e Industrialização','PROCESSOS E MANUFATURA'),
('Lantek, Nesting e Programação CNC','PROCESSOS E MANUFATURA'),
('PCP e Planejamento da Produção','PLANEJAMENTO E MATERIAIS'),
('Materiais, Compras Técnicas e Fornecedores','PLANEJAMENTO E MATERIAIS'),
('Montagem Estrutural','MONTAGEM , FABRICAÇÃO E INTEGRAÇÃO'),
('Montagem de Painéis','MONTAGEM , FABRICAÇÃO E INTEGRAÇÃO'),
('Montagem Final e Integrações','MONTAGEM , FABRICAÇÃO E INTEGRAÇÃO'),
('Fabricação Mecânica','MONTAGEM , FABRICAÇÃO E INTEGRAÇÃO'),
('Pintura, Corrosão e Vedação','MONTAGEM , FABRICAÇÃO E INTEGRAÇÃO'),
('Qualidade, Testes e RNC','QUALIDADE, TESTES E SEGURANÇA'),
('Segurança, Ergonomia e Meio Ambiente','QUALIDADE, TESTES E SEGURANÇA'),
('Testes, FAT e Comissionamento de Fábrica','QUALIDADE, TESTES E SEGURANÇA'),
('Gestão e Coordenação','GESTAO E MELHORIAS'),
('Lean, Dispositivos e Digitalização','GESTAO E MELHORIAS'),
('Melhoria, Dispositivos e Ferramental','GESTAO E MELHORIAS'),
('SAP e Dados de Manufatura','GESTAO E MELHORIAS')
)
insert into public.disciplina_macro_map(disciplina_nome,macro_atividade_id)
select m.disciplina,ma.id from m join public.macro_atividades ma on ma.nome=m.macro
on conflict(disciplina_nome) do update set macro_atividade_id=excluded.macro_atividade_id, updated_at=now();

create or replace function public.aponta_define_macro_atividade()
returns trigger language plpgsql set search_path=public as $$
begin
  select d.macro_atividade_id into new.macro_atividade_id
  from public.disciplina_macro_map d
  where lower(trim(d.disciplina_nome))=lower(trim(coalesce(new.discipline_name,'')))
  limit 1;
  return new;
end; $$;

drop trigger if exists trg_activities_define_macro on public.activities;
create trigger trg_activities_define_macro
before insert or update of discipline_name on public.activities
for each row execute function public.aponta_define_macro_atividade();

update public.activities a set macro_atividade_id=d.macro_atividade_id
from public.disciplina_macro_map d
where lower(trim(d.disciplina_nome))=lower(trim(coalesce(a.discipline_name,'')))
  and a.macro_atividade_id is distinct from d.macro_atividade_id;

-- Atualiza apontamentos existentes para facilitar consumo direto no Power BI.
update public.time_entries te set macro_atividade_id=a.macro_atividade_id
from public.activities a
where a.id=te.activity_id and te.macro_atividade_id is distinct from a.macro_atividade_id;

-- Novos apontamentos herdam a macro da atividade automaticamente.
create or replace function public.aponta_define_macro_apontamento()
returns trigger language plpgsql set search_path=public as $$
begin
  select a.macro_atividade_id into new.macro_atividade_id from public.activities a where a.id=new.activity_id;
  return new;
end; $$;
drop trigger if exists trg_time_entries_define_macro on public.time_entries;
create trigger trg_time_entries_define_macro
before insert or update of activity_id on public.time_entries
for each row execute function public.aponta_define_macro_apontamento();

grant select on public.macro_atividades to authenticated;
grant select on public.disciplina_macro_map to authenticated;

commit;

-- Conferencia: deve retornar 18 disciplinas mapeadas e 0 atividades sem macro (para disciplinas conhecidas).
select ma.nome as atividade_macro,count(a.id) as atividades
from public.macro_atividades ma left join public.activities a on a.macro_atividade_id=ma.id
group by ma.nome,ma.ordem order by ma.ordem;
