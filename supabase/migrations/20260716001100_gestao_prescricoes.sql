-- =============================================================================
-- Migration: gestão de medicamentos e prescrições (Sessão #3 — DEC-024, DEC-026)
--
-- 1) Imutabilidade clínica (DEC-026): após a primeira administração, os campos
--    que dão significado ao histórico ficam imutáveis — medicamentos (nome,
--    dosagem, forma_farmaceutica) e horarios (hora, qtd_dose). Garantido por
--    TRIGGER (vale por qualquer caminho de escrita, não só pelas RPCs).
--    Alterar prescrição com histórico = desativar a linha antiga + criar nova
--    (a RPC atualizar_horario faz as duas coisas numa chamada). posologia é
--    texto de orientação e permanece sempre editável.
-- 2) Índice único parcial (medicamento_id, hora) where ativo: sem dois horários
--    ativos iguais para o mesmo medicamento.
-- 3) RPCs com autorização de administradora (DEC-024) como único caminho de
--    escrita; INSERT/UPDATE diretos revogados do cliente.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Imutabilidade clínica após uso (DEC-026).
-- -----------------------------------------------------------------------------
create or replace function public.fn_medicamento_imutavel_apos_uso()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if (new.nome is distinct from old.nome
      or new.dosagem is distinct from old.dosagem
      or new.forma_farmaceutica is distinct from old.forma_farmaceutica)
     and exists (select 1 from public.administracoes a
                  where a.medicamento_id = old.id) then
    raise exception
      'Medicamento com administrações registradas tem nome/dosagem/forma imutáveis (DEC-026): desative e cadastre a nova versão';
  end if;
  return new;
end;
$$;

create trigger trg_medicamento_imutavel_apos_uso
  before update of nome, dosagem, forma_farmaceutica on public.medicamentos
  for each row execute function public.fn_medicamento_imutavel_apos_uso();

create or replace function public.fn_horario_imutavel_apos_uso()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if (new.hora is distinct from old.hora
      or new.qtd_dose is distinct from old.qtd_dose)
     and exists (select 1 from public.administracoes a
                  where a.horario_id = old.id) then
    raise exception
      'Horário com administrações registradas tem hora/dose imutáveis (DEC-026): desative e cadastre a nova versão';
  end if;
  return new;
end;
$$;

create trigger trg_horario_imutavel_apos_uso
  before update of hora, qtd_dose on public.horarios
  for each row execute function public.fn_horario_imutavel_apos_uso();

-- Sem dois horários ativos iguais para o mesmo medicamento (DEC-026).
create unique index horarios_ativo_hora_unico_idx
  on public.horarios (medicamento_id, hora)
  where ativo;

-- -----------------------------------------------------------------------------
-- Escrita direta sai do cliente: RPCs como único caminho (padrão Sessão #2).
-- -----------------------------------------------------------------------------
revoke insert, update on table public.medicamentos from anon, authenticated;
drop policy medicamentos_insert_autenticado on public.medicamentos;
drop policy medicamentos_update_autenticado on public.medicamentos;

revoke insert, update on table public.horarios from anon, authenticated;
drop policy horarios_insert_autenticado on public.horarios;
drop policy horarios_update_autenticado on public.horarios;

-- -----------------------------------------------------------------------------
-- criar_medicamento
-- -----------------------------------------------------------------------------
create or replace function public.criar_medicamento(
  p_admin_id           uuid,
  p_admin_pin          text,
  p_idoso_id           uuid,
  p_nome               text,
  p_dosagem            text,
  p_forma_farmaceutica text,
  p_posologia          text,
  p_tipo               text
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
  if exists (select 1 from public.medicamentos
              where idoso_id = p_idoso_id and ativo
                and lower(nome) = lower(v_nome)
                and lower(coalesce(dosagem, '')) = lower(trim(coalesce(p_dosagem, '')))) then
    return jsonb_build_object('ok', false, 'erro', 'medicamento_duplicado');
  end if;

  insert into public.medicamentos
    (idoso_id, nome, dosagem, forma_farmaceutica, posologia, tipo)
  values
    (p_idoso_id, v_nome,
     nullif(trim(coalesce(p_dosagem, '')), ''),
     nullif(trim(coalesce(p_forma_farmaceutica, '')), ''),
     nullif(trim(coalesce(p_posologia, '')), ''),
     p_tipo)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'medicamento',
    jsonb_build_object('id', v_id, 'nome', v_nome, 'tipo', p_tipo));
end;
$$;

revoke execute on function
  public.criar_medicamento(uuid, text, uuid, text, text, text, text, text)
  from public, anon;

-- -----------------------------------------------------------------------------
-- atualizar_medicamento — com histórico, só posologia (e tipo, com as guardas
-- existentes) podem mudar; nome/dosagem/forma exigem nova versão (DEC-026).
-- -----------------------------------------------------------------------------
create or replace function public.atualizar_medicamento(
  p_admin_id           uuid,
  p_admin_pin          text,
  p_medicamento_id     uuid,
  p_nome               text,
  p_dosagem            text,
  p_forma_farmaceutica text,
  p_posologia          text,
  p_tipo               text
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
         tipo               = p_tipo
   where id = p_medicamento_id;

  return jsonb_build_object('ok', true);
end;
$$;

revoke execute on function
  public.atualizar_medicamento(uuid, text, uuid, text, text, text, text, text)
  from public, anon;

-- -----------------------------------------------------------------------------
-- definir_ativo_medicamento — desativação/reativação; NUNCA exclusão (DEC-006).
-- -----------------------------------------------------------------------------
create or replace function public.definir_ativo_medicamento(
  p_admin_id       uuid,
  p_admin_pin      text,
  p_medicamento_id uuid,
  p_ativo          boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth  jsonb;
  v_atual public.medicamentos;
begin
  v_auth := public.fn_autorizar_admin(p_admin_id, p_admin_pin);
  if not (v_auth ->> 'ok')::boolean then
    return v_auth;
  end if;

  select * into v_atual from public.medicamentos where id = p_medicamento_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'medicamento_nao_encontrado');
  end if;
  if v_atual.ativo = p_ativo then
    return jsonb_build_object('ok', true);
  end if;
  if p_ativo and exists (select 1 from public.medicamentos
                          where idoso_id = v_atual.idoso_id and ativo
                            and lower(nome) = lower(v_atual.nome)
                            and lower(coalesce(dosagem, '')) =
                                lower(coalesce(v_atual.dosagem, ''))
                            and id <> p_medicamento_id) then
    return jsonb_build_object('ok', false, 'erro', 'medicamento_duplicado');
  end if;

  update public.medicamentos set ativo = p_ativo where id = p_medicamento_id;
  return jsonb_build_object('ok', true);
end;
$$;

revoke execute on function public.definir_ativo_medicamento(uuid, text, uuid, boolean)
  from public, anon;

-- -----------------------------------------------------------------------------
-- criar_horario — só para medicamento contínuo (DEC-014); dose em passos de
-- 0,5 (DEC-013).
-- -----------------------------------------------------------------------------
create or replace function public.criar_horario(
  p_admin_id       uuid,
  p_admin_pin      text,
  p_medicamento_id uuid,
  p_hora           time,
  p_qtd_dose       numeric
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth jsonb;
  v_med  public.medicamentos;
  v_id   uuid;
begin
  v_auth := public.fn_autorizar_admin(p_admin_id, p_admin_pin);
  if not (v_auth ->> 'ok')::boolean then
    return v_auth;
  end if;

  select * into v_med from public.medicamentos where id = p_medicamento_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'medicamento_nao_encontrado');
  end if;
  if v_med.tipo <> 'continuo' then
    return jsonb_build_object('ok', false, 'erro', 'medicamento_sos');
  end if;
  if p_hora is null then
    return jsonb_build_object('ok', false, 'erro', 'hora_obrigatoria');
  end if;
  if p_qtd_dose is null or p_qtd_dose <= 0 or mod(p_qtd_dose * 2, 1) <> 0 then
    return jsonb_build_object('ok', false, 'erro', 'qtd_invalida');
  end if;

  begin
    insert into public.horarios (medicamento_id, hora, qtd_dose)
    values (p_medicamento_id, p_hora, p_qtd_dose)
    returning id into v_id;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'erro', 'horario_duplicado');
  end;

  return jsonb_build_object('ok', true, 'horario',
    jsonb_build_object('id', v_id, 'hora', p_hora, 'qtd_dose', p_qtd_dose));
end;
$$;

revoke execute on function public.criar_horario(uuid, text, uuid, time, numeric)
  from public, anon;

-- -----------------------------------------------------------------------------
-- atualizar_horario — versionamento automático (DEC-026): sem histórico, edita
-- in-place (janela de correção de digitação); com histórico, desativa a linha
-- antiga e cria a nova versão na mesma transação.
-- Retorno inclui horario_id (o novo, quando versionado) e versionado (bool).
-- -----------------------------------------------------------------------------
create or replace function public.atualizar_horario(
  p_admin_id   uuid,
  p_admin_pin  text,
  p_horario_id uuid,
  p_hora       time,
  p_qtd_dose   numeric
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth  jsonb;
  v_atual public.horarios;
  v_novo  uuid;
begin
  v_auth := public.fn_autorizar_admin(p_admin_id, p_admin_pin);
  if not (v_auth ->> 'ok')::boolean then
    return v_auth;
  end if;

  select * into v_atual from public.horarios where id = p_horario_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'horario_nao_encontrado');
  end if;
  if not v_atual.ativo then
    return jsonb_build_object('ok', false, 'erro', 'horario_inativo');
  end if;
  if p_hora is null then
    return jsonb_build_object('ok', false, 'erro', 'hora_obrigatoria');
  end if;
  if p_qtd_dose is null or p_qtd_dose <= 0 or mod(p_qtd_dose * 2, 1) <> 0 then
    return jsonb_build_object('ok', false, 'erro', 'qtd_invalida');
  end if;
  if p_hora = v_atual.hora and p_qtd_dose = v_atual.qtd_dose then
    return jsonb_build_object('ok', true, 'horario_id', p_horario_id,
                              'versionado', false);
  end if;
  if exists (select 1 from public.horarios
              where medicamento_id = v_atual.medicamento_id and ativo
                and hora = p_hora and id <> p_horario_id) then
    return jsonb_build_object('ok', false, 'erro', 'horario_duplicado');
  end if;

  if exists (select 1 from public.administracoes a
              where a.horario_id = p_horario_id) then
    -- Versão nova: a linha antiga permanece para a leitura fiel do histórico.
    update public.horarios set ativo = false where id = p_horario_id;
    insert into public.horarios (medicamento_id, hora, qtd_dose)
    values (v_atual.medicamento_id, p_hora, p_qtd_dose)
    returning id into v_novo;
    return jsonb_build_object('ok', true, 'horario_id', v_novo,
                              'versionado', true);
  end if;

  update public.horarios
     set hora = p_hora, qtd_dose = p_qtd_dose
   where id = p_horario_id;
  return jsonb_build_object('ok', true, 'horario_id', p_horario_id,
                            'versionado', false);
end;
$$;

revoke execute on function public.atualizar_horario(uuid, text, uuid, time, numeric)
  from public, anon;

-- -----------------------------------------------------------------------------
-- definir_ativo_horario — desativação/reativação; NUNCA exclusão (DEC-006).
-- -----------------------------------------------------------------------------
create or replace function public.definir_ativo_horario(
  p_admin_id   uuid,
  p_admin_pin  text,
  p_horario_id uuid,
  p_ativo      boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth  jsonb;
  v_atual public.horarios;
  v_tipo  text;
begin
  v_auth := public.fn_autorizar_admin(p_admin_id, p_admin_pin);
  if not (v_auth ->> 'ok')::boolean then
    return v_auth;
  end if;

  select * into v_atual from public.horarios where id = p_horario_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'horario_nao_encontrado');
  end if;
  if v_atual.ativo = p_ativo then
    return jsonb_build_object('ok', true);
  end if;

  if p_ativo then
    select tipo into v_tipo from public.medicamentos
     where id = v_atual.medicamento_id;
    if v_tipo <> 'continuo' then
      return jsonb_build_object('ok', false, 'erro', 'medicamento_sos');
    end if;
  end if;

  begin
    update public.horarios set ativo = p_ativo where id = p_horario_id;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'erro', 'horario_duplicado');
  end;

  return jsonb_build_object('ok', true);
end;
$$;

revoke execute on function public.definir_ativo_horario(uuid, text, uuid, boolean)
  from public, anon;
