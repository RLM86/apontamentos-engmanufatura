# Aponta P3 v2.11 — Aprovação de Inscrições

## Novo fluxo

1. O usuário cria a própria conta.
2. A inscrição entra como **Pendente**.
3. O usuário consegue entrar no sistema, mas não pode registrar horas.
4. Gestor ou Administrador analisa a inscrição na aba **Equipe**.
5. Ao aprovar, o usuário é liberado imediatamente para apontamentos.
6. Ao rejeitar, o acesso aos apontamentos permanece bloqueado.

## Segurança

- A restrição foi aplicada na interface e no banco Supabase.
- Usuários pendentes ou rejeitados não conseguem inserir apontamentos por chamadas diretas.
- Gestores podem analisar inscrições de Colaboradores.
- Administradores podem analisar todos e continuam responsáveis por perfil, jornada, ativação e exclusão.

## Configuração obrigatória

No Supabase, desative **Confirm email** em:

`Authentication → Providers → Email → Confirm email`

Isso evita o e-mail de confirmação e permite que a aprovação seja feita dentro do Aponta P3.
