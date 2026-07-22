-- =============================================================================
-- Migration: entradas com lote e validade (DEC-041)
--
-- Três caminhos de ENTRADA capturam agora lote + validade + quantidade (e data
-- de entrada, default hoje):
--   1. "+ Medicamento" (estoque inicial do cadastro) — origem compra OU
--      remanescente. Passa pelas RPCs abaixo via src/lib/estoqueInicial.js, sem
--      RPC nova: compra → registrar_entrada_estoque; remanescente →
--      registrar_ajuste_estoque (recontagem para cima).
--   2. Recompra / reposição — registrar_entrada_estoque.
--   3. Ajuste de recontagem PARA CIMA — registrar_ajuste_estoque (na migration
--      de saídas, que também trata o para-baixo por FEFO).
--
-- Aqui: registrar_entrada_estoque ganha p_validade (obrigatória) e p_lote
-- (opcional — código impresso na caixa; nulo = não informado). Cria a linha em
-- lotes_estoque JUNTO com a movimentação de entrada, na mesma transação, via o
-- helper fn_registrar_lote_entrada (DEC-040). Origem sempre 'compra' (o tipo da
-- movimentação continua entrada_compra — DEC-016).
--
-- Decisão menor (documentada): validade NO PASSADO é aceita. Um remanescente
-- pode entrar já perto/na validade, e não há alerta de vencimento nesta sessão
-- (o ajuste é manual). Bloquear seria inventar regra que o roteiro não pediu.
-- =============================================================================

drop function public.registrar_entrada_estoque(uuid, numeric, date, text);

create or replace function public.registrar_entrada_estoque(
  p_medicamento_id uuid,
  p_quantidade     numeric,
  p_validade       date,
  p_lote           text default null,
  p_data           date default null,
  p_observacao     text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cuidador  uuid;
  v_med       public.medicamentos;
  v_hoje      date := (now() at time zone public.fn_fuso_casa())::date;
  v_data      date := coalesce(p_data, (now() at time zone public.fn_fuso_casa())::date);
  v_criado_em timestamptz;
  v_id        uuid;
  v_lote_id   uuid;
  v_saldo     numeric;
begin
  v_cuidador := public.fn_cuidador_do_turno();
  if v_cuidador is null then
    return jsonb_build_object('ok', false, 'erro', 'sem_turno_aberto');
  end if;

  select * into v_med from public.medicamentos where id = p_medicamento_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'medicamento_nao_encontrado');
  end if;
  if not v_med.ativo then
    return jsonb_build_object('ok', false, 'erro', 'medicamento_inativo');
  end if;
  if p_quantidade is null or p_quantidade <= 0 or mod(p_quantidade * 2, 1) <> 0 then
    return jsonb_build_object('ok', false, 'erro', 'qtd_invalida');
  end if;
  if p_validade is null then
    return jsonb_build_object('ok', false, 'erro', 'validade_obrigatoria');
  end if;
  if v_data > v_hoje then
    return jsonb_build_object('ok', false, 'erro', 'data_futura');
  end if;

  v_criado_em := case when v_data = v_hoje then now()
                      else (v_data::timestamp + interval '12 hours')
                             at time zone public.fn_fuso_casa() end;

  insert into public.movimentacoes_estoque
    (medicamento_id, cuidador_id, tipo, quantidade, motivo, criado_em)
  values
    (p_medicamento_id, v_cuidador, 'entrada_compra', p_quantidade,
     nullif(trim(coalesce(p_observacao, '')), ''), v_criado_em)
  returning id into v_id;

  -- Lote físico criado JUNTO com a movimentação (atomicidade — DEC-040).
  v_lote_id := public.fn_registrar_lote_entrada(
    p_medicamento_id, v_id, p_lote, p_validade, p_quantidade, v_data, 'compra');

  select coalesce(sum(saldo_atual), 0) into v_saldo
    from public.lotes_estoque where medicamento_id = p_medicamento_id;

  return jsonb_build_object('ok', true, 'movimentacao_id', v_id,
                            'lote_id', v_lote_id, 'saldo', v_saldo);
end;
$$;

revoke execute on function
  public.registrar_entrada_estoque(uuid, numeric, date, text, date, text)
  from public, anon;
