# Aponta P3 v2.17.7 — Gestão da lista de atividades

- Ferramentas disponíveis somente para Administrador.
- Seleção individual e seleção de todas as atividades visíveis.
- Inativação em massa.
- Exclusão em massa por função segura no Supabase.
- Atividades com apontamentos não são excluídas.
- Download da lista atual em Excel.
- Excel inclui ID, código, atividade, disciplina, natureza, áreas, orientação e status.
- Upload do Excel para atualizar atividades existentes e criar novas.
- O ID identifica atividades existentes; ID vazio cria uma nova.
- Códigos com EM- são normalizados automaticamente.
- Observação permanece opcional.
- Linhas removidas do Excel não são excluídas automaticamente.
- Upload validado e processado em uma transação no Supabase.
