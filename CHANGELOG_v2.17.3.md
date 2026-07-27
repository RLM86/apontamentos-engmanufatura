# Aponta P3 v2.17.3 — MONOBLOCO sem partes

- Ao selecionar uma sala MONOBLOCO no apontamento estrutural, o campo Parte do módulo é ocultado.
- O sistema não exige parte inferior ou superior para MONOBLOCO.
- O apontamento de MONOBLOCO grava `module_part` vazio.
- A atividade passa da etapa 6 para a etapa 5 quando a sala é MONOBLOCO.
- No cadastro e na edição dos módulos de MONOBLOCO, os controles Inferior/Superior ficam ocultos.
- Módulos novos de MONOBLOCO são gravados sem partes.
- Na tabela de módulos, a coluna Partes mostra “Não se aplica”.
- Não exige novo SQL.
