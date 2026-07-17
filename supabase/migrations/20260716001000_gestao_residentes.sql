-- =============================================================================
-- Migration: gestão de residentes (Sessão #3 — DEC-006, DEC-024)
--
-- 1) idosos.ativo: residentes saem por desativação, nunca DELETE — o histórico
--    de administrações precisa da linha para auditoria (mesmo racional da
--    DEC-006 para medicamentos/horários).
-- 2) RPCs de gestão (autorização de administradora — DEC-024) como único
--    caminho de escrita: INSERT/UPDATE diretos revogados do cliente.
-- 3) doses_do_turno passa a ignorar residentes desativados: os slots dos seus
--    medicamentos deixam de entrar na agenda da ronda (e no fechar_turno).
-- =============================================================================

alter table public.idosos
  add column ativo boolean not null default true;

revoke insert, update on table public.idosos from anon, authenticated;
drop policy idosos_insert_autenticado on public.idosos;
drop policy idosos_update_autenticado on public.idosos;

-- -----------------------------------------------------------------------------
-- criar_residente
-- -----------------------------------------------------------------------------
create or replace function public.criar_residente(
  p_admin_id    uuid,
  p_admin_pin   text,
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
  v_auth jsonb;
  v_nome text;
  v_id   uuid;
begin
  v_auth := public.fn_autorizar_admin(p_admin_id, p_admin_pin);
  if not (v_auth ->> 'ok')::boolean then
    return v_auth;
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

revoke execute on function public.criar_residente(uuid, text, text, date, text)
  from public, anon;

-- -----------------------------------------------------------------------------
-- atualizar_residente
-- -----------------------------------------------------------------------------
create or replace function public.atualizar_residente(
  p_admin_id    uuid,
  p_admin_pin   text,
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
  v_auth jsonb;
  v_nome text;
begin
  v_auth := public.fn_autorizar_admin(p_admin_id, p_admin_pin);
  if not (v_auth ->> 'ok')::boolean then
    return v_auth;
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

revoke execute on function public.atualizar_residente(uuid, text, uuid, text, date, text)
  from public, anon;

-- -----------------------------------------------------------------------------
-- definir_ativo_residente — desativação/reativação; NUNCA exclusão.
-- -----------------------------------------------------------------------------
create or replace function public.definir_ativo_residente(
  p_admin_id  uuid,
  p_admin_pin text,
  p_idoso_id  uuid,
  p_ativo     boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth  jsonb;
  v_atual public.idosos;
begin
  v_auth := public.fn_autorizar_admin(p_admin_id, p_admin_pin);
  if not (v_auth ->> 'ok')::boolean then
    return v_auth;
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

revoke execute on function public.definir_ativo_residente(uuid, text, uuid, boolean)
  from public, anon;

-- -----------------------------------------------------------------------------
-- doses_do_turno: residente desativado sai da agenda (mesma semântica já aceita
-- para horário desativado — pendência #2 do relatório da Sessão #2). Única
-- mudança em relação à Sessão #2: filtro i.ativo no CTE de slots.
-- -----------------------------------------------------------------------------
create or replace function public.doses_do_turno(p_turno_id uuid)
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
  situacao           text,
  administracao_id   uuid,
  status_tratativa   text,
  observacao         text
)
language sql
stable
security invoker
set search_path = ''
as $$
  with turno as (
    select t.inicio, least(coalesce(t.fim, now()), now()) as fim_efetivo
    from public.turnos t
    where t.id = p_turno_id
  ),
  dias as (
    select generate_series(
             (turno.inicio at time zone public.fn_fuso_casa())::date,
             (turno.fim_efetivo at time zone public.fn_fuso_casa())::date,
             interval '1 day'
           )::date as dia
    from turno
  ),
  slots as (
    select h.id as horario_id,
           h.medicamento_id,
           h.qtd_dose,
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
         case
           when a.id is not null then 'tratada'
           when now() > s.prevista_em + interval '30 minutes' then 'atrasada'
           else 'pendente'
         end,
         a.id,
         a.status,
         a.observacao
  from slots s
  join turno on s.prevista_em >= turno.inicio
            and s.prevista_em <= turno.fim_efetivo
  join public.medicamentos m on m.id = s.medicamento_id
  join public.idosos i on i.id = m.idoso_id
  left join public.administracoes a
    on a.horario_id = s.horario_id
   and a.prevista_em = s.prevista_em
  order by s.prevista_em, i.nome, m.nome;
$$;

revoke execute on function public.doses_do_turno(uuid) from public, anon;
