-- =============================================================================
-- Migration: lote e validade visíveis no estoque atual e no extrato (DEC-043)
--
-- 1) lotes_estoque_vivo — view dos lotes com saldo > 0 (a prateleira), lida
--    diretamente pela aba "Estoque atual" para exibir, por medicamento, cada
--    lote com sua validade e saldo, ordenados por validade crescente (o próximo
--    a vencer em destaque). security_invoker: respeita o RLS de lotes_estoque.
--
-- 2) extrato_medicamento passa a devolver, em cada movimentação, o(s) lote(s)
--    afetado(s) (reaproveitando o vínculo movimentacao_lote): a entrada mostra o
--    lote/validade que criou; a saída, o(s) lote(s) de onde saiu (com a
--    quantidade tirada de cada). Ordenados por validade. Resto da RPC intocado.
-- =============================================================================

create view public.lotes_estoque_vivo
  with (security_invoker = true)
as
select
  l.id,
  l.medicamento_id,
  l.lote,
  l.validade,
  l.saldo_atual,
  l.quantidade_inicial,
  l.data_entrada,
  l.origem,
  l.criado_em
from public.lotes_estoque l
where l.saldo_atual > 0;

-- -----------------------------------------------------------------------------
-- extrato_medicamento — igual à versão da Sessão #6, agora com 'lotes' por
-- movimentação. A quantidade do vínculo vem com o sinal do ledger (entrada > 0,
-- saída < 0); o cliente mostra o valor absoluto por lote.
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
             'cuidador', x.cuidador,
             'lotes', x.lotes
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
           end as subtipo,
           (
             select coalesce(jsonb_agg(
                      jsonb_build_object(
                        'lote', l.lote,
                        'validade', l.validade,
                        'quantidade', ml.quantidade
                      ) order by l.validade asc, l.data_entrada asc), '[]'::jsonb)
             from public.movimentacao_lote ml
             join public.lotes_estoque l on l.id = ml.lote_id
             where ml.movimentacao_id = me.id
           ) as lotes
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
