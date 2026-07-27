-- APONTA P3 v2.13.0 — ESTRUTURA PROJETO > SALA > MÓDULO
-- Gerado a partir da planilha revisada Proposta_Revisao_Projetos_Areas_Atividades_Setores_ApontaP3(1).xlsx
-- Execute todo este arquivo no SQL Editor do Supabase antes de publicar o app v2.13.0.

create extension if not exists pgcrypto;

create table if not exists public.project_rooms (
  project_id uuid not null references public.projects(id) on delete cascade,
  room_id uuid not null references public.rooms(id) on delete cascade,
  display_name text not null default '',
  order_index integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key(project_id, room_id)
);

create table if not exists public.project_room_modules (
  project_id uuid not null references public.projects(id) on delete cascade,
  room_id uuid not null references public.rooms(id) on delete cascade,
  module_id uuid not null references public.modules(id) on delete cascade,
  display_name text not null default '',
  order_index integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key(project_id, room_id, module_id)
);

create index if not exists idx_project_rooms_project_v213
  on public.project_rooms(project_id);

create index if not exists idx_project_room_modules_project_room_v213
  on public.project_room_modules(project_id, room_id);

alter table public.project_rooms enable row level security;
alter table public.project_room_modules enable row level security;

grant select, insert, update, delete on public.project_rooms,
  public.project_room_modules to authenticated;

drop policy if exists project_rooms_select_v213 on public.project_rooms;
create policy project_rooms_select_v213 on public.project_rooms
  for select to authenticated using (true);

drop policy if exists project_rooms_insert_v213 on public.project_rooms;
create policy project_rooms_insert_v213 on public.project_rooms
  for insert to authenticated
  with check ((select public.is_manager()));

drop policy if exists project_rooms_update_v213 on public.project_rooms;
create policy project_rooms_update_v213 on public.project_rooms
  for update to authenticated
  using ((select public.is_manager()))
  with check ((select public.is_manager()));

drop policy if exists project_rooms_delete_v213 on public.project_rooms;
create policy project_rooms_delete_v213 on public.project_rooms
  for delete to authenticated
  using ((select public.is_manager()));

drop policy if exists project_room_modules_select_v213 on public.project_room_modules;
create policy project_room_modules_select_v213 on public.project_room_modules
  for select to authenticated using (true);

drop policy if exists project_room_modules_insert_v213 on public.project_room_modules;
create policy project_room_modules_insert_v213 on public.project_room_modules
  for insert to authenticated
  with check ((select public.is_manager()));

drop policy if exists project_room_modules_update_v213 on public.project_room_modules;
create policy project_room_modules_update_v213 on public.project_room_modules
  for update to authenticated
  using ((select public.is_manager()))
  with check ((select public.is_manager()));

drop policy if exists project_room_modules_delete_v213 on public.project_room_modules;
create policy project_room_modules_delete_v213 on public.project_room_modules
  for delete to authenticated
  using ((select public.is_manager()));


create temporary table tmp_v213_projects (
  code text primary key,
  name text not null,
  client_name text not null,
  project_status text not null,
  active boolean not null
) on commit drop;

insert into tmp_v213_projects(code,name,client_name,project_status,active) values
('INTERNO-EM','Atividades internas da Engenharia de Manufatura','Interno','Em andamento',true),
('AWS','AWS','','Em andamento',true),
('TB11','TB11','','Em andamento',true),
('UFG','UFG','','Em andamento',true),
('PRODEB','PRODEB','','Em andamento',true),
('BARBADOS','BARBADOS','','Em andamento',true),
('FOR','FOR','','Em andamento',true),
('BOG','BOG','','Em andamento',true),
('CRUSOE','CRUSOE','','Em andamento',true);

update public.projects p
set name=t.name,
    client_name=t.client_name,
    project_status=t.project_status,
    active=t.active
from tmp_v213_projects t
where p.code=t.code
   or (p.code is null and p.name=t.name);

insert into public.projects(code,name,client_name,project_status,active)
select t.code,t.name,t.client_name,t.project_status,t.active
from tmp_v213_projects t
where not exists (
  select 1 from public.projects p
  where p.code=t.code or p.name=t.name
);


insert into public.work_areas(code,name,detail_type,order_index,active) values
('FAB','Fabricação','sector',1,true),
('MES','Montagem Estrutural','module',2,true),
('MPA','Montagem de Painéis','panel_type',3,true),
('MFI','Montagem Final','room',4,true),
('ADM','Administrativo','none',5,true)
on conflict(code) do update set
  name=excluded.name,
  detail_type=excluded.detail_type,
  order_index=excluded.order_index,
  active=excluded.active;


-- Corrige o código duplicado PINT da proposta anterior sem perder referências históricas.
update public.manufacturing_sectors s
set code=case
  when upper(s.name) like '%ELETROSTAT%' then 'PINT-PINTURA-ELETROSTATICA'
  else 'PINT-PINTURA-LIQUIDA'
end
where s.code='PINT'
  and not exists (
    select 1 from public.manufacturing_sectors s2
    where s2.code=case
      when upper(s.name) like '%ELETROSTAT%'
        then 'PINT-PINTURA-ELETROSTATICA'
      else 'PINT-PINTURA-LIQUIDA'
    end
  );

insert into public.manufacturing_sectors(code,name,description,order_index,active) values
('GERAL','GERAL FABRICAÇÃO','Atividade que abrange mais de um setor de fabricação.',1,true),
('PINT-PINTURA-LIQUIDA','PINTURA LIQUIDA','Preparação de superfície e pintura.',2,true),
('PINT-PINTURA-ELETROSTATICA','PINTURA ELETROSTATICA','Preparação de superfície e pintura.',3,true),
('SUBCONJUNTO','SUB CONJUNTO','Pré-montagem, separação e preparação de unidades.',4,true),
('KIT','PREARAÇAO DE KITS','Montagem e conferência de kits de produção.',5,true),
('LASER','LASER','Programação, nesting e corte a laser.',6,true),
('SERRA','SERRA','Serramento, furação e preparação de perfis.',7,true),
('FURAÇÃO','Área de  Furação','',0,false),
('DETALHAMENTO','Área de Detalhamento','',0,false),
('DOBRA','DOBRA','Dobra de chapas, perfis e barramentos.',8,true),
('SOLDA','SOLDA','Soldagem, caldeiraria e subconjuntos.',9,true),
('JATO','JATEAMENTO','Preparação de superfície por jateamento.',10,true),
('INSP','INSPEÇAO DAQUALIDADE','Inspeções dimensionais, visuais e de processo.',11,true),
('RETRAB','RETRABALHO','Ajustes, correções e retrabalhos controlados.',12,true),
('FUR','FURAÇÃO','Furaçao',13,true),
('DET','DETALHAMENTO','detalhamento',14,true),
('LIMP. LASER','LIMPEZA LASER','limpeza a laser',15,true),
('PREP. SUBS','PREPARAÇÃO DE SUBSTRATO','preparaçao de substrato',16,true),
('SETOR-OUTRO','Outro setor de fabricação','Usar quando o setor específico ainda não estiver cadastrado.',99,true)
on conflict(code) do update set
  name=excluded.name,
  description=excluded.description,
  order_index=excluded.order_index,
  active=excluded.active;

insert into public.panel_types(code,name,order_index,active) values
('UPS','UPS',1,true),
('BMS','BMS',2,true),
('RPP','RPP',3,true),
('QGBT','QGBT',4,true),
('PDU','PDU',5,true),
('ATS','ATS',6,true),
('CCM','CCM',7,true),
('PBT','Painel BT',8,true),
('PMT','Painel MT',9,true),
('AUT','Painel de Automação',10,true),
('CTRL','Painel de Controle',11,true),
('AUX','Painel Auxiliar',12,true),
('OUTRO','Outro tipo de painel',99,true)
on conflict(code) do update set
  name=excluded.name,
  order_index=excluded.order_index,
  active=excluded.active;


insert into public.rooms(code,name,functional_group,usage_suggested,order_index,active) values
('DH','Data Hall','','Sala principal de TI',3,true),
('SE','Sala Elétrica','','Sala elétrica geral',4,true),
('SALA-SALA-CATCHER','SALA CATCHER','','Sala vinculada à estrutura do projeto.',0,true),
('SALA-SALA-MEDIA','SALA MEDIA','','Sala vinculada à estrutura do projeto.',0,true),
('SALA-SALA-DE-MAQUINAS','SALA DE MAQUINAS','','Sala vinculada à estrutura do projeto.',0,true),
('PRJ-GERAL','Geral do projeto','','Sala vinculada à estrutura do projeto.',0,true),
('SALA-MONOBLOCO','MONOBLOCO','','Sala vinculada à estrutura do projeto.',0,true),
('SALA-GERAL','Geral do módulo','','Usar quando a atividade abrange todo o módulo',1,true),
('SALA-NA','Não aplicável','','Atividade sem vínculo com uma sala específica',2,true),
('BT','Sala de Baixa Tensão','','Painéis e distribuição BT',5,true),
('MT','Sala de Média Tensão','','Cubículos e sistemas de MT',6,true),
('UPS','Sala de UPS','','UPS e distribuição associada',7,true),
('BAT','Sala de Baterias','','Bancos de baterias e acessórios',8,true),
('TRAFO','Sala de Transformadores','','Transformadores e conexões',9,true),
('GER','Sala de Geradores','','Geradores e sistemas auxiliares',10,true),
('TELECOM','Sala de Telecom / MMR','','Telecomunicações e meet-me room',11,true),
('CTRL','Sala de Controle / BMS','','Controle, supervisão e BMS',12,true),
('CFTV','Sala de Segurança / CFTV','','CFTV e controle de acesso',13,true),
('SDACI','Sala / Área de SDACI','','Detecção, alarme e combate a incêndio',14,true),
('HVAC-SALA','Sala Mecânica / HVAC','','Climatização e equipamentos mecânicos',15,true),
('AGUA-GEL','Sala de Bombas / Água Gelada','','Bombas, manifolds e tubulação de água gelada',16,true),
('CATCHER','HVAC Catcher','','Unidade catcher acoplada ao Data Hall',17,true),
('COR-FRIO','Corredor Frio','','Corredor de insuflamento frio',18,true),
('COR-QUENTE','Corredor Quente','','Corredor de retorno quente',19,true),
('PLENUM','Plenum','','Plenum de insuflamento ou retorno',20,true),
('COR-TEC','Corredor Técnico','','Passagem técnica e manutenção',21,true),
('COR-ACESSO','Corredor de Acesso','','Circulação interna',22,true),
('ANTESSALA','Antessala','','Área de transição e acesso',23,true),
('COBERTURA','Cobertura / Teto','','Teto, cobertura e componentes superiores',24,true),
('BASE-PISO','Base / Piso Inferior','','Base estrutural e piso inferior',25,true),
('PISO-TEC','Piso Técnico / Elevado','','Piso elevado e infraestrutura associada',26,true),
('PAREDE-INT','Paredes Internas','','Paredes, divisórias e fechamentos internos',27,true),
('FACHADA','Paredes Externas / Fachada','','Envoltória e acabamento externo',28,true),
('CF','Compartimentação Corta-Fogo','','Selagens, portas e barreiras corta-fogo',29,true),
('INTERCON','Zona de Interconexão entre Módulos','','Interfaces e acoplamentos entre módulos',30,true),
('AREA-TEC-EXT','Área Técnica Externa','','Equipamentos e infraestrutura externos',31,true),
('EXPED','Área de Embalagem / Expedição','','Embalagem, amarração e expedição',32,true),
('FAB','Área de Fabricação','','Corte, dobra, solda e usinagem',33,true),
('PINT','Área de Pintura / Jateamento','','Preparação de superfície e pintura',34,true),
('MONT-EST','Área de Montagem Estrutural','','Bases, steel frame e estrutura',35,true),
('MONT-FINAL','Área de Montagem Final','','Integração e acabamentos finais',36,true),
('PAINEIS','Área de Montagem de Painéis','','Montagem de painéis e barramentos',37,true),
('TESTES','Área de Testes / FAT','','Inspeções, testes e FAT',38,true),
('ALMOX','Almoxarifado / Preparação de Kits','','Separação, conferência e preparação de materiais',39,true),
('OUTRA','Outra sala / área','','Cadastrar nova opção quando recorrente',40,true),
('NOC','Sala NOC / Operação','','Centro de operação e monitoramento',41,true),
('PDU-RPP','Sala PDU / RPP','','Distribuição elétrica próxima às cargas de TI',42,true),
('QGBT-MCC','Sala QGBT / MCC','','Quadros gerais, CCM e distribuição de potência',43,true),
('PROT-MED','Sala de Proteção e Medição','','Relés, medição, proteção e controle',44,true),
('SAUX','Sala de Serviços Auxiliares','','Serviços auxiliares CA/CC',45,true),
('RET','Sala de Retificadores','','Retificadores e sistemas CC',46,true),
('BCAP','Sala de Banco de Capacitores','','Correção de fator de potência e filtros',47,true),
('CHILLER','Sala / Área de Chillers','','Chillers e equipamentos associados',48,true),
('CRAH','Sala / Área de CRAH-CRAC','','Unidades de tratamento e climatização do Data Hall',49,true),
('MANIFOLD','Área de Manifold','','Manifolds, válvulas e distribuição hidráulica',50,true),
('BOMB-INC','Sala de Bombas de Incêndio','','Bombas e sistemas hidráulicos de incêndio',51,true),
('GAS-INC','Sala de Cilindros / Supressão por Gás','','Cilindros e sistemas de supressão por gás',52,true),
('MANTRAP','Eclusa / Mantrap','','Controle físico de acesso',53,true),
('ROOFTOP','Cobertura Técnica / Rooftop','','Equipamentos e interligações na cobertura',54,true),
('PASSARELA','Passarela / Ponte Técnica','','Conexões, travessias e acesso técnico',55,true),
('DOCA','Doca / Carga e Descarga','','Recebimento, carregamento e descarregamento',56,true),
('STAGING','Área de Staging / Pré-montagem','','Pré-montagem, separação e preparação de unidades',57,true),
('KIT','Área de Kitting / Preparação de Kits','','Montagem e conferência de kits de produção',58,true),
('LASER','Área de Corte Laser / Lantek','','Programação, nesting e corte a laser',59,true),
('SERRA-FUR','Área de Serra e Furação','','Serramento, furação e preparação de perfis',60,true),
('DOBRA','Área de Dobra e Conformação','','Dobra de chapas, perfis e barramentos',61,true),
('SOLDA','Área de Soldagem e Caldeiraria','','Soldagem, caldeiraria e subconjuntos',62,true),
('JATO','Área de Jateamento','','Preparação de superfície por jateamento',63,true),
('CAB-PINT','Cabine / Área de Pintura','','Pintura líquida, eletrostática e cura',64,true),
('MONT-MEC','Área de Montagem Mecânica','','Montagem de equipamentos e sistemas mecânicos',65,true),
('MONT-ELET','Área de Montagem Elétrica','','Infraestrutura, cabos, eletrocalhas e ligações',66,true),
('PAINEL-BT','Área de Painéis BT','','Montagem de painéis de baixa tensão',67,true),
('PAINEL-MT','Área de Painéis MT','','Montagem de painéis de média tensão',68,true),
('BARRAMENTO','Área de Fabricação de Barramentos','','Corte, dobra, furação e preparação de barramentos',69,true),
('BANC-ELET','Bancada Elétrica','','Montagem, crimpagem e testes de componentes elétricos',70,true),
('BANC-MEC','Bancada Mecânica','','Ajustes, preparação e montagem de componentes mecânicos',71,true),
('INSP','Área de Inspeção da Qualidade','','Inspeções dimensionais, visuais e de processo',72,true),
('LAB-TESTE','Laboratório / Bancada de Testes','','Ensaios, medições e validações técnicas',73,true),
('QUARENT','Área de Quarentena / Material Não Conforme','','Segregação e tratativa de materiais não conformes',74,true),
('RETRAB','Área de Retrabalho','','Ajustes, correções e retrabalhos controlados',75,true)
on conflict(code) do update set
  name=excluded.name,
  usage_suggested=excluded.usage_suggested,
  order_index=excluded.order_index,
  active=excluded.active;


insert into public.modules(code,name,module_type,usage_suggested,order_index,active) values
('MOD1','MOD1','','Módulo vinculado a uma sala do projeto.',0,true),
('MOD2','MOD2','','Módulo vinculado a uma sala do projeto.',1,true),
('MOD3','MOD3','','Módulo vinculado a uma sala do projeto.',2,true),
('MOD4','MOD4','','Módulo vinculado a uma sala do projeto.',3,true),
('MOD5','MOD5','','Módulo vinculado a uma sala do projeto.',4,true),
('MOD6','MOD6','','Módulo vinculado a uma sala do projeto.',5,true),
('MOD7','MOD7','','Módulo vinculado a uma sala do projeto.',6,true),
('MOD8','MOD8','','Módulo vinculado a uma sala do projeto.',7,true),
('M04','Módulo 04','','Módulo vinculado a uma sala do projeto.',4,true),
('M05','Módulo 05','','Módulo vinculado a uma sala do projeto.',5,true),
('M06','Módulo 06','','Módulo vinculado a uma sala do projeto.',6,true),
('M07','Módulo 07','','Módulo vinculado a uma sala do projeto.',7,true),
('M08','Módulo 08','','Módulo vinculado a uma sala do projeto.',8,true),
('M09','Módulo 09','','Módulo vinculado a uma sala do projeto.',9,true),
('M10','Módulo 10','','Módulo vinculado a uma sala do projeto.',10,true),
('M11','Módulo 11','','Módulo vinculado a uma sala do projeto.',11,true),
('M12','Módulo 12','','Módulo vinculado a uma sala do projeto.',12,true),
('M13','Módulo 13','','Módulo vinculado a uma sala do projeto.',13,true),
('M14','Módulo 14','','Módulo vinculado a uma sala do projeto.',14,true),
('M15','Módulo 15','','Módulo vinculado a uma sala do projeto.',15,true),
('M16','Módulo 16','','Módulo vinculado a uma sala do projeto.',16,true),
('MOD-GERAL','Geral do projeto','','Módulo vinculado a uma sala do projeto.',0,true),
('M01','Módulo 01','','Módulo vinculado a uma sala do projeto.',1,true),
('M02','Módulo 02','','Módulo vinculado a uma sala do projeto.',2,true),
('M03','Módulo 03','','Módulo vinculado a uma sala do projeto.',3,true)
on conflict(code) do update set
  name=excluded.name,
  usage_suggested=excluded.usage_suggested,
  order_index=excluded.order_index,
  active=excluded.active;


create temporary table tmp_v213_activities (
  code text primary key,
  name text not null,
  discipline_name text not null,
  sector_principal text not null,
  nature text not null,
  observation_requirement text not null,
  active boolean not null
) on commit drop;

insert into tmp_v213_activities(
  code,name,discipline_name,sector_principal,nature,
  observation_requirement,active
) values
('GES-001','Planejamento diário das atividades','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-002','Planejamento semanal das entregas','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-003','Priorização de demandas do projeto','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-004','Acompanhamento do cronograma de manufatura','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-005','Reunião de projeto','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-006','Reunião com Produção','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-007','Reunião com Engenharia de Produto / DFMA','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-008','Reunião com Qualidade','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-009','Reunião com fornecedor ou cliente','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-010','SQDC','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-011','OBEYA','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-012','Atualização de indicadores e relatórios','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-013','Preparação de apresentação técnica','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-014','Treinamento, integração ou capacitação','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-015','Distribuição e acompanhamento de tarefas da equipe','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-016','Reunião com PCP e planejamento','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-020','Reunião com Compras','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-021','Reunião com Suprimentos','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-022','Reunião de alinhamento multidisciplinar','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-023','Atualização do status das demandas','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-024','Conferência de apontamentos e horas da equipe','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('GES-025','Fechamento e registro de atividades concluídas','Gestão e Coordenação','Transversal','Rotina / Planejada','Não',true),
('DFM-001','Análise de fabricabilidade','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-002','Análise de montabilidade','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-003','Análise de acesso para fabricação e montagem','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-004','Análise de acesso para manutenção','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-005','Análise de interfaces entre disciplinas','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-006','Análise de interferências','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-007','Verificação de cotas, tolerâncias e detalhes construtivos','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-008','Verificação de materiais e especificações','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-009','Verificação de BOM / lista de materiais','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-010','Análise de Red Pen / marcações de campo','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-011','Análise de DANE ou SAE','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-012','Revisão técnica de desenho','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-013','Aprovação e liberação de desenho','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-014','Devolução de desenho para correção','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-015','Tratativa de alteração de engenharia / CCB','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-016','Padronização, simplificação ou nacionalização do produto','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-017','Análise de peça especial ou solução não padronizada','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-018','Análise de transporte e embalagem no desenvolvimento do produto','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-019','Análise de manutenção e substituição de componentes','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('DFM-020','Validação da alteração incorporada ao desenho','Produto, DFMA e Fusion','Multissetorial','Planejada / Demanda','Não',true),
('PRC-001','Desenvolvimento de processo de fabricação','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-002','Desenvolvimento de processo de montagem','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-003','Revisão e otimização de processo existente','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-004','Definição da sequência de fabricação','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-005','Definição da sequência de montagem','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-006','Definição de método, máquinas, ferramentas e recursos','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-007','Elaboração de instrução de trabalho','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-008','Revisão de instrução de trabalho','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-009','Elaboração de auxílio visual ou padrão operacional','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-010','Estudo de tempos','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-011','Definição de tempo padrão e tempo de ciclo','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-012','Análise de capacidade produtiva','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-013','Dimensionamento de mão de obra','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-014','Balanceamento de atividades ou linha','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-015','Desenvolvimento ou alteração de layout','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-016','Acompanhamento de primeira execução / try-out','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-017','Validação e liberação de processo','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-018','Treinamento da produção e acompanhamento de ramp-up','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-019','Levantamento do processo atual em fábrica','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-020','Criação de fluxograma ou mapa de processo','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-021','Elaboração de checklist de processo','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-022','Preparação do plano de industrialização','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('PRC-023','Acompanhamento de processo executado por fornecedor','Processo e Industrialização','Multissetorial','Planejada / Demanda','Não',true),
('SAP-001','Criação de rota de fabricação ou montagem','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-002','Revisão de rota','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-003','Verificação de rota versus processo real','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-004','Criação de operação','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-005','Alteração ou correção de operação','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-006','Definição da sequência de operações','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-007','Cadastro ou correção de centro de trabalho','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-008','Cadastro de tempos de operação','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-009','Revisão e validação de tempos no SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-010','Criação ou consulta de ordem de produção','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-011','Verificação de ordem de produção','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-012','Correção de ordem ou sequência de operações','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-013','Verificação de apontamentos de produção','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-014','Correção ou estorno de apontamentos','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-015','Análise de divergência entre roteiro, OP e produção','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-016','Cadastro, saneamento ou atualização em massa de dados mestres','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-017','Criação ou revisão de versão de produção','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-018','Liberação técnica de roteiro ou operação','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-019','Verificação de consumo e baixa de materiais','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-020','Análise de estorno ou correção de componentes','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-021','Verificação do status e avanço da ordem de produção','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-022','Fechamento técnico de ordem de produção','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-023','Extração e análise de dados do SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-024','Apoio ao usuário em transação SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('SAP-025','Teste e validação de alteração realizada no SAP','SAP e Dados de Manufatura','Transversal','Rotina / Demanda','Não',true),
('LTK-001','Cadastro ou importação de geometrias no Lantek','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-002','Revisão do desenho para programação','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-003','Criação de nesting manual','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-004','Criação de nesting automático','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-005','Revisão de nesting','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-006','Otimização de nesting e aproveitamento de chapa','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-007','Análise e reaproveitamento de retalhos','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-008','Definição ou ajuste de parâmetros de corte','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-009','Suporte técnico à máquina ou à produção','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-010','Gestão de biblioteca de materiais e chapas','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-011','Acompanhamento da primeira chapa cortada','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-012','Reprogramação por alteração de desenho','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('LTK-013','Análise de tempo estimado de corte','Lantek, Nesting e Programação CNC','Fabricação','Planejada / Demanda','Não',true),
('FAB-001','Atendimento tecnico do processo de corte','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-002','Atendimento tecnico do processo de furação','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-003','Atendimento tecnico do processo de dobra','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-004','Atendimento tecnico do processo de detalhamento','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-005','Atendimento tecnico do processo de soldagem','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-006','Atendimento tecnico de caldeiraria e montagem de subconjuntos','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-007','Definição de gabaritos e meios de fixação','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-008','Definição ou ajuste de parâmetros de máquina','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-009','Validação de primeira peça fabricada','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-010','Acompanhamento de fabricação crítica','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-011','Tratativa de desvio dimensional','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-012','Tratativa de falta ou incompatibilidade de material','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-013','Definição e acompanhamento de retrabalho ou refugo','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-014','Atendimento tecnico do processo de serra','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-015','Análise de marcação e identificação de peças','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-016','Definição da sequência de fabricação de subconjuntos','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-017','Análise de capacidade e disponibilidade de máquina','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-018','Definição ou ajuste de ferramental de fabricação','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-019','Análise de consumíveis e parâmetros de processo','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-020','Acompanhamento de protótipo ou lote piloto','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-021','Análise de preparação de superfície','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-002','Análise do processo de jateamento','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-003','Análise de pintura líquida','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-004','Análise de pintura eletrostática','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-005','Análise de pintura intumescente','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-006','Verificação de ponto de orvalho e condição ambiental','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-007','Análise de vedação e aplicação de selantes','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-008','Acompanhamento de processo crítico de pintura','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-009','Tratativa de falha, corrosão ou retrabalho superficial','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-010','Definição de mascaramento e proteção de superfícies','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-011','Cálculo ou estimativa de consumo de tinta e insumos','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-012','Análise de cura, secagem e intervalo entre demãos','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('PIN-013','Validação do reparo de pintura ou corrosão','Pintura, Corrosão e Vedação','Fabricação / Montagem Final/Montagem estrutural','Demanda / Emergencial','Não',true),
('MES-001','Definição da sequência de montagem estrutural','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Não',true),
('MES-002','Atendimento tecnico de montagem Estrutual','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Não',true),
('MES-003','Definição ou validação de torque estrutural','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Não',true),
('MES-004','Análise de içamento e pontos de pega','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Não',true),
('MES-005','Análise de movimentação e posicionamento de estruturas','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Não',true),
('MES-006','Análise de acoplamento entre módulos','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Não',true),
('MES-007','Análise de suportes e suportagem','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Não',true),
('MES-008','Definição de ajuste, retrabalho e liberação estrutural','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Não',true),
('MES-009','Análise e validação de gabarito estrutural','Montagem Estrutural','Montagem Estrutural','Demanda / Emergencial','Não',true),
('MFI-001','Definição da sequência de montagem final','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-002','Análise de instalação de HVAC e climatização','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-003','Análise de tubulação de água gelada','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-004','Análise de ventilação e renovação de ar','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-005','Análise de eletrocalhas e leitos','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-006','Análise de eletrodutos e canaletas','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-007','Análise de infraestrutura elétrica','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-008','Análise de BMS e automação','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-009','Análise de CFTV e controle de acesso','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-010','Análise de detecção, alarme e combate a incêndio','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-011','Análise de iluminação e aterramento','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-012','Análise de pisos, forros e revestimentos','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-013','Análise de portas, janelas e fechamentos','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-014','Análise de vedação e selagem corta-fogo','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-015','Análise de instalação e fixação de equipamentos','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-016','Análise de interconexões entre módulos','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-017','Acompanhamento de montagem final crítica','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-018','Definição de ajuste, retrabalho e liberação final','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-019','Análise de embalagem, amarração e transporte','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-020','Atendimento técnico à montagem final','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-021','Análise de rota multidisciplinar','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-022','Análise de suportação e pontos de fixação','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-023','Coordenação e tratativa de interferências em montagem','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-024','Análise de acessibilidade e manutenção dos sistemas','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-025','Análise de interfaces entre montagem final e painéis','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-026','Acompanhamento de interligações mecânicas e elétricas','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MFI-027','Acompanhamento de preparação para transporte e entrega','Montagem Final e Integrações','Montagem Final','Demanda / Emergencial','Não',true),
('MPA-001','Definição da sequência de montagem do painel','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-002','Análise do layout interno do painel','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-003','Análise do posicionamento de componentes','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-004','Análise de fabricação de barramentos rígidos','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-005','Análise de montagem e conexão de barramentos','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-006','Análise de barramentos flexíveis','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-007','Análise de corte, dobra e furação de barramentos','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-008','Análise de tratamento superficial de barramentos','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-009','Análise de cabos, terminais e crimpagem','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-010','Análise de identificação, anilhas e etiquetas','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-011','Definição ou validação de torque elétrico','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-012','Análise de furação, portas e adaptações mecânicas','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-013','Análise de transformadores, TCs e instrumentos','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-014','Verificação de continuidade e isolação — Painéis','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-015','Acompanhamento de testes funcionais','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-016','Acompanhamento de energização ou painel energizado','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-017','Apoio técnico ao FAT de painéis','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-018','Definição de ajuste, retrabalho e liberação do painel','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-019','Análise da lista de materiais do painel','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-020','Definição de ferramentas, bancadas e recursos','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-021','Verificação de diagrama e documentação para montagem','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('MPA-022','Correção de montagem após teste ou inspeção','Montagem de Painéis','Montagem de Painéis','Demanda / Emergencial','Não',true),
('QLD-001','Inspeção e validação dimensional','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-002','Validação de primeira peça','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-003','Validação de processo de fabricação','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-004','Validação de montagem estrutural','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-005','Validação de montagem final','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-006','Validação de montagem de painéis','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-007','Validação de soldagem','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-008','Validação de pintura e proteção anticorrosiva','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-009','Validação de vedação e acabamento','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-010','Validação de torque e fixações','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-011','Verificação ou relatório Qualificação de Instalação (IQ)','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-012','Verificação ou relatório Qualificação de Operação(OQ)','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-013','Verificação ou relatório Qualificação de Desempenho (PQ)','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-014','Auditoria de processo','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-015','Análise de RNC / não conformidade','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-016','Investigação de causa raiz','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-017','Definição de contenção, retrabalho e verificação de eficácia','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-018','Registro e aplicação de lição aprendida','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-019','Elaboração ou revisão de PFMEA','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-020','Elaboração ou revisão de Plano de Controle','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-021','Elaboração ou revisão de plano de inspeção','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-022','Elaboração de A3 ou 8D','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-023','Análise de capacidade e estabilidade do processo','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-024','Acompanhamento de auditoria de cliente ou terceira parte','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-025','Análise de reincidência de não conformidade','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-026','Fechamento de punch list de fabricação ou montagem','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('QLD-027','Organização e validação de evidências da qualidade','Qualidade, Testes e RNC','Multissetorial','Demanda / Validação','Não',true),
('SST-001','Reunião com Segurança do Trabalho','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-002','DDS ou alinhamento de segurança','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-003','Análise de risco do processo','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-004','Avaliação ergonômica do posto de trabalho','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-005','Análise de movimentação manual de carga','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-006','Análise de içamento e movimentação mecanizada','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-007','Avaliação de segurança de máquina','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-008','Avaliação de segurança de ferramenta ou dispositivo','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-009','Análise de bloqueio, etiquetagem e energias perigosas','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-010','Análise de trabalho em altura e acesso','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-011','Análise de produtos químicos, pintura e ventilação','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-012','Análise ambiental, resíduos e impacto do processo','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-013','Definição e acompanhamento de melhoria de segurança ou ergonomia','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-014','Elaboração ou revisão de APR','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-015','Definição de EPI e EPC do processo','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-016','Validação de proteção e adequação de máquina','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-017','Análise de acesso e manutenção segura','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-018','Reunião específica de ergonomia','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-019','Análise de altura, alcance, postura e esforço no posto','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-020','Acompanhamento da adequação de segurança ou ergonomia','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('SST-021','Validação da condição após implantação da melhoria','Segurança, Ergonomia e Meio Ambiente','Multissetorial','Planejada / Demanda','Não',true),
('MEL-001','Evento Kaizen ou melhoria contínua','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-002','Melhoria de produtividade','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-003','Redução de custos','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-004','Redução de desperdício, refugo ou retrabalho','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-005','Melhoria de layout ou posto de trabalho','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-006','Padronização entre projetos','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-007','Desenvolvimento de dispositivo/gabaritos','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-008','Acompanhamento da fabricação de dispositivo','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-009','Try-out e ajuste de dispositivo','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-010','Validação e liberação de dispositivo','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-011','Automação ou digitalização de processo','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-012','Desenvolvimento de Power BI, Power Apps, SharePoint ou APP','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-013','Levantamento de oportunidade de melhoria','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-014','Estudo de viabilidade técnica e econômica','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-015','Mapeamento de fluxo de valor','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-016','Implantação ou auditoria de 5S','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-017','Desenvolvimento de trabalho padronizado','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-018','Desenvolvimento de poka-yoke','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-019','Análise e redução de tempo de setup','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('MEL-020','Implantação de Kanban ou gestão visual de fluxo','Lean, Dispositivos e Digitalização','Multissetorial','Melhoria','Não',true),
('PCP-001','Planejamento da demanda de fabricação e montagem','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Não',true),
('PCP-002','Revisão do sequenciamento de produção','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Não',true),
('PCP-003','Análise de carga e capacidade por recurso','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Não',true),
('PCP-004','Acompanhamento da programação diária ou semanal','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Não',true),
('PCP-005','Verificação de disponibilidade de máquina, mão de obra e recurso','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Não',true),
('PCP-006','Atualização do cronograma de manufatura','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Não',true),
('PCP-007','Reunião e alinhamento com PCP','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Não',true),
('PCP-008','Definição de prioridade de ordens de produção','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Não',true),
('PCP-009','Análise de atraso e plano de recuperação','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Não',true),
('PCP-010','Controle de avanço físico por módulo ou sala','PCP e Planejamento da Produção','Transversal','Planejada / Rotina','Não',true),
('MAT-001','Análise de necessidade de material','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Não',true),
('MAT-002','Verificação de disponibilidade em estoque','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Não',true),
('MAT-003','Análise e aprovação de material alternativo','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Não',true),
('MAT-004','Elaboração de especificação técnica para compra','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Não',true),
('MAT-005','Solicitação ou requisição de compra técnica','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Não',true),
('MAT-006','Reunião técnica com fornecedor','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Não',true),
('MAT-007','Follow-up de fabricação ou entrega de fornecedor','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Não',true),
('MAT-008','Aprovação de amostra ou protótipo de fornecedor','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Não',true),
('MAT-009','Análise de nacionalização de componente ou fornecedor','Materiais, Compras Técnicas e Fornecedores','Multissetorial','Planejada / Demanda','Não',true),
('DOC-001','Criação ou revisão de documentação técnica','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Não',true),
('DOC-002','Cadastro, publicação ou atualização de documento no sistema','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Não',true),
('DOC-003','Análise de documento recebido de outra área ou fornecedor','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Não',true),
('DOC-004','Revisão e atualização de desenho as-built','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Não',true),
('DOC-005','Controle e consolidação de Red Pen','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Não',true),
('DOC-006','Registro e acompanhamento de DANE ou mudança','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Não',true),
('DOC-007','Elaboração e atualização de lista de pendências','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Não',true),
('DOC-008','Organização de registros e evidências técnicas','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Não',true),
('DOC-009','Emissão de relatório técnico','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Não',true),
('DOC-010','Atualização de matriz ou índice de documentos','Documentação Técnica e Controle de Mudanças','Transversal','Rotina / Demanda','Não',true),
('TST-001','Planejamento de teste ou FAT','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-002','Preparação de checklist, procedimento ou protocolo de teste','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-003','Verificação de pré-requisitos para teste','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-004','Acompanhamento de FAT / L1','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-005','Acompanhamento de SAT / L2 de fábrica ou pré-site','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-006','Apoio a startup e energização controlada','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-007','Acompanhamento de teste funcional','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-008','Verificação de continuidade e isolação — Testes/FAT','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-009','Verificação de torque e conexões','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-010','Teste de vedação, estanqueidade ou acabamento','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-011','Teste de pintura, espessura ou aderência','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-012','Tratativa e acompanhamento de punch list','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-013','Registro e organização de evidências de teste','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-014','Análise de falha identificada em teste','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('TST-015','Liberação técnica após teste','Testes, FAT e Comissionamento de Fábrica','Multissetorial','Validação / Demanda','Não',true),
('FAB-021-FABRICACAO-M','Atendimento técnico Jateamento','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-022','Atendimento técnico Limpeza Laser','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true),
('FAB-023','Atendimento técnico a Preparaçao de tintas','Fabricação Mecânica','Fabricação','Demanda / Emergencial','não',true);

update public.activities a
set name=t.name,
    discipline_name=t.discipline_name,
    sector_principal=t.sector_principal,
    nature=t.nature,
    observation_requirement=t.observation_requirement,
    active=t.active
from tmp_v213_activities t
where a.code=t.code
   or (a.code is null and a.name=t.name);

insert into public.activities(
  code,name,discipline_name,sector_principal,nature,
  observation_requirement,usage_description,active,
  activity_type,frequency,responsible_name,backup_name
)
select
  t.code,t.name,t.discipline_name,t.sector_principal,t.nature,
  t.observation_requirement,
  'Registrar objetivamente a atividade executada e o resultado obtido.',
  t.active,'Demanda','','',''
from tmp_v213_activities t
where not exists (
  select 1 from public.activities a
  where a.code=t.code or a.name=t.name
);

create temporary table tmp_v213_activity_links (
  activity_code text not null,
  area_code text not null
) on commit drop;

insert into tmp_v213_activity_links(activity_code,area_code) values
('GES-001','ADM'),
('GES-002','ADM'),
('GES-003','ADM'),
('GES-004','ADM'),
('GES-005','ADM'),
('GES-006','ADM'),
('GES-007','ADM'),
('GES-008','ADM'),
('GES-009','ADM'),
('GES-010','ADM'),
('GES-011','ADM'),
('GES-012','ADM'),
('GES-013','ADM'),
('GES-014','ADM'),
('GES-015','ADM'),
('GES-016','ADM'),
('GES-020','ADM'),
('GES-021','ADM'),
('GES-022','ADM'),
('GES-023','ADM'),
('GES-024','ADM'),
('GES-025','ADM'),
('DFM-001','ADM'),
('DFM-002','ADM'),
('DFM-003','ADM'),
('DFM-004','ADM'),
('DFM-005','ADM'),
('DFM-006','ADM'),
('DFM-007','ADM'),
('DFM-008','ADM'),
('DFM-009','ADM'),
('DFM-010','ADM'),
('DFM-011','ADM'),
('DFM-012','ADM'),
('DFM-013','ADM'),
('DFM-014','ADM'),
('DFM-015','ADM'),
('DFM-016','ADM'),
('DFM-017','ADM'),
('DFM-018','ADM'),
('DFM-019','ADM'),
('DFM-020','ADM'),
('PRC-001','ADM'),
('PRC-002','ADM'),
('PRC-003','ADM'),
('PRC-004','ADM'),
('PRC-005','ADM'),
('PRC-006','ADM'),
('PRC-007','ADM'),
('PRC-008','ADM'),
('PRC-009','ADM'),
('PRC-010','ADM'),
('PRC-011','ADM'),
('PRC-012','ADM'),
('PRC-013','ADM'),
('PRC-014','ADM'),
('PRC-015','ADM'),
('PRC-016','ADM'),
('PRC-017','ADM'),
('PRC-018','ADM'),
('PRC-019','ADM'),
('PRC-020','ADM'),
('PRC-021','ADM'),
('PRC-022','ADM'),
('PRC-023','ADM'),
('SAP-001','ADM'),
('SAP-002','ADM'),
('SAP-003','ADM'),
('SAP-004','ADM'),
('SAP-005','ADM'),
('SAP-006','ADM'),
('SAP-007','ADM'),
('SAP-008','ADM'),
('SAP-009','ADM'),
('SAP-010','ADM'),
('SAP-011','ADM'),
('SAP-012','ADM'),
('SAP-013','ADM'),
('SAP-014','ADM'),
('SAP-015','ADM'),
('SAP-016','ADM'),
('SAP-017','ADM'),
('SAP-018','ADM'),
('SAP-019','ADM'),
('SAP-020','ADM'),
('SAP-021','ADM'),
('SAP-022','ADM'),
('SAP-023','ADM'),
('SAP-024','ADM'),
('SAP-025','ADM'),
('LTK-001','FAB'),
('LTK-002','FAB'),
('LTK-003','FAB'),
('LTK-004','FAB'),
('LTK-005','FAB'),
('LTK-006','FAB'),
('LTK-007','FAB'),
('LTK-008','FAB'),
('LTK-009','FAB'),
('LTK-010','FAB'),
('LTK-011','FAB'),
('LTK-012','FAB'),
('LTK-013','FAB'),
('FAB-001','FAB'),
('FAB-002','FAB'),
('FAB-003','FAB'),
('FAB-004','FAB'),
('FAB-005','FAB'),
('FAB-006','FAB'),
('FAB-007','FAB'),
('FAB-008','FAB'),
('FAB-009','FAB'),
('FAB-010','FAB'),
('FAB-011','FAB'),
('FAB-012','FAB'),
('FAB-013','FAB'),
('FAB-014','FAB'),
('FAB-015','FAB'),
('FAB-016','FAB'),
('FAB-017','FAB'),
('FAB-018','FAB'),
('FAB-019','FAB'),
('FAB-020','FAB'),
('FAB-021','FAB'),
('FAB-021','MFI'),
('PIN-002','FAB'),
('PIN-002','MFI'),
('PIN-003','FAB'),
('PIN-003','MFI'),
('PIN-004','FAB'),
('PIN-004','MFI'),
('PIN-005','FAB'),
('PIN-005','MFI'),
('PIN-006','FAB'),
('PIN-006','MFI'),
('PIN-007','FAB'),
('PIN-007','MFI'),
('PIN-008','FAB'),
('PIN-008','MFI'),
('PIN-009','FAB'),
('PIN-009','MFI'),
('PIN-010','FAB'),
('PIN-010','MFI'),
('PIN-011','FAB'),
('PIN-011','MFI'),
('PIN-012','FAB'),
('PIN-012','MFI'),
('PIN-013','FAB'),
('PIN-013','MFI'),
('MES-001','MES'),
('MES-002','MES'),
('MES-003','MES'),
('MES-004','MES'),
('MES-005','MES'),
('MES-006','MES'),
('MES-007','MES'),
('MES-008','MES'),
('MES-009','MES'),
('MFI-001','MFI'),
('MFI-002','MFI'),
('MFI-003','MFI'),
('MFI-004','MFI'),
('MFI-005','MFI'),
('MFI-006','MFI'),
('MFI-007','MFI'),
('MFI-008','MFI'),
('MFI-009','MFI'),
('MFI-010','MFI'),
('MFI-011','MFI'),
('MFI-012','MFI'),
('MFI-013','MFI'),
('MFI-014','MFI'),
('MFI-015','MFI'),
('MFI-016','MFI'),
('MFI-017','MFI'),
('MFI-018','MFI'),
('MFI-019','MFI'),
('MFI-020','MFI'),
('MFI-021','MFI'),
('MFI-022','MFI'),
('MFI-023','MFI'),
('MFI-024','MFI'),
('MFI-025','MFI'),
('MFI-026','MFI'),
('MFI-027','MFI'),
('MPA-001','MPA'),
('MPA-002','MPA'),
('MPA-003','MPA'),
('MPA-004','MPA'),
('MPA-005','MPA'),
('MPA-006','MPA'),
('MPA-007','MPA'),
('MPA-008','MPA'),
('MPA-009','MPA'),
('MPA-010','MPA'),
('MPA-011','MPA'),
('MPA-012','MPA'),
('MPA-013','MPA'),
('MPA-014','MPA'),
('MPA-015','MPA'),
('MPA-016','MPA'),
('MPA-017','MPA'),
('MPA-018','MPA'),
('MPA-019','MPA'),
('MPA-020','MPA'),
('MPA-021','MPA'),
('MPA-022','MPA'),
('QLD-001','ADM'),
('QLD-002','ADM'),
('QLD-003','ADM'),
('QLD-004','ADM'),
('QLD-005','ADM'),
('QLD-006','ADM'),
('QLD-007','ADM'),
('QLD-008','ADM'),
('QLD-009','ADM'),
('QLD-010','ADM'),
('QLD-011','ADM'),
('QLD-012','ADM'),
('QLD-013','ADM'),
('QLD-014','ADM'),
('QLD-015','ADM'),
('QLD-016','ADM'),
('QLD-017','ADM'),
('QLD-018','ADM'),
('QLD-019','ADM'),
('QLD-020','ADM'),
('QLD-021','ADM'),
('QLD-022','ADM'),
('QLD-023','ADM'),
('QLD-024','ADM'),
('QLD-025','ADM'),
('QLD-026','ADM'),
('QLD-027','ADM'),
('SST-001','ADM'),
('SST-002','ADM'),
('SST-003','ADM'),
('SST-004','ADM'),
('SST-005','ADM'),
('SST-006','ADM'),
('SST-007','ADM'),
('SST-008','ADM'),
('SST-009','ADM'),
('SST-010','ADM'),
('SST-011','ADM'),
('SST-012','ADM'),
('SST-013','ADM'),
('SST-014','ADM'),
('SST-015','ADM'),
('SST-016','ADM'),
('SST-017','ADM'),
('SST-018','ADM'),
('SST-019','ADM'),
('SST-020','ADM'),
('SST-021','ADM'),
('MEL-001','ADM'),
('MEL-002','ADM'),
('MEL-003','ADM'),
('MEL-004','ADM'),
('MEL-005','ADM'),
('MEL-006','ADM'),
('MEL-007','ADM'),
('MEL-008','ADM'),
('MEL-009','ADM'),
('MEL-010','ADM'),
('MEL-011','ADM'),
('MEL-012','ADM'),
('MEL-013','ADM'),
('MEL-014','ADM'),
('MEL-015','ADM'),
('MEL-016','ADM'),
('MEL-017','ADM'),
('MEL-018','ADM'),
('MEL-019','ADM'),
('MEL-020','ADM'),
('PCP-001','ADM'),
('PCP-002','ADM'),
('PCP-003','ADM'),
('PCP-004','ADM'),
('PCP-005','ADM'),
('PCP-006','ADM'),
('PCP-007','ADM'),
('PCP-008','ADM'),
('PCP-009','ADM'),
('PCP-010','ADM'),
('MAT-001','ADM'),
('MAT-002','ADM'),
('MAT-003','ADM'),
('MAT-004','ADM'),
('MAT-005','ADM'),
('MAT-006','ADM'),
('MAT-007','ADM'),
('MAT-008','ADM'),
('MAT-009','ADM'),
('DOC-001','ADM'),
('DOC-002','ADM'),
('DOC-003','ADM'),
('DOC-004','ADM'),
('DOC-005','ADM'),
('DOC-006','ADM'),
('DOC-007','ADM'),
('DOC-008','ADM'),
('DOC-009','ADM'),
('DOC-010','ADM'),
('TST-001','ADM'),
('TST-002','ADM'),
('TST-003','ADM'),
('TST-004','ADM'),
('TST-005','ADM'),
('TST-006','ADM'),
('TST-007','ADM'),
('TST-008','ADM'),
('TST-009','ADM'),
('TST-010','ADM'),
('TST-011','ADM'),
('TST-012','ADM'),
('TST-013','ADM'),
('TST-014','ADM'),
('TST-015','ADM'),
('FAB-021-FABRICACAO-M','FAB'),
('FAB-022','FAB'),
('FAB-023','FAB');

delete from public.activity_area_links l
using public.activities a, tmp_v213_activities t
where l.activity_id=a.id and a.code=t.code;

insert into public.activity_area_links(activity_id,area_code)
select a.id,l.area_code
from tmp_v213_activity_links l
join public.activities a on a.code=l.activity_code
on conflict(activity_id,area_code) do nothing;

create temporary table tmp_v213_project_rooms (
  project_code text not null,
  room_code text not null,
  display_name text not null,
  order_index integer not null,
  active boolean not null,
  primary key(project_code,room_code)
) on commit drop;

insert into tmp_v213_project_rooms(
  project_code,room_code,display_name,order_index,active
) values
('AWS','DH','DATAHALL',0,true),
('AWS','SE','SALA ELETRICA',0,true),
('AWS','SALA-SALA-CATCHER','SALA CATCHER',0,true),
('AWS','SALA-SALA-MEDIA','SALA MEDIA',0,true),
('AWS','SALA-SALA-DE-MAQUINAS','SALA DE MAQUINAS',0,true),
('TB11','PRJ-GERAL','Geral do projeto',0,true),
('UFG','SALA-MONOBLOCO','MONOBLOCO',0,true),
('PRODEB','SALA-MONOBLOCO','MONOBLOCO',0,true),
('BARBADOS','SALA-MONOBLOCO','MONOBLOCO',0,true),
('FOR','PRJ-GERAL','Geral do projeto',0,true),
('BOG','PRJ-GERAL','Geral do projeto',0,true),
('CRUSOE','PRJ-GERAL','Geral do projeto',0,true);

create temporary table tmp_v213_project_room_modules (
  project_code text not null,
  room_code text not null,
  module_code text not null,
  display_name text not null,
  order_index integer not null,
  active boolean not null,
  primary key(project_code,room_code,module_code)
) on commit drop;

insert into tmp_v213_project_room_modules(
  project_code,room_code,module_code,display_name,order_index,active
) values
('AWS','DH','MOD1','MOD1',0,true),
('AWS','DH','MOD2','MOD2',1,true),
('AWS','DH','MOD3','MOD3',2,true),
('AWS','DH','MOD4','MOD4',3,true),
('AWS','DH','MOD5','MOD5',4,true),
('AWS','DH','MOD6','MOD6',5,true),
('AWS','DH','MOD7','MOD7',6,true),
('AWS','DH','MOD8','MOD8',7,true),
('AWS','SE','MOD1','MOD1',12,true),
('AWS','SE','MOD2','MOD2',13,true),
('AWS','SE','MOD3','MOD3',14,true),
('AWS','SE','MOD4','MOD4',15,true),
('AWS','SE','MOD5','MOD5',16,true),
('AWS','SE','MOD6','MOD6',0,true),
('AWS','SALA-SALA-CATCHER','MOD1','MOD1',1,true),
('AWS','SALA-SALA-CATCHER','MOD2','MOD2',2,true),
('AWS','SALA-SALA-CATCHER','MOD3','MOD3',3,true),
('AWS','SALA-SALA-CATCHER','MOD4','MOD4',4,true),
('AWS','SALA-SALA-CATCHER','MOD5','MOD5',5,true),
('AWS','SALA-SALA-CATCHER','MOD6','MOD6',6,true),
('AWS','SALA-SALA-MEDIA','MOD1','MOD1',7,true),
('AWS','SALA-SALA-MEDIA','MOD2','MOD2',8,true),
('AWS','SALA-SALA-MEDIA','MOD3','MOD3',9,true),
('AWS','SALA-SALA-MEDIA','MOD4','MOD4',10,true),
('AWS','SALA-SALA-MEDIA','MOD5','MOD5',11,true),
('AWS','SALA-SALA-MEDIA','MOD6','MOD6',12,true),
('AWS','SALA-SALA-DE-MAQUINAS','MOD1','MOD1',13,true),
('AWS','SALA-SALA-DE-MAQUINAS','MOD2','MOD2',14,true),
('AWS','SALA-SALA-DE-MAQUINAS','MOD3','MOD3',15,true),
('AWS','SALA-SALA-DE-MAQUINAS','MOD4','MOD4',16,true),
('AWS','SALA-SALA-DE-MAQUINAS','MOD5','MOD5',0,true),
('AWS','SALA-SALA-DE-MAQUINAS','MOD6','MOD6',1,true),
('AWS','SALA-SALA-DE-MAQUINAS','MOD7','MOD7',2,true),
('AWS','SALA-SALA-DE-MAQUINAS','MOD8','MOD8',3,true),
('TB11','PRJ-GERAL','M04','Módulo 04',4,true),
('TB11','PRJ-GERAL','M05','Módulo 05',5,true),
('TB11','PRJ-GERAL','M06','Módulo 06',6,true),
('TB11','PRJ-GERAL','M07','Módulo 07',7,true),
('TB11','PRJ-GERAL','M08','Módulo 08',8,true),
('TB11','PRJ-GERAL','M09','Módulo 09',9,true),
('TB11','PRJ-GERAL','M10','Módulo 10',10,true),
('TB11','PRJ-GERAL','M11','Módulo 11',11,true),
('TB11','PRJ-GERAL','M12','Módulo 12',12,true),
('TB11','PRJ-GERAL','M13','Módulo 13',13,true),
('TB11','PRJ-GERAL','M14','Módulo 14',14,true),
('TB11','PRJ-GERAL','M15','Módulo 15',15,true),
('TB11','PRJ-GERAL','M16','Módulo 16',16,true),
('UFG','SALA-MONOBLOCO','MOD1','MOD1',16,true),
('PRODEB','SALA-MONOBLOCO','MOD1','MOD1',16,true),
('BARBADOS','SALA-MONOBLOCO','MOD1','MOD1',16,true),
('FOR','PRJ-GERAL','MOD-GERAL','Geral do projeto',0,true),
('FOR','PRJ-GERAL','M01','Módulo 01',1,true),
('FOR','PRJ-GERAL','M02','Módulo 02',2,true),
('FOR','PRJ-GERAL','M03','Módulo 03',3,true),
('FOR','PRJ-GERAL','M04','Módulo 04',4,true),
('FOR','PRJ-GERAL','M05','Módulo 05',5,true),
('FOR','PRJ-GERAL','M06','Módulo 06',6,true),
('FOR','PRJ-GERAL','M07','Módulo 07',7,true),
('FOR','PRJ-GERAL','M08','Módulo 08',8,true),
('FOR','PRJ-GERAL','M09','Módulo 09',9,true),
('FOR','PRJ-GERAL','M10','Módulo 10',10,true),
('FOR','PRJ-GERAL','M11','Módulo 11',11,true),
('FOR','PRJ-GERAL','M12','Módulo 12',12,true),
('FOR','PRJ-GERAL','M13','Módulo 13',13,true),
('FOR','PRJ-GERAL','M14','Módulo 14',14,true),
('FOR','PRJ-GERAL','M15','Módulo 15',15,true),
('FOR','PRJ-GERAL','M16','Módulo 16',16,true),
('BOG','PRJ-GERAL','MOD-GERAL','Geral do projeto',0,true),
('BOG','PRJ-GERAL','M01','Módulo 01',1,true),
('BOG','PRJ-GERAL','M02','Módulo 02',2,true),
('BOG','PRJ-GERAL','M03','Módulo 03',3,true),
('BOG','PRJ-GERAL','M04','Módulo 04',4,true),
('BOG','PRJ-GERAL','M05','Módulo 05',5,true),
('BOG','PRJ-GERAL','M06','Módulo 06',6,true),
('BOG','PRJ-GERAL','M07','Módulo 07',7,true),
('BOG','PRJ-GERAL','M08','Módulo 08',8,true),
('BOG','PRJ-GERAL','M09','Módulo 09',9,true),
('BOG','PRJ-GERAL','M10','Módulo 10',10,true),
('BOG','PRJ-GERAL','M11','Módulo 11',11,true),
('BOG','PRJ-GERAL','M12','Módulo 12',12,true),
('BOG','PRJ-GERAL','M13','Módulo 13',13,true),
('BOG','PRJ-GERAL','M14','Módulo 14',14,true),
('BOG','PRJ-GERAL','M15','Módulo 15',15,true),
('BOG','PRJ-GERAL','M16','Módulo 16',16,true),
('CRUSOE','PRJ-GERAL','MOD-GERAL','Geral do projeto',0,true),
('CRUSOE','PRJ-GERAL','M01','Módulo 01',1,true),
('CRUSOE','PRJ-GERAL','M02','Módulo 02',2,true),
('CRUSOE','PRJ-GERAL','M03','Módulo 03',3,true),
('CRUSOE','PRJ-GERAL','M04','Módulo 04',4,true),
('CRUSOE','PRJ-GERAL','M05','Módulo 05',5,true),
('CRUSOE','PRJ-GERAL','M06','Módulo 06',6,true),
('CRUSOE','PRJ-GERAL','M07','Módulo 07',7,true),
('CRUSOE','PRJ-GERAL','M08','Módulo 08',8,true),
('CRUSOE','PRJ-GERAL','M09','Módulo 09',9,true),
('CRUSOE','PRJ-GERAL','M10','Módulo 10',10,true),
('CRUSOE','PRJ-GERAL','M11','Módulo 11',11,true),
('CRUSOE','PRJ-GERAL','M12','Módulo 12',12,true),
('CRUSOE','PRJ-GERAL','M13','Módulo 13',13,true),
('CRUSOE','PRJ-GERAL','M14','Módulo 14',14,true),
('CRUSOE','PRJ-GERAL','M15','Módulo 15',15,true),
('CRUSOE','PRJ-GERAL','M16','Módulo 16',16,true);

update public.project_rooms pr
set active=false
where pr.project_id in (
  select p.id
  from public.projects p
  join (select distinct project_code from tmp_v213_project_rooms) t
    on t.project_code=p.code
);

insert into public.project_rooms(
  project_id,room_id,display_name,order_index,active
)
select p.id,r.id,t.display_name,t.order_index,t.active
from tmp_v213_project_rooms t
join public.projects p on p.code=t.project_code
join public.rooms r on r.code=t.room_code
on conflict(project_id,room_id) do update set
  display_name=excluded.display_name,
  order_index=excluded.order_index,
  active=excluded.active;

update public.project_room_modules prm
set active=false
where prm.project_id in (
  select p.id
  from public.projects p
  join (select distinct project_code from tmp_v213_project_room_modules) t
    on t.project_code=p.code
);

insert into public.project_room_modules(
  project_id,room_id,module_id,display_name,order_index,active
)
select p.id,r.id,m.id,t.display_name,t.order_index,t.active
from tmp_v213_project_room_modules t
join public.projects p on p.code=t.project_code
join public.rooms r on r.code=t.room_code
join public.modules m on m.code=t.module_code
on conflict(project_id,room_id,module_id) do update set
  display_name=excluded.display_name,
  order_index=excluded.order_index,
  active=excluded.active;

-- Mantém a tabela antiga project_modules sincronizada para compatibilidade.
insert into public.project_modules(
  project_id,module_id,display_name,order_index,active
)
select
  p.id,
  m.id,
  max(t.display_name),
  min(t.order_index),
  bool_or(t.active)
from tmp_v213_project_room_modules t
join public.projects p on p.code=t.project_code
join public.modules m on m.code=t.module_code
group by p.id,m.id
on conflict(project_id,module_id) do update set
  display_name=excluded.display_name,
  order_index=excluded.order_index,
  active=excluded.active;


create or replace function public.aponta_validate_entry_structure_v213()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.area_code='FAB' then
    if new.sector_id is null then
      raise exception 'Selecione o setor de fabricação.';
    end if;
    new.room_id:=null;
    new.module_id:=null;
    new.panel_type_id:=null;

  elsif new.area_code='MES' then
    if new.room_id is null then
      raise exception 'Selecione a sala do projeto.';
    end if;
    if new.module_id is null then
      raise exception 'Selecione o módulo da sala.';
    end if;
    if not exists (
      select 1
      from public.project_room_modules prm
      where prm.project_id=new.project_id
        and prm.room_id=new.room_id
        and prm.module_id=new.module_id
        and prm.active=true
    ) then
      raise exception 'O módulo selecionado não está vinculado a esta sala do projeto.';
    end if;
    new.sector_id:=null;
    new.panel_type_id:=null;

  elsif new.area_code='MPA' then
    if new.panel_type_id is null then
      raise exception 'Selecione o tipo de painel.';
    end if;
    new.sector_id:=null;
    new.room_id:=null;
    new.module_id:=null;

  elsif new.area_code='MFI' then
    if new.room_id is null then
      raise exception 'Selecione a sala do projeto.';
    end if;
    if not exists (
      select 1
      from public.project_rooms pr
      where pr.project_id=new.project_id
        and pr.room_id=new.room_id
        and pr.active=true
    ) then
      raise exception 'A sala selecionada não está vinculada a este projeto.';
    end if;
    new.sector_id:=null;
    new.module_id:=null;
    new.panel_type_id:=null;

  elsif new.area_code='ADM' then
    new.sector_id:=null;
    new.room_id:=null;
    new.module_id:=null;
    new.panel_type_id:=null;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_validate_entry_structure_v213 on public.time_entries;
create trigger trg_validate_entry_structure_v213
before insert or update of project_id,area_code,sector_id,room_id,module_id,panel_type_id
on public.time_entries
for each row execute function public.aponta_validate_entry_structure_v213();

notify pgrst, 'reload schema';

-- RESUMO DA PLANILHA APLICADA:
-- Projetos: 9
-- Áreas: 5
-- Setores: 19
-- Tipos de painel: 13
-- Salas do catálogo: 80
-- Vínculos Projeto × Sala: 12
-- Vínculos Projeto × Sala × Módulo: 101
-- Atividades: 309
