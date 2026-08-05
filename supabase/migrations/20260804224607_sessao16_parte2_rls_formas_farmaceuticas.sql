-- Complemento da Parte 2 (DEC-054): RLS de formas_farmaceuticas.
--
-- Toda tabela nova no projeto nasce com RLS ligado por padrão (hardening da
-- Sessão #1/#2) e sem nenhuma policy — leitura fica bloqueada em silêncio (RLS
-- filtra, não dá erro), foi assim que o <select> de forma farmacêutica no
-- cadastro apareceu vazio no teste manual desta sessão. Mesma policy de
-- leitura que todo catálogo/tabela de referência do projeto já usa.

create policy formas_farmaceuticas_select_autenticado
  on public.formas_farmaceuticas
  for select
  to authenticated
  using (true);
