-- =============================================================================
-- Migration: adesão conta pelo dono real da dose (Sessão #12 — DEC-046)
--
-- O relatório atribuía TODA dose ao `medicamentos.idoso_id`. Com o estoque da
-- casa (DEC-044), a dipirona que a dona Maria tomou da caixa comum cairia na
-- adesão do "Da Casa" — um residente que não existe, cobrindo justamente o que
-- o relatório deveria mostrar.
--
-- Mudança: o residente de uma dose passa a ser o DONO RESOLVIDO (DEC-045),
--     coalesce(a.idoso_id, m.idoso_id)
-- tanto no trecho de SOS quanto no de doses agendadas (onde é literalmente o
-- mesmo valor de antes — a coluna é sempre nula ali; escrever coalesce nos dois
-- lugares deixa UMA regra na cabeça de quem lê, não duas). O filtro por
-- residente (`p_idoso_id`) segue o mesmo dono resolvido: a Maria vê, na adesão
-- dela, também o que tomou da casa.
--
-- Consequência desejada: o "Da Casa" NÃO gera linha de adesão própria — como
-- ninguém "é" a casa em consumo, nenhuma dose resolve para ele.
--
-- O RESTO DO RELATÓRIO NÃO MUDA: denominador materializado, as cinco categorias
-- (DEC-030/034), pendentes do turno aberto, fronteira de dia no fuso da casa.
-- Diferença em relação à versão da Sessão #9, linha a linha: só o coalesce.
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

  -- Período = [início 00:00, fim+1 00:00) no fuso da casa, nunca UTC.
  v_ini := p_inicio::timestamp at time zone public.fn_fuso_casa();
  v_fim := (p_fim + 1)::timestamp at time zone public.fn_fuso_casa();

  select count(*) filter (where a.status = 'tomado_no_horario'),
         count(*) filter (where a.status = 'tomado_atrasado'),
         count(*) filter (where a.status = 'recusado'),
         count(*) filter (where a.status = 'nao_tomado'),
         count(*) filter (where a.status = 'pendente')
    into v_no_horario, v_atrasada, v_recusada, v_nao_tomada, v_nao_apurada
    from public.administracoes a
    join public.medicamentos m on m.id = a.medicamento_id
   where a.horario_id is not null
     and a.prevista_em >= v_ini and a.prevista_em < v_fim
     and (p_idoso_id is null
          or coalesce(a.idoso_id, m.idoso_id) = p_idoso_id);

  v_total := v_no_horario + v_atrasada + v_recusada + v_nao_tomada + v_nao_apurada;

  -- SOS não tem prevista_em: o instante do fato é registrado_em (DEC-014/023).
  -- Aqui o coalesce trabalha de verdade: a dose do medicamento da casa entra na
  -- adesão de quem tomou (DEC-045/046).
  select count(*)
    into v_sos
    from public.administracoes a
    join public.medicamentos m on m.id = a.medicamento_id
   where a.horario_id is null
     and a.registrado_em >= v_ini and a.registrado_em < v_fim
     and (p_idoso_id is null
          or coalesce(a.idoso_id, m.idoso_id) = p_idoso_id);

  -- Pendentes: doses já vencidas sem tratativa só existem dentro do turno
  -- aberto (todo turno fechado tem 100% de tratativa — DEC-022). Doses
  -- agendadas apenas: medicamento da casa é SOS e não tem grade.
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
