-- APONT MAN P3 v2.19.25 - VALIDACAO ATIVIDADE MACRO

-- 1. As seis macros
SELECT id, codigo, nome
FROM macro_atividades
ORDER BY id;

-- 2. As 18 disciplinas e suas macros
SELECT
    d.disciplina,
    m.codigo AS macro_codigo,
    m.nome AS atividade_macro
FROM disciplina_macro_map d
JOIN macro_atividades m
  ON m.id = d.macro_atividade_id
ORDER BY m.id, d.disciplina;

-- 3. Deve retornar 0
SELECT COUNT(*) AS atividades_sem_macro
FROM activities
WHERE macro_atividade_id IS NULL;

-- 4. Conferencia pronta para Power BI
SELECT
    a.id,
    a.code AS codigo,
    a.name AS atividade,
    a.discipline_name AS disciplina,
    m.codigo AS macro_codigo,
    m.nome AS atividade_macro,
    a.nature,
    a.active
FROM activities a
LEFT JOIN macro_atividades m
  ON m.id = a.macro_atividade_id
ORDER BY m.id, a.discipline_name, a.name;
