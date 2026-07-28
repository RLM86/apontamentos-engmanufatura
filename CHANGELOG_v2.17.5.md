# Aponta P3 v2.17.5

## Importação
- Corrigida a importação para a estrutura atual de projetos, atividades e apontamentos.
- Apontamentos importados recebem a área Administrativo.
- Atividades importadas recebem observação opcional e informações mínimas exigidas.
- Horas acima de 24 são ignoradas como inválidas.
- Lotes com erro são verificados registro por registro.
- A mensagem informa a etapa, o registro e o erro real do Supabase.
- Removida a mensagem antiga sobre SQL 2.6.

## Exclusão múltipla
- Caixa de seleção em cada apontamento editável.
- Selecionar todos os apontamentos editáveis visíveis.
- Limpar seleção.
- Excluir vários apontamentos de uma vez.
- Registros bloqueados por aprovação ou fechamento não são apagados.
- O sistema informa quantos foram excluídos e quantos foram bloqueados.
