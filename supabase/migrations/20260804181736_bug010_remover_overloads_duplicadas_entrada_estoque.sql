-- BUG-010: a migration da Sessao 15 acrescentou p_gotas_por_ml via
-- "create or replace", o que em Postgres cria uma sobrecarga nova em vez de
-- substituir. As versoes antigas sobreviveram. Com duas sobrecargas expostas,
-- o PostgREST nao consegue escolher a candidata e devolve erro HTTP, o que o
-- frontend traduz como "Falha de conexao" — inviabilizando todo registro de
-- compra de estoque.
--
-- A propria migration da Sessao 15 fez o drop correspondente em
-- criar_medicamento e atualizar_medicamento; foi omitido apenas aqui.
--
-- Seguranca: DDL puro. Nenhuma linha de tabela e lida, alterada ou removida.
-- fn_registrar_lote_entrada de 7 argumentos e chamada por
-- registrar_ajuste_estoque; a versao de 8 argumentos tem
-- p_gotas_por_ml DEFAULT NULL, entao a chamada passa a resolver para ela
-- sem mudanca de comportamento.

drop function if exists public.registrar_entrada_estoque(uuid, numeric, date, text, date, text);

drop function if exists public.fn_registrar_lote_entrada(uuid, uuid, text, date, numeric, date, text);
