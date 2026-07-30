# Aponta P3 v2.18.3 — Carga completa das áreas

- Corrigido o limite de 1.000 registros na leitura dos vínculos entre atividades e áreas.
- Com centenas de atividades e múltiplas áreas, a consulta anterior era truncada.
- O truncamento fazia algumas áreas aparecerem em branco depois de editar outra atividade.
- Nova função retorna uma linha por atividade com todas as áreas em um array.
- A tela transforma o resultado agrupado nos vínculos utilizados pelo aplicativo.
- Vínculos duplicados são removidos localmente.
- A edição de uma atividade não interfere na exibição das demais.
- Cadastro de áreas, filtros, upload e download foram preservados.
