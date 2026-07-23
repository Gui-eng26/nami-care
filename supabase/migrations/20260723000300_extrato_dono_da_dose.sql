-- =============================================================================
-- Migration: dono da dose no extrato + leitura unificada do ledger
-- (Sessão #13 — DEC-049)
--
-- Duas coisas ligadas pela mesma causa.
--
-- (a) No extrato de um medicamento DA CASA, a baixa aparece com data, hora,
--     cuidadora, lote e validade — mas não com QUEM TOMOU. É justamente a
--     informação que a DEC-045 passou a gravar. O estoque compartilhado não
--     criou o problema; tornou-o visível.
--
-- (b) O extrato existia em DUAS TELAS QUE LIAM O LEDGER POR CAMINHOS
--     DIFERENTES: `FichaEstoque` lia `movimentacoes_estoque` direto pelo
--     PostgREST (últimas 50, sem período, rotulando por `tipo`), e
--     `ExtratoMovimentacoes` lia por esta RPC (com período e filtro, rotulando
--     por `subtipo`). Um ajuste de contagem para baixo lia "Ajuste de contagem"
--     numa tela e "Ajuste de contagem (a menos)" na outra. E pelo caminho
--     direto, resolver o `coalesce` do dono e o teste de sentinela exigiria a
--     regra EM JAVASCRIPT — contra a convenção de manter regra no banco.
--
-- Decisão: unificar. A ficha passa a consumir esta mesma RPC, que ganha o que
-- faltava para atendê-la — PERÍODO OPCIONAL:
--     ambos nulos      → sem recorte de data, últimas 50 (comportamento da ficha)
--     ambos preenchidos→ como hoje
--     um só nulo       → periodo_invalido (meio período é engano, não intenção)
--
-- E o campo novo `residente`, preenchido SÓ quando a movimentação é baixa por
-- dose tomada (`subtipo = 'dose'`, com `administracao_id`) E o medicamento é da
-- casa. Em medicamento vinculado a um residente o campo seria redundante — o
-- cabeçalho da tela já diz de quem é. Compra, ajuste, perda e perda por recusa
-- nunca mostram residente.
--
-- Tudo o mais é preservado: subtipo derivado pelo SINAL da quantidade, filtro
-- combinável, `lotes` por movimentação (DEC-043), bloco `medicamento`.
--
-- O drop antes do create é necessário: a assinatura antiga tinha os quatro
-- parâmetros obrigatórios; sem removê-la ficariam duas versões concorrendo.
-- Somente leitura — nenhuma escrita no ledger, nenhuma mudança de schema.
-- =============================================================================

drop function if exists public.extrato_medicamento(uuid, date, date, text[]);

create function public.extrato_medicamento(
  p_medicamento_id uuid,
  p_inicio         date default null,
  p_fim            date default null,
  p_subtipos       text[] default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_ini     timestamptz;
  v_fim     timestamptz;
  v_med     record;
  v_da_casa boolean;
  v_movs    jsonb;
begin
  -- Período é tudo-ou-nada: os dois nulos (a ficha) ou os dois preenchidos (o
  -- extrato com calendário). Um só preenchido é engano de chamada.
  if (p_inicio is null) <> (p_fim is null) then
    return jsonb_build_object('ok', false, 'erro', 'periodo_invalido');
  end if;
  if p_inicio is not null and p_fim < p_inicio then
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

  -- O medicamento é da caixa comum? Decide, sozinho, se o residente aparece.
  select coalesce(i.eh_sentinela, false) into v_da_casa
    from public.idosos i where i.id = v_med.idoso_id;

  -- Período = [início 00:00, fim+1 00:00) no fuso da casa (DEC-023).
  if p_inicio is not null then
    v_ini := p_inicio::timestamp at time zone public.fn_fuso_casa();
    v_fim := (p_fim + 1)::timestamp at time zone public.fn_fuso_casa();
  end if;

  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', y.id,
             'tipo', y.tipo,
             'subtipo', y.subtipo,
             'quantidade', y.quantidade,
             'motivo', y.motivo,
             'criado_em', y.criado_em,
             'cuidador', y.cuidador,
             'residente', y.residente,
             'lotes', y.lotes
           ) order by y.criado_em desc), '[]'::jsonb)
    into v_movs
  from (
    select x.*
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
             -- Quem tomou, pelo dono resolvido da DEC-045. Só na baixa por dose
             -- de medicamento da casa; nulo em todo o resto.
             case
               when v_da_casa and me.tipo = 'saida_administracao'
                    and me.administracao_id is not null
               then (
                 select i.nome
                   from public.administracoes a
                   join public.medicamentos m on m.id = a.medicamento_id
                   join public.idosos i on i.id = coalesce(a.idoso_id, m.idoso_id)
                  where a.id = me.administracao_id
               )
             end as residente,
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
        and (v_ini is null or (me.criado_em >= v_ini and me.criado_em < v_fim))
    ) x
    where p_subtipos is null or x.subtipo = any (p_subtipos)
    order by x.criado_em desc
    -- Sem período, a ficha mostra as últimas 50 — como sempre mostrou.
    limit case when p_inicio is null then 50 end
  ) y;

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
      'eh_da_casa', v_da_casa,
      'saldo', v_med.saldo
    ),
    'movimentacoes', v_movs
  );
end;
$$;

comment on function public.extrato_medicamento(uuid, date, date, text[]) is
  'Movimentações de um medicamento (DEC-036/043/049). Período opcional: nulos = últimas 50 sem recorte (a ficha do estoque); preenchidos = recorte no fuso da casa. Campo `residente` só em baixa por dose de medicamento da casa, pelo dono resolvido da DEC-045.';

revoke execute on function
  public.extrato_medicamento(uuid, date, date, text[])
  from public, anon;
