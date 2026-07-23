-- =============================================================================
-- Migration: extrato de adesão por categoria (Sessão #13 — DEC-048)
--
-- O relatório entrega só o agregado: dá para saber que houve 3 não tomadas no
-- período, não QUAIS. Para agir sobre uma não adesão a cuidadora precisa saber
-- em que dia e hora, de qual medicamento. É a mesma ideia do extrato de
-- movimentação de estoque, trazida para dentro da adesão.
--
-- É A MESMA FUNÇÃO DO RELATÓRIO, FILTRADA. `detalhe_adesao` não tem `where`
-- próprio: lê `fn_doses_adesao` (DEC-048) e filtra por categoria. Por
-- construção, o que esta RPC lista é exatamente o que `relatorio_adesao` conta —
-- não há como divergirem.
--
-- Só na visão POR RESIDENTE: `p_idoso_id` é obrigatório. Na visão "Toda a casa"
-- uma lista de centenas de doses de onze pessoas não ajudaria ninguém a agir, e
-- é justamente agir que motiva a tela.
--
-- Teto de 200 linhas, mais recentes primeiro, com `total` sempre devolvendo a
-- contagem REAL antes do corte e `truncado` dizendo que houve corte. Nunca
-- truncar em silêncio — uma lista que mente sobre o próprio tamanho é pior que
-- lista nenhuma.
--
-- O sentinela "Da Casa" não precisa de tratamento especial: nenhuma dose resolve
-- para ele (DEC-046), então a lista vem naturalmente vazia.
--
-- Somente leitura. Nada de schema, nada de escrita.
-- =============================================================================

create or replace function public.detalhe_adesao(
  p_inicio    date,
  p_fim       date,
  p_idoso_id  uuid,
  p_categoria text
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_limite constant int := 200;
  v_total  bigint;
  v_doses  jsonb;
begin
  if p_inicio is null or p_fim is null or p_fim < p_inicio then
    return jsonb_build_object('ok', false, 'erro', 'periodo_invalido');
  end if;
  -- O detalhe existe só por residente (ver cabeçalho).
  if p_idoso_id is null then
    return jsonb_build_object('ok', false, 'erro', 'residente_obrigatorio');
  end if;
  if not exists (select 1 from public.idosos where id = p_idoso_id) then
    return jsonb_build_object('ok', false, 'erro', 'residente_nao_encontrado');
  end if;
  -- Lista fechada: as cinco categorias do relatório (DEC-030/034) mais o SOS.
  -- Nenhuma categoria nova nasce aqui.
  if p_categoria is null or p_categoria not in
     ('no_horario', 'atrasada', 'recusada', 'nao_tomada', 'nao_apurada', 'sos') then
    return jsonb_build_object('ok', false, 'erro', 'categoria_invalida');
  end if;

  select count(*) into v_total
    from public.fn_doses_adesao(p_inicio, p_fim, p_idoso_id) d
   where d.categoria = p_categoria;

  -- Instante de referência: `prevista_em` na agendada, `registrado_em` no SOS —
  -- a mesma assimetria que governa o período, agora governando a ordem.
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'administracao_id', x.administracao_id,
             'medicamento_id', x.medicamento_id,
             'nome_medicamento', x.nome_medicamento,
             'dosagem', x.dosagem,
             'forma_farmaceutica', x.forma_farmaceutica,
             'eh_da_casa', x.eh_da_casa,
             'qtd', x.qtd,
             'prevista_em', x.prevista_em,
             'registrado_em', x.registrado_em,
             'cuidador_nome', x.cuidador_nome,
             'observacao', x.observacao
           ) order by x.referencia desc), '[]'::jsonb)
    into v_doses
  from (
    select d.*, coalesce(d.prevista_em, d.registrado_em) as referencia
      from public.fn_doses_adesao(p_inicio, p_fim, p_idoso_id) d
     where d.categoria = p_categoria
     order by coalesce(d.prevista_em, d.registrado_em) desc
     limit v_limite
  ) x;

  return jsonb_build_object(
    'ok', true,
    'categoria', p_categoria,
    'total', v_total,
    'limite', v_limite,
    'truncado', v_total > v_limite,
    'doses', v_doses
  );
end;
$$;

comment on function public.detalhe_adesao(date, date, uuid, text) is
  'Extrato de adesão por categoria (DEC-048): lista as doses que relatorio_adesao conta, lendo a mesma fn_doses_adesao. Exige residente. Teto de 200 linhas, mais recentes primeiro; `total` é a contagem real antes do corte.';

revoke execute on function
  public.detalhe_adesao(date, date, uuid, text)
  from public, anon;
