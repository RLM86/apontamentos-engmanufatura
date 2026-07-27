# Aponta P3 Modular v2.9

## Relatórios de equipe

- Relatórios agora possuem duas visões: **Projetos e horas** e **Equipe: horas, férias e afastamentos**.
- Filtros por colaborador, período e tipo de ausência.
- Resumo por colaborador com horas apontadas e dias de férias, atestados, afastamentos/licenças, folgas e outros.
- Detalhamento dos períodos que cruzam o intervalo selecionado.
- Indicadores de horas, férias, dias afastados e colaboradores com ocorrência.
- Exportação do resumo e do detalhamento em CSV.
- Mantido o controle de acesso por perfil e pelas políticas RLS do Supabase.

## Compatibilidade

- Não exige novo SQL quando o banco já recebeu a atualização v2.8.
- Mantém o `config.js` e a conexão Supabase da versão anterior.
- Cache PWA atualizado para v2.9.
- Pacote inclui a correção mais recente da função de backup e o configurador limpo do agente.
