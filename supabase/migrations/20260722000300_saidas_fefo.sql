-- =============================================================================
-- Migration: saídas por FEFO automático (DEC-042)
--
-- Três caminhos de SAÍDA — dose administrada (baixa automática), ajuste de
-- recontagem para baixo, e perda — passam a ABATER POR FEFO: sempre do lote de
-- validade mais próxima primeiro, varrendo múltiplos lotes quando a quantidade
-- excede o saldo do lote da frente (fn_consumir_fefo — DEC-040). Empate de
-- validade desempata por data_entrada (FIFO secundário), depois criado_em.
--
-- A RONDA NÃO MUDA (DEC-008 preservada, agora estendida para FEFO): a cuidadora
-- segue marcando tomado/recusado/não-tomado; a baixa por lote é automática e
-- silenciosa — nenhuma escolha de lote, nenhum menu de inventário na ronda. O
-- caso "0,5 restante" se resolve sozinho: o FEFO tira 0,5 do lote velho (zera) e
-- 0,5 do próximo para completar 1, sem menu, sem órfão.
--
-- O ledger continua sendo escrito com UMA movimentação por saída (forma
-- intocada — extrato/adesão/cobertura leem dele); o FEFO distribui essa
-- movimentação pelos lotes via movimentacao_lote, na MESMA transação.
--
-- fn_consumir_fefo é best-effort (ver DEC-040): se a dose excede o físico
-- (medicamento sem estoque, super-administração), a movimentação de saída é
-- gravada cheia e os lotes piso em zero — a ronda nunca falha. Recontagem para
-- baixo e perda nunca excedem o físico por construção (a quantidade sai do
-- próprio saldo contado/existente), então cobrem sempre por completo.
--
-- Ajuste de recontagem: agora compara a contagem física contra o SALDO DOS
-- LOTES (a prateleira), não mais contra a soma do ledger. Para CIMA cria um lote
-- novo (origem remanescente) exigindo validade — a unidade "a mais" pertence a
-- algum lote físico que a casa tem em mãos (lote pode ser "não identificado",
-- mas a validade é informada — DEC-041). Para BAIXO abate por FEFO.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Trigger de baixa automática (DEC-008 → estendida para FEFO). A movimentação de
-- saída é criada como antes; em seguida fn_consumir_fefo distribui a quantidade
-- pelos lotes por validade. nao_tomado: nenhuma movimentação (inalterado).
-- -----------------------------------------------------------------------------
create or replace function public.fn_baixa_automatica_estoque()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if new.status in ('tomado_no_horario', 'tomado_atrasado') then
    insert into public.movimentacoes_estoque
      (medicamento_id, cuidador_id, administracao_id, tipo, quantidade, motivo, criado_em)
    values
      (new.medicamento_id, new.cuidador_id, new.id, 'saida_administracao',
       -new.qtd, 'Baixa automática — dose administrada', new.registrado_em)
    returning id into v_id;
    perform public.fn_consumir_fefo(new.medicamento_id, v_id, new.qtd);

  elsif new.status = 'recusado' then
    insert into public.movimentacoes_estoque
      (medicamento_id, cuidador_id, administracao_id, tipo, quantidade, motivo, criado_em)
    values
      (new.medicamento_id, new.cuidador_id, new.id, 'perda',
       -new.qtd, 'Perda — dose recusada pelo idoso (DEC-009)', new.registrado_em)
    returning id into v_id;
    perform public.fn_consumir_fefo(new.medicamento_id, v_id, new.qtd);
  end if;
  -- nao_tomado: nenhuma movimentação
  return new;
end;
$$;

revoke execute on function public.fn_baixa_automatica_estoque()
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- registrar_perda_estoque — abate por FEFO (validade mais próxima primeiro).
-- Assinatura inalterada; só o corpo ganha a distribuição por lote e passa a ler
-- o saldo dos lotes. A perda nunca excede o físico (a cuidadora só descarta o
-- que existe), então o FEFO cobre por completo.
-- -----------------------------------------------------------------------------
create or replace function public.registrar_perda_estoque(
  p_medicamento_id uuid,
  p_quantidade     numeric,
  p_motivo         text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cuidador uuid;
  v_id       uuid;
  v_saldo    numeric;
begin
  v_cuidador := public.fn_cuidador_do_turno();
  if v_cuidador is null then
    return jsonb_build_object('ok', false, 'erro', 'sem_turno_aberto');
  end if;
  if not exists (select 1 from public.medicamentos where id = p_medicamento_id) then
    return jsonb_build_object('ok', false, 'erro', 'medicamento_nao_encontrado');
  end if;
  if p_quantidade is null or p_quantidade <= 0 or mod(p_quantidade * 2, 1) <> 0 then
    return jsonb_build_object('ok', false, 'erro', 'qtd_invalida');
  end if;
  if nullif(trim(coalesce(p_motivo, '')), '') is null then
    return jsonb_build_object('ok', false, 'erro', 'motivo_obrigatorio');
  end if;

  insert into public.movimentacoes_estoque
    (medicamento_id, cuidador_id, tipo, quantidade, motivo)
  values
    (p_medicamento_id, v_cuidador, 'perda', -p_quantidade, trim(p_motivo))
  returning id into v_id;

  perform public.fn_consumir_fefo(p_medicamento_id, v_id, p_quantidade);

  select coalesce(sum(saldo_atual), 0) into v_saldo
    from public.lotes_estoque where medicamento_id = p_medicamento_id;

  return jsonb_build_object('ok', true, 'movimentacao_id', v_id, 'saldo', v_saldo);
end;
$$;

revoke execute on function
  public.registrar_perda_estoque(uuid, numeric, text)
  from public, anon;

-- -----------------------------------------------------------------------------
-- registrar_ajuste_estoque — recontagem física contra o SALDO DOS LOTES.
--   diferença > 0 (para cima): cria um lote novo (origem remanescente) com o
--     excedente; exige p_validade (a unidade a mais pertence a um lote físico —
--     lote pode ser nulo/"não identificado"). DEC-041.
--   diferença < 0 (para baixo): abate |diferença| por FEFO. DEC-042.
--   diferença = 0: sem movimentação ({sem_diferenca: true}).
-- Assinatura muda (ganha p_lote/p_validade) → drop + recreate.
-- -----------------------------------------------------------------------------
drop function public.registrar_ajuste_estoque(uuid, numeric, text);

create or replace function public.registrar_ajuste_estoque(
  p_medicamento_id     uuid,
  p_quantidade_contada numeric,
  p_observacao         text default null,
  p_lote               text default null,
  p_validade           date default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cuidador  uuid;
  v_saldo     numeric;
  v_diferenca numeric;
  v_motivo    text;
  v_id        uuid;
begin
  v_cuidador := public.fn_cuidador_do_turno();
  if v_cuidador is null then
    return jsonb_build_object('ok', false, 'erro', 'sem_turno_aberto');
  end if;
  if not exists (select 1 from public.medicamentos where id = p_medicamento_id) then
    return jsonb_build_object('ok', false, 'erro', 'medicamento_nao_encontrado');
  end if;
  if p_quantidade_contada is null or p_quantidade_contada < 0
     or mod(p_quantidade_contada * 2, 1) <> 0 then
    return jsonb_build_object('ok', false, 'erro', 'qtd_invalida');
  end if;

  -- Saldo atual = a prateleira (soma dos lotes), que é o que se está recontando.
  select coalesce(sum(saldo_atual), 0) into v_saldo
    from public.lotes_estoque where medicamento_id = p_medicamento_id;

  v_diferenca := p_quantidade_contada - v_saldo;
  if v_diferenca = 0 then
    return jsonb_build_object('ok', true, 'sem_diferenca', true, 'saldo', v_saldo);
  end if;

  -- Recontagem para cima precisa de validade: o excedente é um lote físico.
  if v_diferenca > 0 and p_validade is null then
    return jsonb_build_object('ok', false, 'erro', 'validade_obrigatoria');
  end if;

  v_motivo := format('Contagem física: sistema %s, contado %s',
                     case when mod(v_saldo, 1) = 0 then trunc(v_saldo)::text
                          else to_char(v_saldo, 'FM9999990.0') end,
                     case when mod(p_quantidade_contada, 1) = 0
                          then trunc(p_quantidade_contada)::text
                          else to_char(p_quantidade_contada, 'FM9999990.0') end);
  if nullif(trim(coalesce(p_observacao, '')), '') is not null then
    v_motivo := v_motivo || ' — ' || trim(p_observacao);
  end if;

  insert into public.movimentacoes_estoque
    (medicamento_id, cuidador_id, tipo, quantidade, motivo)
  values
    (p_medicamento_id, v_cuidador, 'ajuste_contagem', v_diferenca, v_motivo)
  returning id into v_id;

  if v_diferenca > 0 then
    -- Excedente vira um lote novo (remanescente na prateleira).
    perform public.fn_registrar_lote_entrada(
      p_medicamento_id, v_id, p_lote, p_validade, v_diferenca,
      (now() at time zone public.fn_fuso_casa())::date, 'remanescente');
  else
    -- Faltou: abate |diferença| por FEFO (sempre coberto, |dif| <= saldo).
    perform public.fn_consumir_fefo(p_medicamento_id, v_id, -v_diferenca);
  end if;

  return jsonb_build_object('ok', true, 'sem_diferenca', false,
                            'movimentacao_id', v_id, 'diferenca', v_diferenca,
                            'saldo', p_quantidade_contada);
end;
$$;

revoke execute on function
  public.registrar_ajuste_estoque(uuid, numeric, text, text, date)
  from public, anon;
