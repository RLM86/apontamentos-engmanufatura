# Aponta P3 Modular v2.10

## Aprovação de férias e afastamentos

- Todo novo período é criado com situação **Pendente**.
- Gestor ou Administrador possui o botão **Aprovar**.
- Após a aprovação, o colaborador não consegue mais editar nem excluir.
- Gestores e Administradores continuam podendo editar ou excluir registros aprovados.
- Registros anteriores à atualização são marcados como aprovados automaticamente.
- A aba possui filtro e coluna de situação da aprovação.
- O relatório de equipe também mostra se o período está pendente ou aprovado.
- A proteção foi aplicada na tela, nas funções RPC, nas políticas RLS e em gatilhos do banco.

## Instalação

1. Faça backup.
2. Execute `ATUALIZAR_BANCO_v2.10_APROVACAO_FERIAS_AFASTAMENTOS.sql` no SQL Editor do Supabase.
3. Publique os arquivos atualizados no Netlify.
4. Pressione `Ctrl + F5`.
