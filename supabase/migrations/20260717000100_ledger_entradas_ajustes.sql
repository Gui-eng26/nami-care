-- =============================================================================
-- Migration: entradas, ajuste por contagem e perda manual no ledger (Sessão #4)
--
-- 1) A metade que faltava do ledger (DEC-004): hoje só existem saídas (trigger
--    da Sessão #1). Três RPCs completam o ciclo:
--      registrar_entrada_estoque — reposição de compra (entrada_compra)
--      registrar_ajuste_estoque  — contagem física; o banco calcula a diferença
--                                  e grava ajuste_contagem (nunca sobrescreve)
--      registrar_perda_estoque   — quebra, vencimento, descarte (perda)
--    Todas gravam o cuidador do TURNO ABERTO (DEC-019): a RPC descobre quem
--    detém o turno; sem turno aberto, nenhuma movimentação manual.
-- 2) Escrita direta em movimentacoes_estoque sai do cliente (mesmo padrão de
--    turnos/cadastros): INSERT revogado + política removida. O trigger de
--    baixa automática vira SECURITY DEFINER para continuar inserindo quando a
--    administração é registrada pelo papel authenticated.
-- 3) medicamentos.estoque_minimo (DEC-027): estoque mínimo de segurança dos
--    medicamentos SOS, definido pelo cuidador no cadastro. criar_medicamento e
--    atualizar_medicamento ganham o parâmetro (assinaturas recriadas).
--    O campo é calibração operacional, não clínica: fica fora da imutabilidade
--    da DEC-026 e é sempre editável.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- estoque_minimo (DEC-027): relevante para SOS; aceita fração 0,5 (DEC-013).
-- -----------------------------------------------------------------------------
alter table public.medicamentos
  add column estoque_minimo numeric(6,2),
  add constraint medicamentos_estoque_minimo_valido
    check (estoque_minimo is null
           or (estoque_minimo >= 0 and mod(estoque_minimo * 2, 1) = 0));

-- -----------------------------------------------------------------------------
-- Ledger fecha para escrita direta do cliente: RPCs e trigger são o único
-- caminho (DEC-016/DEC-017 continuam valendo — nada de UPDATE/DELETE).
-- -----------------------------------------------------------------------------
revoke insert on table public.movimentacoes_estoque from anon, authenticated;
drop policy movimentacoes_insert_autenticado on public.movimentacoes_estoque;

-- O trigger de baixa (DEC-008) passa a SECURITY DEFINER: o INSERT em
-- administracoes continua vindo do authenticated (ronda e dose SOS), mas a
-- movimentação derivada é gravada com os privilégios do dono da função.
create or replace function public.fn_baixa_automatica_estoque()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status in ('tomado_no_horario', 'tomado_atrasado') then
    insert into public.movimentacoes_estoque
      (medicamento_id, cuidador_id, administracao_id, tipo, quantidade, motivo, criado_em)
    values
      (new.medicamento_id, new.cuidador_id, new.id, 'saida_administracao',
       -new.qtd, 'Baixa automática — dose administrada', new.registrado_em);
  elsif new.status = 'recusado' then
    insert into public.movimentacoes_estoque
      (medicamento_id, cuidador_id, administracao_id, tipo, quantidade, motivo, criado_em)
    values
      (new.medicamento_id, new.cuidador_id, new.id, 'perda',
       -new.qtd, 'Perda — dose recusada pelo idoso (DEC-009)', new.registrado_em);
  end if;
  -- nao_tomado: nenhuma movimentação
  return new;
end;
$$;

revoke execute on function public.fn_baixa_automatica_estoque()
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- fn_cuidador_do_turno — quem detém o turno aberto (DEC-019/DEC-022).
-- Interna: usada pelas RPCs de movimentação manual.
-- -----------------------------------------------------------------------------
create or replace function public.fn_cuidador_do_turno()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select cuidador_id from public.turnos where fim is null limit 1;
$$;

revoke execute on function public.fn_cuidador_do_turno()
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- registrar_entrada_estoque — reposição de compra (linha positiva).
-- p_data: dia da compra (default hoje, fuso da casa); compra de dias anteriores
-- entra datada ao meio-dia local para o extrato contar a história certa.
-- Erros: sem_turno_aberto | medicamento_nao_encontrado | medicamento_inativo |
--        qtd_invalida | data_futura
-- -----------------------------------------------------------------------------
create or replace function public.registrar_entrada_estoque(
  p_medicamento_id uuid,
  p_quantidade     numeric,
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

  select coalesce(sum(quantidade), 0) into v_saldo
    from public.movimentacoes_estoque where medicamento_id = p_medicamento_id;

  return jsonb_build_object('ok', true, 'movimentacao_id', v_id, 'saldo', v_saldo);
end;
$$;

revoke execute on function
  public.registrar_entrada_estoque(uuid, numeric, date, text)
  from public, anon;

-- -----------------------------------------------------------------------------
-- registrar_ajuste_estoque — a cuidadora informa a quantidade CONTADA; o banco
-- calcula a diferença contra o saldo do ledger e registra ajuste_contagem.
-- O motivo grava os dois números: é o relatório de divergência em uma linha.
-- Contagem igual ao sistema não gera movimentação ({sem_diferenca: true}).
-- Vale também para medicamento/residente desativado: o estoque físico existe.
-- Erros: sem_turno_aberto | medicamento_nao_encontrado | qtd_invalida
-- -----------------------------------------------------------------------------
create or replace function public.registrar_ajuste_estoque(
  p_medicamento_id     uuid,
  p_quantidade_contada numeric,
  p_observacao         text default null
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

  select coalesce(sum(quantidade), 0) into v_saldo
    from public.movimentacoes_estoque where medicamento_id = p_medicamento_id;

  v_diferenca := p_quantidade_contada - v_saldo;
  if v_diferenca = 0 then
    return jsonb_build_object('ok', true, 'sem_diferenca', true, 'saldo', v_saldo);
  end if;

  -- Quantidades são múltiplos de 0,5: inteiro sem casa decimal, meio com uma.
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

  return jsonb_build_object('ok', true, 'sem_diferenca', false,
                            'movimentacao_id', v_id, 'diferenca', v_diferenca,
                            'saldo', p_quantidade_contada);
end;
$$;

revoke execute on function
  public.registrar_ajuste_estoque(uuid, numeric, text)
  from public, anon;

-- -----------------------------------------------------------------------------
-- registrar_perda_estoque — quebra, vencimento, descarte de metade não
-- utilizada (DEC-013). Motivo OBRIGATÓRIO: perda sem explicação não conta a
-- história que a auditoria existe para contar.
-- Erros: sem_turno_aberto | medicamento_nao_encontrado | qtd_invalida |
--        motivo_obrigatorio
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

  select coalesce(sum(quantidade), 0) into v_saldo
    from public.movimentacoes_estoque where medicamento_id = p_medicamento_id;

  return jsonb_build_object('ok', true, 'movimentacao_id', v_id, 'saldo', v_saldo);
end;
$$;

revoke execute on function
  public.registrar_perda_estoque(uuid, numeric, text)
  from public, anon;

-- -----------------------------------------------------------------------------
-- criar_medicamento / atualizar_medicamento ganham p_estoque_minimo.
-- Assinatura muda → drop + recreate (create or replace criaria sobrecarga).
-- -----------------------------------------------------------------------------
drop function public.criar_medicamento(uuid, text, uuid, text, text, text, text, text);

create or replace function public.criar_medicamento(
  p_admin_id           uuid,
  p_admin_pin          text,
  p_idoso_id           uuid,
  p_nome               text,
  p_dosagem            text,
  p_forma_farmaceutica text,
  p_posologia          text,
  p_tipo               text,
  p_estoque_minimo     numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth jsonb;
  v_nome text;
  v_id   uuid;
begin
  v_auth := public.fn_autorizar_admin(p_admin_id, p_admin_pin);
  if not (v_auth ->> 'ok')::boolean then
    return v_auth;
  end if;

  if not exists (select 1 from public.idosos where id = p_idoso_id and ativo) then
    return jsonb_build_object('ok', false, 'erro', 'residente_nao_encontrado');
  end if;
  v_nome := trim(coalesce(p_nome, ''));
  if v_nome = '' then
    return jsonb_build_object('ok', false, 'erro', 'nome_obrigatorio');
  end if;
  if p_tipo not in ('continuo', 'sos') then
    return jsonb_build_object('ok', false, 'erro', 'tipo_invalido');
  end if;
  if p_estoque_minimo is not null
     and (p_estoque_minimo < 0 or mod(p_estoque_minimo * 2, 1) <> 0) then
    return jsonb_build_object('ok', false, 'erro', 'estoque_minimo_invalido');
  end if;
  if exists (select 1 from public.medicamentos
              where idoso_id = p_idoso_id and ativo
                and lower(nome) = lower(v_nome)
                and lower(coalesce(dosagem, '')) = lower(trim(coalesce(p_dosagem, '')))) then
    return jsonb_build_object('ok', false, 'erro', 'medicamento_duplicado');
  end if;

  insert into public.medicamentos
    (idoso_id, nome, dosagem, forma_farmaceutica, posologia, tipo, estoque_minimo)
  values
    (p_idoso_id, v_nome,
     nullif(trim(coalesce(p_dosagem, '')), ''),
     nullif(trim(coalesce(p_forma_farmaceutica, '')), ''),
     nullif(trim(coalesce(p_posologia, '')), ''),
     p_tipo, p_estoque_minimo)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'medicamento',
    jsonb_build_object('id', v_id, 'nome', v_nome, 'tipo', p_tipo));
end;
$$;

revoke execute on function
  public.criar_medicamento(uuid, text, uuid, text, text, text, text, text, numeric)
  from public, anon;

drop function public.atualizar_medicamento(uuid, text, uuid, text, text, text, text, text);

create or replace function public.atualizar_medicamento(
  p_admin_id           uuid,
  p_admin_pin          text,
  p_medicamento_id     uuid,
  p_nome               text,
  p_dosagem            text,
  p_forma_farmaceutica text,
  p_posologia          text,
  p_tipo               text,
  p_estoque_minimo     numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth    jsonb;
  v_nome    text;
  v_dosagem text;
  v_forma   text;
  v_atual   public.medicamentos;
begin
  v_auth := public.fn_autorizar_admin(p_admin_id, p_admin_pin);
  if not (v_auth ->> 'ok')::boolean then
    return v_auth;
  end if;

  select * into v_atual from public.medicamentos where id = p_medicamento_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'medicamento_nao_encontrado');
  end if;

  v_nome    := trim(coalesce(p_nome, ''));
  v_dosagem := nullif(trim(coalesce(p_dosagem, '')), '');
  v_forma   := nullif(trim(coalesce(p_forma_farmaceutica, '')), '');
  if v_nome = '' then
    return jsonb_build_object('ok', false, 'erro', 'nome_obrigatorio');
  end if;
  if p_tipo not in ('continuo', 'sos') then
    return jsonb_build_object('ok', false, 'erro', 'tipo_invalido');
  end if;
  if p_estoque_minimo is not null
     and (p_estoque_minimo < 0 or mod(p_estoque_minimo * 2, 1) <> 0) then
    return jsonb_build_object('ok', false, 'erro', 'estoque_minimo_invalido');
  end if;

  if (v_nome is distinct from v_atual.nome
      or v_dosagem is distinct from v_atual.dosagem
      or v_forma is distinct from v_atual.forma_farmaceutica)
     and exists (select 1 from public.administracoes a
                  where a.medicamento_id = p_medicamento_id) then
    return jsonb_build_object('ok', false, 'erro', 'medicamento_com_historico');
  end if;

  if p_tipo = 'sos' and v_atual.tipo = 'continuo'
     and exists (select 1 from public.horarios h
                  where h.medicamento_id = p_medicamento_id and h.ativo) then
    return jsonb_build_object('ok', false, 'erro', 'possui_horarios_ativos');
  end if;

  if exists (select 1 from public.medicamentos
              where idoso_id = v_atual.idoso_id and ativo
                and lower(nome) = lower(v_nome)
                and lower(coalesce(dosagem, '')) = lower(coalesce(v_dosagem, ''))
                and id <> p_medicamento_id) then
    return jsonb_build_object('ok', false, 'erro', 'medicamento_duplicado');
  end if;

  update public.medicamentos
     set nome               = v_nome,
         dosagem            = v_dosagem,
         forma_farmaceutica = v_forma,
         posologia          = nullif(trim(coalesce(p_posologia, '')), ''),
         tipo               = p_tipo,
         estoque_minimo     = p_estoque_minimo
   where id = p_medicamento_id;

  return jsonb_build_object('ok', true);
end;
$$;

revoke execute on function
  public.atualizar_medicamento(uuid, text, uuid, text, text, text, text, text, numeric)
  from public, anon;
