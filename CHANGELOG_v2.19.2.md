# Aponta Horas v2.19.2 — Correção da redefinição de senha

- O link de recuperação passa a usar sempre o endereço principal atual.
- Removida dependência do domínio antigo `rmacedo.workers.dev`.
- Mantidos o endereço principal e o endereço secundário.
- Corrigido o marcador antigo `build=2120` para `build=2192`.
- Melhorada a mensagem enviada ao usuário após solicitar recuperação.
- Melhorada a mensagem para links inválidos ou expirados.
- Não exige alteração nas tabelas do banco.
- Exige conferência das URLs em Authentication → URL Configuration no Supabase.
