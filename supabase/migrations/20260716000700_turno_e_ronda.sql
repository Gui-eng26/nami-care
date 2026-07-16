-- =============================================================================
-- Migration: fluxo de turno e ronda de medicação (DEC-019, DEC-022, DEC-023)
--
-- 1) Turno: no máximo UM turno aberto por vez (dispositivo único, DEC-002);
--    abertura só via RPC abrir_turno (PIN + rate limit da DEC-021) e
--    fechamento só via RPC fechar_turno (bloqueado enquanto houver dose devida
--    sem tratativa — DEC-010). Grants de INSERT/UPDATE em turnos são revogados
--    do cliente para que as RPCs sejam o único caminho.
-- 2) Dose de ronda ancorada no slot: administracoes.prevista_em carrega o
--    instante agendado (dia + horarios.hora no fuso da casa). UNIQUE
--    (horario_id, prevista_em) impede dupla tratativa do mesmo slot.
--    NULL em ambos = dose avulsa (SOS, DEC-014).
-- 3) Toda administração exige turno aberto do cuidador informado (DEC-019:
--    quem age é o cuidador do turno, nunca o usuário Supabase da casa).
-- 4) doses_do_turno: fonte única da agenda do turno (usada pela tela da ronda
--    e pelo fechar_turno — nenhuma lógica de slots duplicada no cliente).
-- =============================================================================

-- Fuso da casa de repouso (piloto: uma única casa — Campinas/SP).
create or replace function public.fn_fuso_casa()
returns text
language sql
immutable
as $$ select 'America/Sao_Paulo' $$;

-- -----------------------------------------------------------------------------
-- Turnos: um aberto por vez; escrita só via RPC.
-- -----------------------------------------------------------------------------
create unique index turnos_apenas_um_aberto_idx
  on public.turnos ((fim is null))
  where fim is null;

-- Turno pode abrir e fechar no mesmo instante (fim = inicio): now() é fixo por
-- transação e a regra original (fim > inicio) rejeitava esse caso-limite.
alter table public.turnos
  drop constraint turnos_fim_apos_inicio;
alter table public.turnos
  add constraint turnos_fim_apos_inicio
    check (fim is null or fim >= inicio);

revoke insert, update, delete on table public.turnos from anon, authenticated;
drop policy turnos_insert_autenticado on public.turnos;
drop policy turnos_update_autenticado on public.turnos;

-- -----------------------------------------------------------------------------
-- administracoes.prevista_em — instante agendado do slot tratado.
-- -----------------------------------------------------------------------------
alter table public.administracoes
  add column prevista_em timestamptz;

alter table public.administracoes
  add constraint administracoes_prevista_so_na_ronda
    check ((horario_id is null) = (prevista_em is null));

alter table public.administracoes
  add constraint administracoes_slot_unico
    unique (horario_id, prevista_em);

-- prevista_em entra no rol de campos imutáveis da auditoria (DEC-017).
create or replace function public.fn_administracao_imutavel()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status is distinct from old.status
     or new.qtd is distinct from old.qtd
     or new.medicamento_id is distinct from old.medicamento_id
     or new.horario_id is distinct from old.horario_id
     or new.cuidador_id is distinct from old.cuidador_id
     or new.registrado_em is distinct from old.registrado_em
     or new.prevista_em is distinct from old.prevista_em then
    raise exception
      'Administração é imutável (auditoria): corrija com novo registro e ajuste de estoque';
  end if;
  return new;
end;
$$;

-- Administração só dentro de turno aberto do próprio cuidador (DEC-019/DEC-022).
create or replace function public.fn_administracao_exige_turno()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.turnos t
    where t.cuidador_id = new.cuidador_id and t.fim is null
  ) then
    raise exception
      'Administração exige turno aberto do cuidador informado (DEC-019)';
  end if;
  return new;
end;
$$;

create trigger trg_administracao_exige_turno
  before insert on public.administracoes
  for each row execute function public.fn_administracao_exige_turno();

-- -----------------------------------------------------------------------------
-- doses_do_turno — agenda do turno: todos os slots (horário ativo × dia) de
-- medicamento contínuo ativo cujo instante previsto caiu dentro do turno,
-- com a situação de cada um:
--   tratada  = já existe administração para o slot
--   pendente = devida, sem tratativa, dentro da tolerância de 30 min (DEC-010)
--   atrasada = devida, sem tratativa, tolerância estourada
-- SECURITY INVOKER: roda com o RLS do chamador.
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
    cross join dias d
    where h.ativo
      and m.ativo
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

-- -----------------------------------------------------------------------------
-- abrir_turno — verificação de PIN server-side (DEC-020) + rate limit
-- (DEC-021) + abertura/retomada do turno. SECURITY DEFINER: é a única forma de
-- ler pin_hash/tentativas_pin e inserir em turnos.
-- Retornos (jsonb): {ok:true, retomado, turno:{...}} ou {ok:false, erro:...}
--   erros: pin_invalido | cuidador_nao_encontrado | pin_bloqueado (+ desbloqueia_em)
--          pin_incorreto (+ tentativas_restantes) | turno_aberto_outro_cuidador
-- -----------------------------------------------------------------------------
create or replace function public.abrir_turno(p_cuidador_id uuid, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c_max_falhas constant int := 5;
  c_janela     constant interval := interval '15 minutes';
  v_cuidador     public.cuidadores;
  v_falhas       int;
  v_desbloqueia  timestamptz;
  v_turno        public.turnos;
begin
  if p_pin is null or p_pin !~ '^[0-9]{4,6}$' then
    return jsonb_build_object('ok', false, 'erro', 'pin_invalido');
  end if;

  select * into v_cuidador
    from public.cuidadores
   where id = p_cuidador_id and ativo;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'cuidador_nao_encontrado');
  end if;

  -- DEC-021: bloqueia quando as últimas c_max_falhas falhas cabem na janela;
  -- desbloqueia quando a mais antiga delas completa c_janela.
  select count(*), min(tentado_em) + c_janela
    into v_falhas, v_desbloqueia
    from (
      select tentado_em
        from public.tentativas_pin
       where cuidador_id = p_cuidador_id
         and not sucesso
         and tentado_em > now() - c_janela
       order by tentado_em desc
       limit c_max_falhas
    ) ultimas_falhas;

  if v_falhas >= c_max_falhas then
    return jsonb_build_object('ok', false, 'erro', 'pin_bloqueado',
                              'desbloqueia_em', v_desbloqueia);
  end if;

  if v_cuidador.pin_hash <> extensions.crypt(p_pin, v_cuidador.pin_hash) then
    insert into public.tentativas_pin (cuidador_id, sucesso)
    values (p_cuidador_id, false);
    return jsonb_build_object('ok', false, 'erro', 'pin_incorreto',
                              'tentativas_restantes',
                              greatest(c_max_falhas - v_falhas - 1, 0));
  end if;

  insert into public.tentativas_pin (cuidador_id, sucesso)
  values (p_cuidador_id, true);

  select * into v_turno from public.turnos where fim is null limit 1;
  if found then
    if v_turno.cuidador_id = p_cuidador_id then
      -- Retomada: mesmo cuidador reautentica no turno já aberto (DEC-002).
      return jsonb_build_object('ok', true, 'retomado', true, 'turno',
        jsonb_build_object('id', v_turno.id, 'cuidador_id', v_turno.cuidador_id,
                           'cuidador_nome', v_cuidador.nome, 'inicio', v_turno.inicio));
    end if;
    return jsonb_build_object('ok', false, 'erro', 'turno_aberto_outro_cuidador',
      'turno', jsonb_build_object('id', v_turno.id, 'cuidador_id', v_turno.cuidador_id,
                                  'inicio', v_turno.inicio));
  end if;

  begin
    insert into public.turnos (cuidador_id)
    values (p_cuidador_id)
    returning * into v_turno;
  exception when unique_violation then
    -- corrida: outro turno abriu entre a checagem e o insert
    return jsonb_build_object('ok', false, 'erro', 'turno_aberto_outro_cuidador');
  end;

  return jsonb_build_object('ok', true, 'retomado', false, 'turno',
    jsonb_build_object('id', v_turno.id, 'cuidador_id', v_turno.cuidador_id,
                       'cuidador_nome', v_cuidador.nome, 'inicio', v_turno.inicio));
end;
$$;

revoke execute on function public.abrir_turno(uuid, text) from public, anon;

-- -----------------------------------------------------------------------------
-- fechar_turno — fechamento obrigatório (DEC-010): só fecha quando TODA dose
-- devida do turno tem tratativa; devolve a lista do que falta caso contrário.
-- Dose dentro da tolerância mas sem tratativa também impede o fechamento.
-- -----------------------------------------------------------------------------
create or replace function public.fechar_turno(p_turno_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_turno     public.turnos;
  v_total     int;
  v_pendentes jsonb;
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
    into v_total, v_pendentes
    from public.doses_do_turno(p_turno_id) d
   where d.situacao <> 'tratada';

  if v_total > 0 then
    return jsonb_build_object('ok', false, 'erro', 'doses_pendentes',
                              'total', v_total, 'doses', v_pendentes);
  end if;

  update public.turnos set fim = now() where id = p_turno_id;
  return jsonb_build_object('ok', true, 'turno_id', p_turno_id, 'fim', now());
end;
$$;

revoke execute on function public.fechar_turno(uuid) from public, anon;
