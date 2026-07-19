-- =============================================================================
-- Migration: relatório de adesão (Sessão #5 — DEC-030/031/032; BRIEFING §6.10)
--
-- Modelo de cálculo (DEC-030):
--   Denominador = doses já MATERIALIZADAS: linhas de administracoes de ronda
--   (horario_id não nulo) com prevista_em dentro do período. A grade histórica
--   de horários NUNCA é reconstruída a partir de `horarios` — o fechamento
--   obrigatório de turno (DEC-010/022) garante que cada dia já fechado carrega,
--   em linhas próprias, exatamente as doses que estavam previstas nele; a
--   prescrição versionada (DEC-026) é absorvida naturalmente.
--
--   Quatro categorias mutuamente exclusivas, direto do status gravado (a
--   comparação registrado_em × prevista_em NÃO classifica: registro tardio de
--   dose tomada no horário grava registrado_em = prevista_em — DEC-023):
--     no horário  = status 'tomado_no_horario'
--     atrasada    = status 'tomado_atrasado'
--     recusada    = status 'recusado'   (decisão do residente)
--     não tomada  = status 'nao_tomado' (falha operacional — nunca somar com
--                                        recusada: são sinais distintos)
--
--   Dia corrente: dose futura fica fora do denominador; dose já vencida sem
--   tratativa (turno aberto em andamento) entra como PENDENTE, categoria à
--   parte — vem de doses_do_turno (fonte única da lógica de slots, DEC-023;
--   nada de segunda implementação). Percentuais calculados AQUI, nunca no
--   cliente. SOS (horario_id nulo) fica fora dos percentuais: contagem
--   absoluta, sem denominador natural.
--
--   Fronteira de dia sempre no fuso da casa (fn_fuso_casa, DEC-023).
--
-- Visões (macro/micro): a macro (casa) é a micro sem o filtro de residente —
-- mesmo caminho de cálculo (p_idoso_id nulo = casa toda). Residente desativado
-- (DEC-032): o histórico do período ativo continua contando e aparece na macro;
-- o selo de desativado é apresentação (tela).
--
-- Acesso (DEC-031): qualquer cuidadora autenticada — o relatório é aba de
-- operação junto de Ronda | Estoque, não área de gestão (não exige DEC-024).
-- =============================================================================

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
  v_ini         timestamptz;
  v_fim         timestamptz;
  v_no_horario  bigint;
  v_atrasada    bigint;
  v_recusada    bigint;
  v_nao_tomada  bigint;
  v_total       bigint;
  v_pendentes   bigint := 0;
  v_sos         bigint;
  v_turno_aberto uuid;
begin
  if p_inicio is null or p_fim is null or p_fim < p_inicio then
    return jsonb_build_object('ok', false, 'erro', 'periodo_invalido');
  end if;
  if p_idoso_id is not null
     and not exists (select 1 from public.idosos where id = p_idoso_id) then
    return jsonb_build_object('ok', false, 'erro', 'residente_nao_encontrado');
  end if;

  -- Período = [início 00:00, fim+1 00:00) no fuso da casa, nunca UTC.
  v_ini := p_inicio::timestamp at time zone public.fn_fuso_casa();
  v_fim := (p_fim + 1)::timestamp at time zone public.fn_fuso_casa();

  select count(*) filter (where a.status = 'tomado_no_horario'),
         count(*) filter (where a.status = 'tomado_atrasado'),
         count(*) filter (where a.status = 'recusado'),
         count(*) filter (where a.status = 'nao_tomado')
    into v_no_horario, v_atrasada, v_recusada, v_nao_tomada
    from public.administracoes a
    join public.medicamentos m on m.id = a.medicamento_id
   where a.horario_id is not null
     and a.prevista_em >= v_ini and a.prevista_em < v_fim
     and (p_idoso_id is null or m.idoso_id = p_idoso_id);

  v_total := v_no_horario + v_atrasada + v_recusada + v_nao_tomada;

  -- SOS não tem prevista_em: o instante do fato é registrado_em (DEC-014/023).
  select count(*)
    into v_sos
    from public.administracoes a
    join public.medicamentos m on m.id = a.medicamento_id
   where a.horario_id is null
     and a.registrado_em >= v_ini and a.registrado_em < v_fim
     and (p_idoso_id is null or m.idoso_id = p_idoso_id);

  -- Pendentes: doses já vencidas sem tratativa só existem dentro do turno
  -- aberto (todo turno fechado tem 100% de tratativa — DEC-022).
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
    'pendentes', v_pendentes,
    'devidas_ate_agora', v_total + v_pendentes,
    'sos', v_sos
  );
end;
$$;

revoke execute on function public.relatorio_adesao(date, date, uuid) from public, anon;
