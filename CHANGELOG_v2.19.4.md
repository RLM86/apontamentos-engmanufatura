# Aponta Horas v2.19.4 — Erros claros na recuperação de senha

- Corrigida a exibição de erro `{}`.
- O sistema passa a interpretar código, status e mensagem retornados pelo Supabase.
- Mensagens específicas para:
  - limite de envio de e-mails;
  - falha de conexão;
  - URL de redirecionamento não autorizada;
  - falha de SMTP;
  - e-mail inválido;
  - usuário não localizado.
- Adicionado código técnico quando o servidor não fornece descrição.
- Mantida a página própria de criação da nova senha.
- Não exige SQL.
