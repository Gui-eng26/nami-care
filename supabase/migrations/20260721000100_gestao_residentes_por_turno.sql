-- =============================================================================
-- Migration: gestão de residentes/medicamentos/prescrições autorizada por TURNO
-- (Sessão #8 — DEC-038, que inverte parcialmente a DEC-024)
--
-- POR QUÊ: a trava de PIN de administradora (DEC-024) não protegia o histórico
-- clínico — corrompia-o. A residente volta da consulta com prescrição nova; a
-- cuidadora do turno (profissional de saúde habilitada) aplica a mudança no
-- mundo real de qualquer jeito, mas não conseguia REGISTRÁ-LA sem a admin por
-- perto. A mudança acontecia fora do app e a trilha de auditoria sumia.
--
-- DEC-038: gestão de residentes, medicamentos e prescrições passa a autorizar
-- por `fn_cuidador_do_turno()` (exige turno aberto), o mesmo padrão das RPCs de
-- estoque da Sessão #4. A auditoria MELHORA: a alteração passa a ficar dentro do
-- app, no turno de quem a fez.
--
-- O que NÃO muda:
--   - DEC-026 (versionamento clínico): mudar dose/horário de medicamento já
--     administrado continua desativando a linha antiga e criando outra. É isso
--     que torna seguro abrir a edição — o histórico anterior segue fiel.
--   - Toda a validação de negócio de cada RPC (nome obrigatório, duplicidade por
--     catalogo_id, imutabilidade após uso, guardas de SOS/horário). Só muda a
--     autorização.
--   - Gestão de EQUIPE (criar/atualizar/desativar cuidadora, redefinir PIN,
--     autorizar_gestao) — segue sob `fn_autorizar_admin` (DEC-024 preservada
--     nesse escopo): é administração de QUEM TEM ACESSO, não ato de cuidado.
--
-- As assinaturas perdem p_admin_id/p_admin_pin → drop + recreate. As funções
-- continuam SECURITY DEFINER (a escrita direta nas tabelas segue revogada) e
-- voltam ao default de execute do schema, com o mesmo revoke de public/anon das
-- migrations anteriores.
--
-- Erro novo, coerente com as RPCs de estoque: sem turno aberto → sem_turno_aberto.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Residentes
-- -----------------------------------------------------------------------------
drop function public.criar_residente(uuid, text, text, date, text);

create or replace function public.criar_residente(
  p_nome        text,
  p_nascimento  date default null,
  p_observacoes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nome text;
  v_id   uuid;
begin
  if public.fn_cuidador_do_turno() is null then
    return jsonb_build_object('ok', false, 'erro', 'sem_turno_aberto');
  end if;

  v_nome := trim(coalesce(p_nome, ''));
  if v_nome = '' then
    return jsonb_build_object('ok', false, 'erro', 'nome_obrigatorio');
  end if;
  if exists (select 1 from public.idosos
              where ativo and lower(nome) = lower(v_nome)) then
    return jsonb_build_object('ok', false, 'erro', 'nome_duplicado');
  end if;
  if p_nascimento is not null and p_nascimento >= current_date then
    return jsonb_build_object('ok', false, 'erro', 'nascimento_invalido');
  end if;

  insert into public.idosos (nome, nascimento, observacoes)
  values (v_nome, p_nascimento, nullif(trim(coalesce(p_observacoes, '')), ''))
  returning id into v_id;

  return jsonb_build_object('ok', true, 'residente',
    jsonb_build_object('id', v_id, 'nome', v_nome));
end;
$$;

revoke execute on function public.criar_residente(text, date, text)
  from public, anon;

drop function public.atualizar_residente(uuid, text, uuid, text, date, text);

create or replace function public.atualizar_residente(
  p_idoso_id    uuid,
  p_nome        text,
  p_nascimento  date,
  p_observacoes text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nome text;
begin
  if public.fn_cuidador_do_turno() is null then
    return jsonb_build_object('ok', false, 'erro', 'sem_turno_aberto');
  end if;

  v_nome := trim(coalesce(p_nome, ''));
  if v_nome = '' then
    return jsonb_build_object('ok', false, 'erro', 'nome_obrigatorio');
  end if;
  if exists (select 1 from public.idosos
              where ativo and lower(nome) = lower(v_nome)
                and id <> p_idoso_id) then
    return jsonb_build_object('ok', false, 'erro', 'nome_duplicado');
  end if;
  if p_nascimento is not null and p_nascimento >= current_date then
    return jsonb_build_object('ok', false, 'erro', 'nascimento_invalido');
  end if;

  update public.idosos
     set nome        = v_nome,
         nascimento  = p_nascimento,
         observacoes = nullif(trim(coalesce(p_observacoes, '')), '')
   where id = p_idoso_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'residente_nao_encontrado');
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

revoke execute on function public.atualizar_residente(uuid, text, date, text)
  from public, anon;

drop function public.definir_ativo_residente(uuid, text, uuid, boolean);

create or replace function public.definir_ativo_residente(
  p_idoso_id uuid,
  p_ativo    boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_atual public.idosos;
begin
  if public.fn_cuidador_do_turno() is null then
    return jsonb_build_object('ok', false, 'erro', 'sem_turno_aberto');
  end if;

  select * into v_atual from public.idosos where id = p_idoso_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'residente_nao_encontrado');
  end if;
  if v_atual.ativo = p_ativo then
    return jsonb_build_object('ok', true);
  end if;
  if p_ativo and exists (select 1 from public.idosos
                          where ativo and lower(nome) = lower(v_atual.nome)
                            and id <> p_idoso_id) then
    return jsonb_build_object('ok', false, 'erro', 'nome_duplicado');
  end if;

  update public.idosos set ativo = p_ativo where id = p_idoso_id;
  return jsonb_build_object('ok', true);
end;
$$;

revoke execute on function public.definir_ativo_residente(uuid, boolean)
  from public, anon;

-- -----------------------------------------------------------------------------
-- Medicamentos (regras do catálogo — DEC-035 — preservadas na íntegra)
-- -----------------------------------------------------------------------------
drop function public.criar_medicamento(uuid, text, uuid, uuid, text, text, text, text, text, numeric);

create or replace function public.criar_medicamento(
  p_idoso_id           uuid,
  p_catalogo_id        uuid,
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
  v_cat         public.catalogo_medicamentos;
  v_catalogo_id uuid;
  v_nome        text;
  v_dosagem     text;
  v_forma       text;
  v_id          uuid;
begin
  if public.fn_cuidador_do_turno() is null then
    return jsonb_build_object('ok', false, 'erro', 'sem_turno_aberto');
  end if;

  if not exists (select 1 from public.idosos where id = p_idoso_id and ativo) then
    return jsonb_build_object('ok', false, 'erro', 'residente_nao_encontrado');
  end if;
  if p_tipo not in ('continuo', 'sos') then
    return jsonb_build_object('ok', false, 'erro', 'tipo_invalido');
  end if;
  if p_estoque_minimo is not null
     and (p_estoque_minimo < 0 or mod(p_estoque_minimo * 2, 1) <> 0) then
    return jsonb_build_object('ok', false, 'erro', 'estoque_minimo_invalido');
  end if;

  if p_catalogo_id is not null then
    select * into v_cat from public.catalogo_medicamentos where id = p_catalogo_id;
    if not found then
      return jsonb_build_object('ok', false, 'erro', 'catalogo_nao_encontrado');
    end if;
    v_catalogo_id := v_cat.id;
    v_nome    := v_cat.nome;
    v_dosagem := v_cat.dosagem;
    v_forma   := v_cat.forma_farmaceutica;
  else
    v_nome := trim(coalesce(p_nome, ''));
    if v_nome = '' then
      return jsonb_build_object('ok', false, 'erro', 'nome_obrigatorio');
    end if;
    v_dosagem := nullif(trim(coalesce(p_dosagem, '')), '');
    v_forma   := nullif(trim(coalesce(p_forma_farmaceutica, '')), '');
    insert into public.catalogo_medicamentos (nome, dosagem, forma_farmaceutica)
    values (v_nome, v_dosagem, v_forma)
    returning id into v_catalogo_id;
  end if;

  if exists (select 1 from public.medicamentos
              where idoso_id = p_idoso_id and ativo and catalogo_id = v_catalogo_id) then
    return jsonb_build_object('ok', false, 'erro', 'medicamento_duplicado');
  end if;

  insert into public.medicamentos
    (idoso_id, catalogo_id, nome, dosagem, forma_farmaceutica, posologia, tipo, estoque_minimo)
  values
    (p_idoso_id, v_catalogo_id, v_nome, v_dosagem, v_forma,
     nullif(trim(coalesce(p_posologia, '')), ''), p_tipo, p_estoque_minimo)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'medicamento',
    jsonb_build_object('id', v_id, 'nome', v_nome, 'tipo', p_tipo,
                       'catalogo_id', v_catalogo_id));
end;
$$;

revoke execute on function
  public.criar_medicamento(uuid, uuid, text, text, text, text, text, numeric)
  from public, anon;

drop function public.atualizar_medicamento(uuid, text, uuid, uuid, text, text, text, text, text, numeric);

create or replace function public.atualizar_medicamento(
  p_medicamento_id     uuid,
  p_catalogo_id        uuid,
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
  v_atual       public.medicamentos;
  v_cat         public.catalogo_medicamentos;
  v_catalogo_id uuid;
  v_nome        text;
  v_dosagem     text;
  v_forma       text;
begin
  if public.fn_cuidador_do_turno() is null then
    return jsonb_build_object('ok', false, 'erro', 'sem_turno_aberto');
  end if;

  select * into v_atual from public.medicamentos where id = p_medicamento_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'medicamento_nao_encontrado');
  end if;
  if p_tipo not in ('continuo', 'sos') then
    return jsonb_build_object('ok', false, 'erro', 'tipo_invalido');
  end if;
  if p_estoque_minimo is not null
     and (p_estoque_minimo < 0 or mod(p_estoque_minimo * 2, 1) <> 0) then
    return jsonb_build_object('ok', false, 'erro', 'estoque_minimo_invalido');
  end if;

  if p_catalogo_id is not null then
    select * into v_cat from public.catalogo_medicamentos where id = p_catalogo_id;
    if not found then
      return jsonb_build_object('ok', false, 'erro', 'catalogo_nao_encontrado');
    end if;
    v_catalogo_id := v_cat.id;
    v_nome    := v_cat.nome;
    v_dosagem := v_cat.dosagem;
    v_forma   := v_cat.forma_farmaceutica;
  else
    v_nome := trim(coalesce(p_nome, ''));
    if v_nome = '' then
      return jsonb_build_object('ok', false, 'erro', 'nome_obrigatorio');
    end if;
    v_dosagem := nullif(trim(coalesce(p_dosagem, '')), '');
    v_forma   := nullif(trim(coalesce(p_forma_farmaceutica, '')), '');
    insert into public.catalogo_medicamentos (nome, dosagem, forma_farmaceutica)
    values (v_nome, v_dosagem, v_forma)
    returning id into v_catalogo_id;
  end if;

  if v_catalogo_id is distinct from v_atual.catalogo_id
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
                and catalogo_id = v_catalogo_id
                and id <> p_medicamento_id) then
    return jsonb_build_object('ok', false, 'erro', 'medicamento_duplicado');
  end if;

  update public.medicamentos
     set catalogo_id        = v_catalogo_id,
         nome               = v_nome,
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
  public.atualizar_medicamento(uuid, uuid, text, text, text, text, text, numeric)
  from public, anon;

drop function public.definir_ativo_medicamento(uuid, text, uuid, boolean);

create or replace function public.definir_ativo_medicamento(
  p_medicamento_id uuid,
  p_ativo          boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_atual public.medicamentos;
begin
  if public.fn_cuidador_do_turno() is null then
    return jsonb_build_object('ok', false, 'erro', 'sem_turno_aberto');
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

revoke execute on function public.definir_ativo_medicamento(uuid, boolean)
  from public, anon;

-- -----------------------------------------------------------------------------
-- Horários (prescrição). O versionamento da DEC-026 em atualizar_horario segue
-- palavra por palavra o que já estava lá — é ele que torna seguro abrir a
-- edição de prescrição à cuidadora do turno.
-- -----------------------------------------------------------------------------
drop function public.criar_horario(uuid, text, uuid, time without time zone, numeric);

create or replace function public.criar_horario(
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
  v_med public.medicamentos;
  v_id  uuid;
begin
  if public.fn_cuidador_do_turno() is null then
    return jsonb_build_object('ok', false, 'erro', 'sem_turno_aberto');
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

revoke execute on function public.criar_horario(uuid, time, numeric)
  from public, anon;

drop function public.atualizar_horario(uuid, text, uuid, time without time zone, numeric);

create or replace function public.atualizar_horario(
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
  v_atual public.horarios;
  v_novo  uuid;
begin
  if public.fn_cuidador_do_turno() is null then
    return jsonb_build_object('ok', false, 'erro', 'sem_turno_aberto');
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

  -- DEC-026: com histórico, versiona (desativa + cria); nunca sobrescreve.
  if exists (select 1 from public.administracoes a
              where a.horario_id = p_horario_id) then
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

revoke execute on function public.atualizar_horario(uuid, time, numeric)
  from public, anon;

drop function public.definir_ativo_horario(uuid, text, uuid, boolean);

create or replace function public.definir_ativo_horario(
  p_horario_id uuid,
  p_ativo      boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_atual public.horarios;
  v_tipo  text;
begin
  if public.fn_cuidador_do_turno() is null then
    return jsonb_build_object('ok', false, 'erro', 'sem_turno_aberto');
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

revoke execute on function public.definir_ativo_horario(uuid, boolean)
  from public, anon;
