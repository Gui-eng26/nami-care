-- =============================================================================
-- Migration: dose SOS reestruturada (Sessão #12 — DEC-047)
--
-- A dose SOS invertia a ordem natural: montava a lista a partir do ESTOQUE SOS
-- por residente, então só aparecia quem já tinha um SOS próprio cadastrado, e o
-- medicamento vinha preso ao residente. Não havia como dar um SOS da casa a um
-- residente qualquer.
--
-- Fluxo novo — primeiro QUEM TOMA, depois QUAL MEDICAMENTO:
--   1) residente: todos os ativos, EXCETO o "Da Casa" (ninguém toma "como a
--      casa"); é aqui, e só aqui, que o sentinela é escondido — por não entrar
--      na lista, sem precisar de flag em lugar nenhum;
--   2) medicamento: os SOS ativos DAQUELE residente MAIS os SOS DA CASA, numa
--      lista só (os dois coexistem: a Maria pode ter o SOS particular dela e
--      também tomar da caixa comum);
--   3) quantidade (meio-em-meio preservado);
--   4) registro com o horário real do momento (SOS já é horario_id nulo);
--   5) dono da dose: preenchido só se o medicamento é da casa (DEC-045);
--   6) baixa de estoque: trigger da DEC-008 + FEFO da DEC-042, sem nada novo.
--
-- POR QUE UMA RPC (e não o INSERT direto de antes): agora há uma regra a
-- garantir — medicamento da casa EXIGE o dono da dose, medicamento de residente
-- EXIGE que ele fique nulo. Deixar isso no cliente seria pôr regra de negócio
-- fora do banco. A RPC valida e NORMALIZA: recebe sempre quem tomou (é o passo
-- 1 da tela, o cliente não precisa saber a regra) e decide se grava ou descarta.
-- O trigger da DEC-045 continua atrás dela como garantia dura.
--
-- A DOSE AGENDADA DA RONDA NÃO MUDA: segue INSERT direto do cliente, mesmo
-- caminho, mesma tela. A política de INSERT de `administracoes` passa a exigir
-- `horario_id` não nulo — o que a ronda sempre fez — de modo que a única porta
-- do SOS é esta RPC. Caminhos SECURITY DEFINER (esta RPC, a resolução em lote
-- de pendências) rodam como owner e não passam por RLS.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) INSERT direto do cliente = dose agendada. SOS só pela RPC.
-- -----------------------------------------------------------------------------
drop policy administracoes_insert_autenticado on public.administracoes;

create policy administracoes_insert_agendada on public.administracoes
  for insert to authenticated
  with check (horario_id is not null);

-- -----------------------------------------------------------------------------
-- 2) registrar_dose_sos — a porta única da dose avulsa.
--    p_idoso_id é SEMPRE quem tomou (passo 1 da tela). A RPC normaliza:
--    grava em administracoes.idoso_id apenas quando o medicamento é da casa.
-- -----------------------------------------------------------------------------
create or replace function public.registrar_dose_sos(
  p_medicamento_id uuid,
  p_idoso_id       uuid,
  p_qtd            numeric,
  p_observacao     text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cuidador uuid;
  v_med      public.medicamentos;
  v_da_casa  boolean;
  v_id       uuid;
  v_saldo    numeric;
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
  if v_med.tipo <> 'sos' then
    return jsonb_build_object('ok', false, 'erro', 'medicamento_nao_sos');
  end if;

  -- Quem toma: residente ativo de verdade. O "Da Casa" não toma nada.
  if not exists (select 1 from public.idosos i
                  where i.id = p_idoso_id and i.ativo and not i.eh_sentinela) then
    return jsonb_build_object('ok', false, 'erro', 'residente_nao_encontrado');
  end if;

  select i.eh_sentinela into v_da_casa
    from public.idosos i where i.id = v_med.idoso_id;

  -- O medicamento tem que ser do próprio residente ou da casa — nunca da caixa
  -- de outro residente (é a caixa física de outra pessoa).
  if not v_da_casa and v_med.idoso_id <> p_idoso_id then
    return jsonb_build_object('ok', false, 'erro', 'medicamento_de_outro_residente');
  end if;

  if p_qtd is null or p_qtd <= 0 or mod(p_qtd * 2, 1) <> 0 then
    return jsonb_build_object('ok', false, 'erro', 'qtd_invalida');
  end if;

  -- horario_id nulo (dose avulsa, DEC-014) e registrado_em = agora (default):
  -- a hora do registro é a hora do fato. A baixa de estoque com FEFO vem do
  -- trigger da DEC-008/042 — nenhuma lógica de estoque aqui.
  insert into public.administracoes
    (medicamento_id, horario_id, idoso_id, cuidador_id, qtd, status, observacao)
  values
    (p_medicamento_id, null,
     case when v_da_casa then p_idoso_id end,
     v_cuidador, p_qtd, 'tomado_no_horario',
     nullif(trim(coalesce(p_observacao, '')), ''))
  returning id into v_id;

  select coalesce(sum(saldo_atual), 0) into v_saldo
    from public.lotes_estoque where medicamento_id = p_medicamento_id;

  return jsonb_build_object('ok', true, 'administracao_id', v_id,
                            'da_casa', coalesce(v_da_casa, false),
                            'saldo', v_saldo);
end;
$$;

revoke execute on function
  public.registrar_dose_sos(uuid, uuid, numeric, text)
  from public, anon;
