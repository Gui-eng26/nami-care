-- =============================================================================
-- Migration: extrato de movimentação de estoque (Sessão #6 — DEC-036)
--
-- Tela nova, SOMENTE LEITURA, dentro da aba Estoque (alterna com "Estoque
-- atual"). Nenhuma ação de compra/ajuste/perda vive aqui. Duas RPCs, ambas
-- SECURITY INVOKER (leitura pela mesma superfície da cuidadora, sem PIN de
-- gestão — a tela é aberta a todas):
--
-- 1) extrato_consolidado_estoque(p_tipo) — visão consolidada POR CATÁLOGO
--    (DEC-035): uma linha por item de catálogo, agregando os N residentes que
--    o compartilham. Ordenada do PIOR caso pro melhor:
--      continuo — cobertura_dias (view cobertura_estoque; menor = pior)
--      sos      — distância saldo − estoque_minimo (mais negativa = pior)
--    Quando 2+ residentes compartilham o item, o PIOR valor do grupo decide a
--    posição da linha. Item de residente/medicamento inativo não entra no
--    cálculo de urgência (valor nulo) — aparece com selo, sem alerta (DEC-029).
--    O array de residentes vem ordenado pior-primeiro (ativos antes de
--    inativos) para o cliente exibir o drill-down sem reordenar.
--
-- 2) extrato_medicamento(p_medicamento_id, p_inicio, p_fim, p_subtipos) — as
--    movimentacoes_estoque de UM medicamento no período (fuso da casa), mais
--    recente primeiro. O subtipo é derivado no banco — atenção ao ajuste de
--    contagem, que é entrada OU saída conforme o SINAL da quantidade daquela
--    linha (nunca só pelo campo tipo). O filtro por subtipo combina com o
--    período. Cor por direção (sinal) é apresentação do cliente.
--
-- Fonte reaproveitada: cobertura_estoque e saldo_estoque (Sessões #1/#4) — o
-- saldo/cobertura NÃO é recalculado aqui. As RPCs de compra/ajuste/perda, o
-- trigger de baixa e movimentacoes_estoque continuam INTOCADOS.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- extrato_consolidado_estoque — lista por catálogo, pior caso do grupo à frente.
-- -----------------------------------------------------------------------------
create or replace function public.extrato_consolidado_estoque(p_tipo text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_itens jsonb;
begin
  if p_tipo not in ('continuo', 'sos') then
    return jsonb_build_object('ok', false, 'erro', 'tipo_invalido');
  end if;

  with base as (
    select
      c.medicamento_id, c.idoso_id, c.nome_idoso, c.idoso_ativo,
      c.tipo, c.ativo, c.saldo, c.estoque_minimo, c.cobertura_dias,
      c.alerta_reposicao, c.sugestao_compra, m.catalogo_id,
      (c.ativo and c.idoso_ativo) as item_ativo,
      -- Valor de urgência (menor = pior); nulo quando não se aplica alerta
      -- (item inativo, ou SOS sem mínimo) → ordena por último (nulls last).
      case
        when not (c.ativo and c.idoso_ativo) then null
        when c.tipo = 'continuo' then c.cobertura_dias
        when c.estoque_minimo is null then null
        else c.saldo - c.estoque_minimo
      end as valor_urgencia
    from public.cobertura_estoque c
    join public.medicamentos m on m.id = c.medicamento_id
    where c.tipo = p_tipo
  ),
  grupos as (
    select
      catalogo_id,
      count(*) as n_residentes,
      count(*) filter (where item_ativo) as n_ativos,
      min(valor_urgencia) as pior_valor,
      bool_or(alerta_reposicao) as algum_alerta,
      jsonb_agg(
        jsonb_build_object(
          'medicamento_id', medicamento_id,
          'idoso_id', idoso_id,
          'nome_idoso', nome_idoso,
          'item_ativo', item_ativo,
          'medicamento_ativo', ativo,
          'idoso_ativo', idoso_ativo,
          'saldo', saldo,
          'estoque_minimo', estoque_minimo,
          'cobertura_dias', cobertura_dias,
          'alerta_reposicao', alerta_reposicao,
          'sugestao_compra', sugestao_compra
        )
        order by item_ativo desc, valor_urgencia asc nulls last, nome_idoso
      ) as residentes
    from base
    group by catalogo_id
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'catalogo_id', g.catalogo_id,
      'nome', cat.nome,
      'dosagem', cat.dosagem,
      'forma_farmaceutica', cat.forma_farmaceutica,
      'tipo', p_tipo,
      'n_residentes', g.n_residentes,
      'n_ativos', g.n_ativos,
      'algum_alerta', g.algum_alerta,
      'residentes', g.residentes
    )
    order by g.pior_valor asc nulls last, cat.nome
  ), '[]'::jsonb)
  into v_itens
  from grupos g
  join public.catalogo_medicamentos cat on cat.id = g.catalogo_id;

  return jsonb_build_object('ok', true, 'tipo', p_tipo, 'itens', v_itens);
end;
$$;

revoke execute on function public.extrato_consolidado_estoque(text) from public, anon;

-- -----------------------------------------------------------------------------
-- extrato_medicamento — movimentações de um medicamento no período.
-- Subtipos (para o filtro combinável com o calendário):
--   compra        entrada_compra
--   dose          saida_administracao
--   perda         perda
--   ajuste_mais   ajuste_contagem com quantidade > 0  (recontagem pra cima)
--   ajuste_menos  ajuste_contagem com quantidade < 0  (recontagem pra baixo)
-- p_subtipos nulo = todos.
-- -----------------------------------------------------------------------------
create or replace function public.extrato_medicamento(
  p_medicamento_id uuid,
  p_inicio         date,
  p_fim            date,
  p_subtipos       text[] default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_ini  timestamptz;
  v_fim  timestamptz;
  v_med  record;
  v_movs jsonb;
begin
  if p_inicio is null or p_fim is null or p_fim < p_inicio then
    return jsonb_build_object('ok', false, 'erro', 'periodo_invalido');
  end if;

  select c.medicamento_id, c.nome, c.dosagem, c.forma_farmaceutica, c.tipo,
         c.ativo, c.idoso_id, c.nome_idoso, c.idoso_ativo, c.saldo
    into v_med
    from public.cobertura_estoque c
   where c.medicamento_id = p_medicamento_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'medicamento_nao_encontrado');
  end if;

  -- Período = [início 00:00, fim+1 00:00) no fuso da casa (DEC-023).
  v_ini := p_inicio::timestamp at time zone public.fn_fuso_casa();
  v_fim := (p_fim + 1)::timestamp at time zone public.fn_fuso_casa();

  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', x.id,
             'tipo', x.tipo,
             'subtipo', x.subtipo,
             'quantidade', x.quantidade,
             'motivo', x.motivo,
             'criado_em', x.criado_em,
             'cuidador', x.cuidador
           ) order by x.criado_em desc), '[]'::jsonb)
    into v_movs
  from (
    select me.id, me.tipo, me.quantidade, me.motivo, me.criado_em,
           cu.nome as cuidador,
           case
             when me.tipo = 'entrada_compra'      then 'compra'
             when me.tipo = 'saida_administracao' then 'dose'
             when me.tipo = 'perda'               then 'perda'
             when me.tipo = 'ajuste_contagem' and me.quantidade > 0 then 'ajuste_mais'
             else 'ajuste_menos'
           end as subtipo
    from public.movimentacoes_estoque me
    left join public.cuidadores cu on cu.id = me.cuidador_id
    where me.medicamento_id = p_medicamento_id
      and me.criado_em >= v_ini
      and me.criado_em <  v_fim
  ) x
  where p_subtipos is null or x.subtipo = any (p_subtipos);

  return jsonb_build_object(
    'ok', true,
    'medicamento', jsonb_build_object(
      'medicamento_id', v_med.medicamento_id,
      'nome', v_med.nome,
      'dosagem', v_med.dosagem,
      'forma_farmaceutica', v_med.forma_farmaceutica,
      'tipo', v_med.tipo,
      'ativo', v_med.ativo,
      'idoso_id', v_med.idoso_id,
      'nome_idoso', v_med.nome_idoso,
      'idoso_ativo', v_med.idoso_ativo,
      'saldo', v_med.saldo
    ),
    'movimentacoes', v_movs
  );
end;
$$;

revoke execute on function
  public.extrato_medicamento(uuid, date, date, text[])
  from public, anon;
