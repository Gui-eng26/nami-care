-- =============================================================================
-- Migration: pendências entre turnos (Sessão #5.5 — BUG-002, DEC-033, DEC-034)
--
-- BUG-002: doses_do_turno delimita a busca por [turno.inicio, agora]. Se um
-- período fica sem NENHUM turno aberto (madrugada sem plantão registrado,
-- cuidadora esqueceu de abrir o app), as doses vencidas nesse intervalo não
-- entram na consulta do turno seguinte — ficam invisíveis por construção:
-- não aparecem como pendentes, atrasadas nem em estado algum, e o relatório
-- de adesão as perde do denominador (limite já documentado na DEC-030).
--
-- Decisão de produto: NÃO estender a janela da doses_do_turno (misturaria
-- "meu trabalho deste turno" com "problema de um turno que não existiu").
-- As doses órfãs vão para uma fila própria — "Pendências entre turnos" —
-- com consulta independente, tratativa individual pelo mesmo modal da ronda
-- e resolução em lote com o novo status 'pendente'.
--
-- DEC-033 — teto de 5 dias: a fila só materializa pendências dos últimos
--   5 dias (janela móvel de 120 h). Dias mais antigos com pendência são
--   apenas CONTADOS (dias, não doses) para o aviso de dado perdido — o app
--   não reconstrói histórico ilimitado, e dado além do teto deixa de ser
--   tratável (nem individualmente, nem em lote). Consequência assumida.
--
-- DEC-034 — resolução em lote + status 'pendente':
--   'pendente' ≠ 'nao_tomado'. 'nao_tomado' é a CONFIRMAÇÃO de que a dose
--   não foi dada; 'pendente' é "não sabemos, e decidimos conscientemente
--   não apurar". Nunca somar os dois. O status só nasce da RPC de lote
--   (trigger de guarda impede INSERT direto), exige o PIN do próprio
--   cuidador do turno aberto (reafirmação de identidade, mesmo espírito da
--   reverificação do trocar_pin/DEC-025) e NÃO movimenta estoque (o trigger
--   de baixa já ignora status fora de tomado_*/recusado) — a reconciliação
--   é manual, via registrar_ajuste_estoque (Sessão #4).
--
-- fechar_turno passa a considerar as DUAS filas: doses_do_turno E pendências
-- entre turnos dentro do teto ('pendente' conta como resolvida; dose além do
-- teto não bloqueia, por definição da DEC-033).
--
-- relatorio_adesao ganha a 5ª categoria "Pendente (não apurado)" — chave
-- jsonb 'nao_apurada', para não colidir com 'pendentes' (doses do turno
-- aberto ainda sem tratativa, fora do denominador). 'pendente' É linha
-- materializada: entra no denominador com percentual próprio.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Novo status 'pendente' em administracoes.
--    O trigger de baixa (fn_baixa_automatica_estoque) não precisa mudar: só
--    movimenta estoque para tomado_no_horario/tomado_atrasado/recusado —
--    'pendente' cai no mesmo "nenhuma movimentação" do nao_tomado.
-- -----------------------------------------------------------------------------
alter table public.administracoes
  drop constraint administracoes_status_check;
alter table public.administracoes
  add constraint administracoes_status_check
    check (status in ('tomado_no_horario', 'tomado_atrasado',
                      'nao_tomado', 'recusado', 'pendente'));

-- 'pendente' só nasce da resolução em lote (DEC-034): quem trata dose a dose
-- está confirmando o que aconteceu — o modal individual não oferece essa
-- opção, e o banco garante a regra por qualquer caminho de escrita.
create or replace function public.fn_pendente_so_em_lote()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status = 'pendente'
     and coalesce(current_setting('nami_care.lote_pendencias', true), '') <> 'on' then
    raise exception
      'Status pendente só pode ser gravado pela resolução em lote de pendências entre turnos (DEC-034)';
  end if;
  return new;
end;
$$;

create trigger trg_pendente_so_em_lote
  before insert on public.administracoes
  for each row execute function public.fn_pendente_so_em_lote();

-- -----------------------------------------------------------------------------
-- 2) fn_pendencias_entre_turnos — fonte única da fila entre turnos.
--    Dose vencida (prevista_em <= agora) de medicamento contínuo com
--    horário/medicamento/residente ativos, SEM administração, cujo instante
--    não foi coberto por NENHUM turno (intervalos [inicio, fim ou agora]).
--    Limites:
--    - só a partir do primeiro turno da casa (antes disso o app não operava);
--    - só a partir da criação do horário (linha versionada pela DEC-026 não
--      gera pendência retroativa de antes de existir);
--    - dose SOS não entra: sem grade planejada, não há pendência (DEC-014).
--    dentro_do_teto marca a janela de 5 dias da DEC-033; fora dela a linha
--    existe apenas para a CONTAGEM de dias perdidos.
--    Independente da doses_do_turno, que permanece intocada (bounded por
--    turno.inicio): as duas filas nunca se sobrepõem — o que o turno aberto
--    cobre está coberto por um turno e não aparece aqui.
-- -----------------------------------------------------------------------------
create or replace function public.fn_pendencias_entre_turnos()
returns table (
  horario_id         uuid,
  medicamento_id     uuid,
  idoso_id           uuid,
  nome_idoso         text,
  nome_medicamento   text,
  dosagem            text,
  forma_farmaceutica text,
  qtd_dose           numeric,
  prevista_em        timestamptz,
  dia                date,
  dentro_do_teto     boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  with limites as (
    select min(t.inicio) as primeiro_turno,
           now() - interval '5 days' as teto
    from public.turnos t
  ),
  dias as (
    select generate_series(
             (l.primeiro_turno at time zone public.fn_fuso_casa())::date,
             (now() at time zone public.fn_fuso_casa())::date,
             interval '1 day'
           )::date as dia
    from limites l
    where l.primeiro_turno is not null
  ),
  slots as (
    select h.id as horario_id,
           h.medicamento_id,
           h.qtd_dose,
           h.criado_em,
           d.dia,
           ((d.dia + h.hora) at time zone public.fn_fuso_casa()) as prevista_em
    from public.horarios h
    join public.medicamentos m on m.id = h.medicamento_id
    join public.idosos i on i.id = m.idoso_id
    cross join dias d
    where h.ativo
      and m.ativo
      and i.ativo
      and m.tipo = 'continuo'
  )
  select s.horario_id,
         s.medicamento_id,
         m.idoso_id,
         i.nome,
         m.nome,
         m.dosagem,
         m.forma_farmaceutica,
         s.qtd_dose,
         s.prevista_em,
         s.dia,
         s.prevista_em >= l.teto
  from slots s
  cross join limites l
  join public.medicamentos m on m.id = s.medicamento_id
  join public.idosos i on i.id = m.idoso_id
  where s.prevista_em <= now()
    and s.prevista_em >= l.primeiro_turno
    and s.prevista_em >= s.criado_em
    and not exists (
      select 1 from public.administracoes a
      where a.horario_id = s.horario_id
        and a.prevista_em = s.prevista_em
    )
    and not exists (
      select 1 from public.turnos t
      where s.prevista_em >= t.inicio
        and s.prevista_em <= coalesce(t.fim, now())
    )
  order by s.prevista_em, i.nome, m.nome;
$$;

revoke execute on function public.fn_pendencias_entre_turnos() from public, anon;

-- -----------------------------------------------------------------------------
-- 3) listar_pendencias_entre_turnos — contrato jsonb para a tela:
--    doses dentro do teto (a lista tratável), total (contagem de doses, usada
--    na aba) e dias_alem_do_teto (contagem de DIAS perdidos, para o aviso
--    permanente de dado não tratável — DEC-033).
-- -----------------------------------------------------------------------------
create or replace function public.listar_pendencias_entre_turnos()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'ok', true,
    'teto_dias', 5,
    'total', count(*) filter (where p.dentro_do_teto),
    'dias_alem_do_teto', count(distinct p.dia) filter (where not p.dentro_do_teto),
    'doses', coalesce(
      jsonb_agg(jsonb_build_object(
        'horario_id', p.horario_id,
        'medicamento_id', p.medicamento_id,
        'idoso_id', p.idoso_id,
        'nome_idoso', p.nome_idoso,
        'nome_medicamento', p.nome_medicamento,
        'dosagem', p.dosagem,
        'forma_farmaceutica', p.forma_farmaceutica,
        'qtd_dose', p.qtd_dose,
        'prevista_em', p.prevista_em,
        'dia', p.dia
      ) order by p.prevista_em, p.nome_idoso, p.nome_medicamento)
        filter (where p.dentro_do_teto),
      '[]'::jsonb)
  )
  from public.fn_pendencias_entre_turnos() p;
$$;

revoke execute on function public.listar_pendencias_entre_turnos() from public, anon;

-- -----------------------------------------------------------------------------
-- 4) resolver_pendencias_em_lote — encerra de uma vez tudo que ainda está sem
--    tratativa DENTRO do teto, com status 'pendente' (DEC-034). Exige o PIN do
--    próprio cuidador do turno aberto, verificado no banco com o rate limit de
--    sempre (fn_verificar_pin — DEC-020/021): é reafirmação de identidade para
--    uma ação de impacto, não troca de credencial. Cobre só o que restar no
--    momento da execução (o que já foi tratado individualmente fica de fora —
--    a UNIQUE do slot e o NOT EXISTS da fila garantem).
--    Nenhuma movimentação de estoque é gerada (trigger de baixa ignora
--    'pendente'); a reconciliação é manual via registrar_ajuste_estoque.
-- -----------------------------------------------------------------------------
create or replace function public.resolver_pendencias_em_lote(
  p_turno_id uuid,
  p_pin      text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_turno public.turnos;
  v_verif jsonb;
  v_total int;
begin
  select * into v_turno from public.turnos where id = p_turno_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'turno_nao_encontrado');
  end if;
  if v_turno.fim is not null then
    return jsonb_build_object('ok', false, 'erro', 'turno_ja_fechado');
  end if;

  v_verif := public.fn_verificar_pin(v_turno.cuidador_id, p_pin);
  if not (v_verif ->> 'ok')::boolean then
    return v_verif;
  end if;

  -- Libera o status 'pendente' apenas dentro desta transação (trigger de
  -- guarda trg_pendente_so_em_lote).
  perform set_config('nami_care.lote_pendencias', 'on', true);

  insert into public.administracoes
    (medicamento_id, horario_id, cuidador_id, qtd, status, observacao, prevista_em)
  select p.medicamento_id,
         p.horario_id,
         v_turno.cuidador_id,
         p.qtd_dose,
         'pendente',
         'Encerrada em lote sem apuração individual (pendências entre turnos)',
         p.prevista_em
  from public.fn_pendencias_entre_turnos() p
  where p.dentro_do_teto
  on conflict (horario_id, prevista_em) do nothing;

  get diagnostics v_total = row_count;
  perform set_config('nami_care.lote_pendencias', '', true);

  return jsonb_build_object('ok', true, 'total', v_total);
end;
$$;

revoke execute on function public.resolver_pendencias_em_lote(uuid, text)
  from public, anon;

-- -----------------------------------------------------------------------------
-- 5) fechar_turno considera as duas filas: doses do turno (como sempre) E
--    pendências entre turnos dentro do teto. 'pendente' já conta como
--    resolvida nas duas (tem administração). O retorno distingue as origens
--    para a tela explicar de onde vem o bloqueio.
-- -----------------------------------------------------------------------------
create or replace function public.fechar_turno(p_turno_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_turno        public.turnos;
  v_ronda        int;
  v_pendentes    jsonb;
  v_entre_turnos int;
begin
  select * into v_turno from public.turnos where id = p_turno_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'turno_nao_encontrado');
  end if;
  if v_turno.fim is not null then
    return jsonb_build_object('ok', false, 'erro', 'turno_ja_fechado');
  end if;

  select count(*),
         jsonb_agg(jsonb_build_object(
           'nome_idoso', d.nome_idoso,
           'nome_medicamento', d.nome_medicamento,
           'dosagem', d.dosagem,
           'prevista_em', d.prevista_em,
           'situacao', d.situacao
         ) order by d.prevista_em, d.nome_idoso)
    into v_ronda, v_pendentes
    from public.doses_do_turno(p_turno_id) d
   where d.situacao <> 'tratada';

  -- Pendências entre turnos dentro do teto de 5 dias (DEC-033/034). Doses
  -- além do teto não bloqueiam: não são mais tratáveis pelo app, por definição.
  select count(*)
    into v_entre_turnos
    from public.fn_pendencias_entre_turnos() p
   where p.dentro_do_teto;

  if v_ronda > 0 or v_entre_turnos > 0 then
    return jsonb_build_object('ok', false, 'erro', 'doses_pendentes',
                              'total', v_ronda + v_entre_turnos,
                              'total_ronda', v_ronda,
                              'total_entre_turnos', v_entre_turnos,
                              'doses', v_pendentes);
  end if;

  update public.turnos set fim = now() where id = p_turno_id;
  return jsonb_build_object('ok', true, 'turno_id', p_turno_id, 'fim', now());
end;
$$;

revoke execute on function public.fechar_turno(uuid) from public, anon;

-- -----------------------------------------------------------------------------
-- 6) relatorio_adesao — 5ª categoria "Pendente (não apurado)" (DEC-034).
--    'pendente' é linha materializada: entra no denominador com percentual
--    próprio. Não se soma a 'não tomada' (que é confirmação de falta) nem às
--    tomadas (que são confirmação de ocorrência) — mentiria nos dois casos.
--    Chave jsonb 'nao_apurada' para não colidir com 'pendentes' (doses do
--    turno aberto sem tratativa, fora do denominador — semântica distinta).
--    Restante idêntico à versão da Sessão #5 (DEC-030/031/032).
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
     and (p_idoso_id is null or m.idoso_id = p_idoso_id);

  v_total := v_no_horario + v_atrasada + v_recusada + v_nao_tomada + v_nao_apurada;

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
    'nao_apurada', jsonb_build_object('qtd', v_nao_apurada,
      'pct', case when v_total > 0 then round(v_nao_apurada * 100.0 / v_total, 1) end),
    'pendentes', v_pendentes,
    'devidas_ate_agora', v_total + v_pendentes,
    'sos', v_sos
  );
end;
$$;

revoke execute on function public.relatorio_adesao(date, date, uuid) from public, anon;
