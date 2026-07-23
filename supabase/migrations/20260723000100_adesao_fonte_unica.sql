-- =============================================================================
-- Migration: fonte única das doses da adesão (Sessão #13 — DEC-048)
--
-- `relatorio_adesao` contava as categorias com um `where` escrito dentro dela.
-- O extrato por categoria (DEC-048, migration seguinte) precisa LISTAR
-- exatamente as mesmas doses que o relatório CONTA. Se a listagem nascesse com
-- `where` próprio, passariam a existir duas implementações da mesma pergunta —
-- e no dia em que divergissem a tela diria "4 não tomadas" e listaria 3. O
-- relatório inteiro perderia a confiança da cuidadora.
--
-- O projeto já resolveu esse padrão uma vez: a ronda consome `doses_do_turno` e
-- não recalcula slots. `fn_doses_adesao` é o equivalente para a adesão.
--
-- ESTA MIGRATION É REFACTOR PURO: `relatorio_adesao` mantém assinatura e JSON de
-- saída idênticos, campo por campo. Nada de schema, nada de escrita.
--
-- O que passa a morar num lugar só:
--   * a REGRA DE PERÍODO ASSIMÉTRICA — dose agendada filtra por `prevista_em`,
--     dose SOS filtra por `registrado_em` (SOS não tem `prevista_em`, DEC-014/
--     023). Antes isso estava espalhado em dois `select`;
--   * o DONO RESOLVIDO `coalesce(a.idoso_id, m.idoso_id)` (DEC-045/046);
--   * o mapeamento status → categoria, nas mesmas chaves que o JSON já devolve e
--     que a tela já usa (`no_horario`, `atrasada`, `recusada`, `nao_tomada`,
--     `nao_apurada`, `sos`) — sem camada de tradução entre banco e tela.
--
-- O que NÃO entra na função: `pendentes` (doses vencidas sem tratativa no turno
-- aberto). São doses que ainda NÃO TÊM LINHA em `administracoes` — fonte
-- estruturalmente diferente, que continua vindo de `doses_do_turno`.
--
-- SECURITY INVOKER de propósito: `relatorio_adesao` e `detalhe_adesao` também
-- são invoker e precisam de execute como a cuidadora. Ela já tem `select` em
-- `administracoes` pelo RLS — a função não abre nada novo.
-- =============================================================================

create or replace function public.fn_doses_adesao(
  p_inicio   date,
  p_fim      date,
  p_idoso_id uuid default null
)
returns table (
  administracao_id   uuid,
  categoria          text,
  idoso_id           uuid,
  medicamento_id     uuid,
  nome_medicamento   text,
  dosagem            text,
  forma_farmaceutica text,
  eh_da_casa         boolean,
  qtd                numeric,
  prevista_em        timestamptz,
  registrado_em      timestamptz,
  cuidador_nome      text,
  observacao         text
)
language sql
stable
security invoker
set search_path = ''
as $$
  with limites as (
    -- Fronteira de dia no fuso da casa, nunca UTC (DEC-023).
    select p_inicio::timestamp   at time zone public.fn_fuso_casa() as ini,
           (p_fim + 1)::timestamp at time zone public.fn_fuso_casa() as fim
  )
  select
    a.id,
    case
      when a.horario_id is null            then 'sos'
      when a.status = 'tomado_no_horario'  then 'no_horario'
      when a.status = 'tomado_atrasado'    then 'atrasada'
      when a.status = 'recusado'           then 'recusada'
      when a.status = 'nao_tomado'         then 'nao_tomada'
      when a.status = 'pendente'           then 'nao_apurada'
    end,
    -- Dono resolvido: quem tomou, se gravado; senão o dono do medicamento.
    coalesce(a.idoso_id, m.idoso_id),
    a.medicamento_id,
    m.nome,
    m.dosagem,
    m.forma_farmaceutica,
    -- "Da casa" é propriedade do MEDICAMENTO (a caixa comum), não de quem tomou.
    coalesce(i_med.eh_sentinela, false),
    a.qtd,
    a.prevista_em,
    a.registrado_em,
    cu.nome,
    a.observacao
  from public.administracoes a
  join public.medicamentos m    on m.id = a.medicamento_id
  join public.idosos i_med      on i_med.id = m.idoso_id
  left join public.cuidadores cu on cu.id = a.cuidador_id
  cross join limites l
  where (
          -- Agendada: o fato é o slot planejado.
          (a.horario_id is not null
           and a.prevista_em >= l.ini and a.prevista_em < l.fim)
          -- SOS: o fato é o instante do registro.
       or (a.horario_id is null
           and a.registrado_em >= l.ini and a.registrado_em < l.fim)
        )
    and (p_idoso_id is null or coalesce(a.idoso_id, m.idoso_id) = p_idoso_id);
$$;

comment on function public.fn_doses_adesao(date, date, uuid) is
  'Fonte única das doses que compõem a adesão (DEC-048): uma linha por administração no período, com dono resolvido, categoria e a regra de período assimétrica (agendada por prevista_em, SOS por registrado_em). relatorio_adesao conta em cima dela; detalhe_adesao é a mesma função filtrada. NÃO inclui pendentes (doses sem linha em administracoes).';

revoke execute on function public.fn_doses_adesao(date, date, uuid) from public, anon;

-- -----------------------------------------------------------------------------
-- relatorio_adesao — MESMA assinatura, MESMO JSON. A única diferença é de onde
-- vêm as contagens: agora de `fn_doses_adesao`, não de dois `select` próprios.
-- O trecho de `pendentes` e o cálculo dos percentuais ficam literalmente iguais.
-- -----------------------------------------------------------------------------
create or replace function public.relatorio_adesao(
  p_inicio   date,
  p_fim      date,
  p_idoso_id uuid default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_ini          timestamptz;
  v_fim          timestamptz;
  v_no_horario   bigint;
  v_atrasada     bigint;
  v_recusada     bigint;
  v_nao_tomada   bigint;
  v_nao_apurada  bigint;
  v_total        bigint;
  v_pendentes    bigint := 0;
  v_sos          bigint;
  v_turno_aberto uuid;
begin
  if p_inicio is null or p_fim is null or p_fim < p_inicio then
    return jsonb_build_object('ok', false, 'erro', 'periodo_invalido');
  end if;
  if p_idoso_id is not null
     and not exists (select 1 from public.idosos where id = p_idoso_id) then
    return jsonb_build_object('ok', false, 'erro', 'residente_nao_encontrado');
  end if;

  -- Uma passada só na fonte única: as cinco categorias do denominador mais o
  -- SOS, que segue como contagem à parte (fora dos percentuais — DEC-030).
  select count(*) filter (where d.categoria = 'no_horario'),
         count(*) filter (where d.categoria = 'atrasada'),
         count(*) filter (where d.categoria = 'recusada'),
         count(*) filter (where d.categoria = 'nao_tomada'),
         count(*) filter (where d.categoria = 'nao_apurada'),
         count(*) filter (where d.categoria = 'sos')
    into v_no_horario, v_atrasada, v_recusada, v_nao_tomada, v_nao_apurada, v_sos
    from public.fn_doses_adesao(p_inicio, p_fim, p_idoso_id) d;

  v_total := v_no_horario + v_atrasada + v_recusada + v_nao_tomada + v_nao_apurada;

  -- Pendentes: doses já vencidas sem tratativa só existem dentro do turno
  -- aberto (todo turno fechado tem 100% de tratativa — DEC-022). Elas ainda não
  -- têm linha em `administracoes`, por isso ficam fora da fonte única. Doses
  -- agendadas apenas: medicamento da casa é SOS e não tem grade.
  v_ini := p_inicio::timestamp at time zone public.fn_fuso_casa();
  v_fim := (p_fim + 1)::timestamp at time zone public.fn_fuso_casa();

  select t.id into v_turno_aberto from public.turnos t where t.fim is null;
  if v_turno_aberto is not null then
    select count(*)
      into v_pendentes
      from public.doses_do_turno(v_turno_aberto) d
     where d.situacao <> 'tratada'
       and d.prevista_em >= v_ini and d.prevista_em < v_fim
       and (p_idoso_id is null or d.idoso_id = p_idoso_id);
  end if;

  return jsonb_build_object(
    'ok', true,
    'inicio', p_inicio,
    'fim', p_fim,
    'total_planejadas', v_total,
    'no_horario', jsonb_build_object('qtd', v_no_horario,
      'pct', case when v_total > 0 then round(v_no_horario * 100.0 / v_total, 1) end),
    'atrasada', jsonb_build_object('qtd', v_atrasada,
      'pct', case when v_total > 0 then round(v_atrasada * 100.0 / v_total, 1) end),
    'recusada', jsonb_build_object('qtd', v_recusada,
      'pct', case when v_total > 0 then round(v_recusada * 100.0 / v_total, 1) end),
    'nao_tomada', jsonb_build_object('qtd', v_nao_tomada,
      'pct', case when v_total > 0 then round(v_nao_tomada * 100.0 / v_total, 1) end),
    'nao_apurada', jsonb_build_object('qtd', v_nao_apurada,
      'pct', case when v_total > 0 then round(v_nao_apurada * 100.0 / v_total, 1) end),
    'pendentes', v_pendentes,
    'devidas_ate_agora', v_total + v_pendentes,
    'sos', v_sos
  );
end;
$$;

revoke execute on function public.relatorio_adesao(date, date, uuid) from public, anon;
