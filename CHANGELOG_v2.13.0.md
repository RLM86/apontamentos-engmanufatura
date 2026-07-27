# Aponta P3 v2.13.0 — Estrutura Projeto, Sala e Módulo

## Fluxo de apontamento
- Projeto
- Área
- Fabricação: Setor
- Montagem Estrutural: Sala do projeto e depois Módulo da sala
- Montagem de Painéis: Tipo de painel
- Montagem Final: Sala do projeto
- Administrativo: sem campo intermediário
- Atividade, data, horas e observação

## Banco de dados
- Nova tabela `project_rooms`
- Nova tabela `project_room_modules`
- Validação no banco para impedir módulo de uma sala diferente
- Dados da planilha revisada incorporados
- Backup atualizado para incluir os novos vínculos

## Cadastros em três subabas
1. Cadastros gerais
2. Referências por área
3. Estrutura por projeto
