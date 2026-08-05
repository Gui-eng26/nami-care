-- SESSÃO 16 — Parte 3 (DEC-055): recorrência por horário.
--
-- Problema: doses_do_turno faz cross join de todo horário ativo × todo dia do
-- turno — a frequência é sempre diária, implícita (limitação já conhecida,
-- DEC-027). A recorrência mora NO HORÁRIO, não no medicamento: o caso real que
-- motiva isso é um omeprazol em dias alternados, com 8h a cada 2 dias e 20h a
-- cada 4 dias — um padrão único no medicamento não representaria isso.
--
-- Migration ADITIVA e RETROCOMPATÍVEL (regra permanente da Sessão #16, Parte
-- 0): os 4 parâmetros novos de criar_horario/atualizar_horario têm default —
-- o frontend atual (que só manda p_hora/p_qtd_dose) continua funcionando sem
-- mudança, criando horário 'diario' como sempre. A tela de recorrência
-- (seletor de modo, dias da semana, calendário de conferência) é a Parte 6.

begin;

-- 1) Colunas de recorrência em horarios ------------------------------------

alter table public.horarios
  add column recorrencia_tipo text not null default 'diario',
  add column dias_semana int[],
  add column intervalo_dias int,
  add column data_referencia date;

alter table public.horarios
  add constraint horarios_recorrencia_tipo_check
    check (recorrencia_tipo in ('diario', 'dias_semana', 'intervalo'));

-- Presença condicional exata (mesmo padrão de gotas_por_ml/volume_frasco_ml
-- da Sessão #15): cada tipo exige exatamente os campos que lhe dizem respeito.
alter table public.horarios
  add constraint horarios_recorrencia_presenca_check
    check (
      (recorrencia_tipo = 'diario'
        and dias_semana is null and intervalo_dias is null and data_referencia is null)
      or (recorrencia_tipo = 'dias_semana'
        and dias_semana is not null and intervalo_dias is null and data_referencia is null)
      or (recorrencia_tipo = 'intervalo'
        and dias_semana is null and intervalo_dias is not null and data_referencia is not null)
    );

-- Postgres não aceita subquery direto em CHECK; a validação de "sem
-- repetição" precisa de unnest+distinct, então vira função auxiliar.
create or replace function public.fn_array_sem_repeticao(arr int[])
returns boolean
language sql
immutable
as $$
  select cardinality(arr) = cardinality(array(select distinct unnest(arr)))
$$;

alter table public.horarios
  add constraint horarios_dias_semana_valido_check
    check (
      dias_semana is null or (
        cardinality(dias_semana) > 0
        and dias_semana <@ array[1,2,3,4,5,6,7]
        and public.fn_array_sem_repeticao(dias_semana)
      )
    );

alter table public.horarios
  add constraint horarios_intervalo_dias_valido_check
    check (intervalo_dias is null or intervalo_dias > 1);

comment on column public.horarios.recorrencia_tipo is
  'diario | dias_semana | intervalo (DEC-055). Backfill: todo horário existente é diario — comportamento idêntico ao de antes desta migration.';
comment on column public.horarios.data_referencia is
  'Âncora do ciclo de "intervalo" (ex.: a cada 2 dias a partir daqui). Nos dias da semana a própria semana já é a âncora, por isso só existe para intervalo.';

-- 2) doses_do_turno filtra pela recorrência de cada horário ------------------
--
-- Backfill deixou todo horário existente como 'diario', então o primeiro
-- ramo do OR abaixo é sempre verdadeiro para eles — zero mudança de
-- comportamento para o caso hoje esmagadoramente majoritário (regressão
-- obrigatória da Parte 0). Dia da semana e contagem de intervalo usam d.dia,
-- que já vem calculado no fuso da casa (fn_fuso_casa) pelo CTE `dias`.

create or replace function public.doses_do_turno(p_turno_id uuid)
returns table(horario_id uuid, medicamento_id uuid, idoso_id uuid, nome_idoso text, nome_medicamento text, dosagem text, forma_farmaceutica text, qtd_dose numeric, prevista_em timestamp with time zone, situacao text, administracao_id uuid, status_tratativa text, observacao text)
language sql
stable
set search_path to ''
as $function$
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
      and (
        h.recorrencia_tipo = 'diario'
        or (h.recorrencia_tipo = 'dias_semana'
            and extract(isodow from d.dia)::int = any(h.dias_semana))
        or (h.recorrencia_tipo = 'intervalo'
            and d.dia >= h.data_referencia
            and mod((d.dia - h.data_referencia), h.intervalo_dias) = 0)
      )
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
           when now() > s.prevista_em + interval '60 minutes' then 'atrasada'
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
$function$;

-- 3) Imutabilidade estende aos campos de recorrência -------------------------

create or replace function public.fn_horario_imutavel_apos_uso()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  if (new.hora is distinct from old.hora
      or new.qtd_dose is distinct from old.qtd_dose
      or new.recorrencia_tipo is distinct from old.recorrencia_tipo
      or new.dias_semana is distinct from old.dias_semana
      or new.intervalo_dias is distinct from old.intervalo_dias
      or new.data_referencia is distinct from old.data_referencia)
     and exists (select 1 from public.administracoes a
                  where a.horario_id = old.id) then
    raise exception
      'Horário com administrações registradas tem hora/dose/recorrência imutáveis (DEC-026/055): desative e cadastre a nova versão';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_horario_imutavel_apos_uso on public.horarios;
create trigger trg_horario_imutavel_apos_uso
  before update of hora, qtd_dose, recorrencia_tipo, dias_semana, intervalo_dias, data_referencia
  on public.horarios
  for each row execute function public.fn_horario_imutavel_apos_uso();

-- 4) RPCs: recorrência opcional (aditivo, com default) -----------------------
--
-- BUG-010: mesmo sendo aditivo, ainda troca a assinatura (parâmetros novos) —
-- drop explícito da versão antiga é obrigatório.

drop function if exists public.criar_horario(uuid, time without time zone, numeric);
drop function if exists public.atualizar_horario(uuid, time without time zone, numeric);

create or replace function public.criar_horario(
  p_medicamento_id uuid,
  p_hora time without time zone,
  p_qtd_dose numeric,
  p_recorrencia_tipo text default 'diario',
  p_dias_semana int[] default null,
  p_intervalo_dias int default null,
  p_data_referencia date default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
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

  if p_recorrencia_tipo not in ('diario', 'dias_semana', 'intervalo') then
    return jsonb_build_object('ok', false, 'erro', 'recorrencia_tipo_invalida');
  end if;
  if p_recorrencia_tipo = 'dias_semana' then
    if p_intervalo_dias is not null or p_data_referencia is not null then
      return jsonb_build_object('ok', false, 'erro', 'recorrencia_campos_incoerentes');
    end if;
    if p_dias_semana is null or cardinality(p_dias_semana) = 0 then
      return jsonb_build_object('ok', false, 'erro', 'dias_semana_obrigatorio');
    end if;
    if exists (select 1 from unnest(p_dias_semana) v where v < 1 or v > 7) then
      return jsonb_build_object('ok', false, 'erro', 'dias_semana_invalido');
    end if;
    if cardinality(p_dias_semana) <> cardinality(array(select distinct unnest(p_dias_semana))) then
      return jsonb_build_object('ok', false, 'erro', 'dias_semana_repetido');
    end if;
  elsif p_recorrencia_tipo = 'intervalo' then
    if p_dias_semana is not null then
      return jsonb_build_object('ok', false, 'erro', 'recorrencia_campos_incoerentes');
    end if;
    if p_intervalo_dias is null or p_intervalo_dias <= 1 then
      return jsonb_build_object('ok', false, 'erro', 'intervalo_dias_invalido');
    end if;
    if p_data_referencia is null then
      return jsonb_build_object('ok', false, 'erro', 'data_referencia_obrigatoria');
    end if;
  else
    if p_dias_semana is not null or p_intervalo_dias is not null or p_data_referencia is not null then
      return jsonb_build_object('ok', false, 'erro', 'recorrencia_campos_incoerentes');
    end if;
  end if;

  begin
    insert into public.horarios
      (medicamento_id, hora, qtd_dose, recorrencia_tipo, dias_semana, intervalo_dias, data_referencia)
    values
      (p_medicamento_id, p_hora, p_qtd_dose, p_recorrencia_tipo, p_dias_semana, p_intervalo_dias, p_data_referencia)
    returning id into v_id;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'erro', 'horario_duplicado');
  end;

  return jsonb_build_object('ok', true, 'horario',
    jsonb_build_object('id', v_id, 'hora', p_hora, 'qtd_dose', p_qtd_dose));
end;
$function$;

create or replace function public.atualizar_horario(
  p_horario_id uuid,
  p_hora time without time zone,
  p_qtd_dose numeric,
  p_recorrencia_tipo text default 'diario',
  p_dias_semana int[] default null,
  p_intervalo_dias int default null,
  p_data_referencia date default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
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

  if p_recorrencia_tipo not in ('diario', 'dias_semana', 'intervalo') then
    return jsonb_build_object('ok', false, 'erro', 'recorrencia_tipo_invalida');
  end if;
  if p_recorrencia_tipo = 'dias_semana' then
    if p_intervalo_dias is not null or p_data_referencia is not null then
      return jsonb_build_object('ok', false, 'erro', 'recorrencia_campos_incoerentes');
    end if;
    if p_dias_semana is null or cardinality(p_dias_semana) = 0 then
      return jsonb_build_object('ok', false, 'erro', 'dias_semana_obrigatorio');
    end if;
    if exists (select 1 from unnest(p_dias_semana) v where v < 1 or v > 7) then
      return jsonb_build_object('ok', false, 'erro', 'dias_semana_invalido');
    end if;
    if cardinality(p_dias_semana) <> cardinality(array(select distinct unnest(p_dias_semana))) then
      return jsonb_build_object('ok', false, 'erro', 'dias_semana_repetido');
    end if;
  elsif p_recorrencia_tipo = 'intervalo' then
    if p_dias_semana is not null then
      return jsonb_build_object('ok', false, 'erro', 'recorrencia_campos_incoerentes');
    end if;
    if p_intervalo_dias is null or p_intervalo_dias <= 1 then
      return jsonb_build_object('ok', false, 'erro', 'intervalo_dias_invalido');
    end if;
    if p_data_referencia is null then
      return jsonb_build_object('ok', false, 'erro', 'data_referencia_obrigatoria');
    end if;
  else
    if p_dias_semana is not null or p_intervalo_dias is not null or p_data_referencia is not null then
      return jsonb_build_object('ok', false, 'erro', 'recorrencia_campos_incoerentes');
    end if;
  end if;

  if p_hora = v_atual.hora and p_qtd_dose = v_atual.qtd_dose
     and p_recorrencia_tipo = v_atual.recorrencia_tipo
     and p_dias_semana is not distinct from v_atual.dias_semana
     and p_intervalo_dias is not distinct from v_atual.intervalo_dias
     and p_data_referencia is not distinct from v_atual.data_referencia then
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
    insert into public.horarios
      (medicamento_id, hora, qtd_dose, recorrencia_tipo, dias_semana, intervalo_dias, data_referencia)
    values
      (v_atual.medicamento_id, p_hora, p_qtd_dose, p_recorrencia_tipo, p_dias_semana, p_intervalo_dias, p_data_referencia)
    returning id into v_novo;
    return jsonb_build_object('ok', true, 'horario_id', v_novo,
                              'versionado', true);
  end if;

  update public.horarios
     set hora = p_hora,
         qtd_dose = p_qtd_dose,
         recorrencia_tipo = p_recorrencia_tipo,
         dias_semana = p_dias_semana,
         intervalo_dias = p_intervalo_dias,
         data_referencia = p_data_referencia
   where id = p_horario_id;
  return jsonb_build_object('ok', true, 'horario_id', p_horario_id,
                            'versionado', false);
end;
$function$;

commit;
