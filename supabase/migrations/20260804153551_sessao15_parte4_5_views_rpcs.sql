-- Sessão #15, Partes 4-5: views expõem unidade_dose/gotas_por_ml/volume_frasco_ml
-- do catálogo (e o fator congelado no lote); RPCs de cadastro e compra passam
-- a aceitar a unidade explícita vinda da lista fechada da UI.

create or replace view public.saldo_estoque as
 SELECT m.id AS medicamento_id, m.idoso_id, m.nome, m.dosagem, m.forma_farmaceutica, m.tipo, m.ativo,
    COALESCE(sum(l.saldo_atual), 0::numeric) AS saldo,
    c.unidade_dose,
    c.gotas_por_ml AS catalogo_gotas_por_ml,
    c.volume_frasco_ml
   FROM medicamentos m
     LEFT JOIN lotes_estoque l ON l.medicamento_id = m.id
     LEFT JOIN catalogo_medicamentos c ON c.id = m.catalogo_id
  GROUP BY m.id, c.unidade_dose, c.gotas_por_ml, c.volume_frasco_ml;

create or replace view public.cobertura_estoque as
 WITH doses_dia AS (
         SELECT h.medicamento_id, sum(h.qtd_dose) AS doses_por_dia
           FROM horarios h WHERE h.ativo GROUP BY h.medicamento_id
        )
 SELECT s.medicamento_id, s.idoso_id, i.nome AS nome_idoso, i.ativo AS idoso_ativo, s.nome, s.dosagem,
    s.forma_farmaceutica, s.tipo, s.ativo, s.saldo, m.estoque_minimo, d.doses_por_dia,
        CASE WHEN s.tipo = 'continuo'::text AND d.doses_por_dia > 0::numeric THEN round(s.saldo / d.doses_por_dia, 1) ELSE NULL::numeric END AS cobertura_dias,
        CASE WHEN NOT (s.ativo AND i.ativo) THEN false
             WHEN s.tipo = 'continuo'::text THEN COALESCE(d.doses_por_dia > 0::numeric AND (s.saldo / d.doses_por_dia) < 5::numeric, false)
             ELSE COALESCE(s.saldo < m.estoque_minimo, false) END AS alerta_reposicao,
        CASE WHEN s.ativo AND i.ativo AND s.tipo = 'continuo'::text AND d.doses_por_dia > 0::numeric AND (s.saldo / d.doses_por_dia) < 5::numeric THEN GREATEST(ceil(d.doses_por_dia * 30::numeric - s.saldo), 0::numeric) ELSE NULL::numeric END AS sugestao_compra,
    i.eh_sentinela AS idoso_da_casa,
    s.unidade_dose,
    s.catalogo_gotas_por_ml,
    s.volume_frasco_ml
   FROM saldo_estoque s
     JOIN medicamentos m ON m.id = s.medicamento_id
     JOIN idosos i ON i.id = s.idoso_id
     LEFT JOIN doses_dia d ON d.medicamento_id = s.medicamento_id;

create or replace view public.lotes_estoque_vivo as
 SELECT id, medicamento_id, lote, validade, saldo_atual, quantidade_inicial, data_entrada, origem, criado_em,
    gotas_por_ml
   FROM lotes_estoque l
  WHERE saldo_atual > 0::numeric;

create or replace function public.fn_registrar_lote_entrada(p_medicamento_id uuid, p_movimentacao_id uuid, p_lote text, p_validade date, p_quantidade numeric, p_data_entrada date, p_origem text, p_gotas_por_ml numeric default null)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lote_id uuid;
begin
  insert into public.lotes_estoque
    (medicamento_id, lote, validade, quantidade_inicial, saldo_atual,
     data_entrada, origem, gotas_por_ml)
  values
    (p_medicamento_id, nullif(trim(coalesce(p_lote, '')), ''), p_validade,
     p_quantidade, p_quantidade,
     coalesce(p_data_entrada, (now() at time zone public.fn_fuso_casa())::date),
     p_origem, p_gotas_por_ml)
  returning id into v_lote_id;

  insert into public.movimentacao_lote (movimentacao_id, lote_id, quantidade)
  values (p_movimentacao_id, v_lote_id, p_quantidade);

  return v_lote_id;
end;
$function$;

create or replace function public.registrar_entrada_estoque(p_medicamento_id uuid, p_quantidade numeric, p_validade date, p_lote text DEFAULT NULL::text, p_data date DEFAULT NULL::date, p_observacao text DEFAULT NULL::text, p_gotas_por_ml numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_cuidador  uuid;
  v_med       public.medicamentos;
  v_hoje      date := (now() at time zone public.fn_fuso_casa())::date;
  v_data      date := coalesce(p_data, (now() at time zone public.fn_fuso_casa())::date);
  v_criado_em timestamptz;
  v_id        uuid;
  v_lote_id   uuid;
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
  if p_validade is null then
    return jsonb_build_object('ok', false, 'erro', 'validade_obrigatoria');
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

  v_lote_id := public.fn_registrar_lote_entrada(
    p_medicamento_id, v_id, p_lote, p_validade, p_quantidade, v_data, 'compra', p_gotas_por_ml);

  select coalesce(sum(saldo_atual), 0) into v_saldo
    from public.lotes_estoque where medicamento_id = p_medicamento_id;

  return jsonb_build_object('ok', true, 'movimentacao_id', v_id,
                            'lote_id', v_lote_id, 'saldo', v_saldo);
end;
$function$;

drop function public.criar_medicamento(uuid, uuid, text, text, text, text, text, numeric);

create or replace function public.criar_medicamento(p_idoso_id uuid, p_catalogo_id uuid, p_nome text, p_dosagem text, p_forma_farmaceutica text, p_posologia text, p_tipo text, p_estoque_minimo numeric DEFAULT NULL::numeric, p_unidade_dose text DEFAULT NULL::text, p_gotas_por_ml numeric DEFAULT NULL::numeric, p_volume_frasco_ml numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_cat         public.catalogo_medicamentos;
  v_catalogo_id uuid;
  v_nome        text;
  v_dosagem     text;
  v_forma       text;
  v_unidade     text;
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

    v_unidade := coalesce(nullif(trim(coalesce(p_unidade_dose, '')), ''), 'unidade');
    if v_unidade not in ('comprimido','capsula','dragea','gota','ml','sache','supositorio','adesivo','unidade') then
      return jsonb_build_object('ok', false, 'erro', 'unidade_dose_invalida');
    end if;
    if v_unidade = 'gota' and (p_gotas_por_ml is null or p_gotas_por_ml <= 0) then
      return jsonb_build_object('ok', false, 'erro', 'gotas_por_ml_obrigatorio');
    end if;
    if v_unidade in ('gota', 'ml') and (p_volume_frasco_ml is null or p_volume_frasco_ml <= 0) then
      return jsonb_build_object('ok', false, 'erro', 'volume_frasco_obrigatorio');
    end if;

    insert into public.catalogo_medicamentos (nome, dosagem, forma_farmaceutica, unidade_dose, gotas_por_ml, volume_frasco_ml)
    values (v_nome, v_dosagem, v_forma, v_unidade,
            case when v_unidade = 'gota' then p_gotas_por_ml else null end,
            case when v_unidade in ('gota', 'ml') then p_volume_frasco_ml else null end)
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
$function$;

drop function public.atualizar_medicamento(uuid, uuid, text, text, text, text, text, numeric);

create or replace function public.atualizar_medicamento(p_medicamento_id uuid, p_catalogo_id uuid, p_nome text, p_dosagem text, p_forma_farmaceutica text, p_posologia text, p_tipo text, p_estoque_minimo numeric DEFAULT NULL::numeric, p_unidade_dose text DEFAULT NULL::text, p_gotas_por_ml numeric DEFAULT NULL::numeric, p_volume_frasco_ml numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_atual       public.medicamentos;
  v_cat         public.catalogo_medicamentos;
  v_catalogo_id uuid;
  v_nome        text;
  v_dosagem     text;
  v_forma       text;
  v_unidade     text;
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

    v_unidade := coalesce(nullif(trim(coalesce(p_unidade_dose, '')), ''), 'unidade');
    if v_unidade not in ('comprimido','capsula','dragea','gota','ml','sache','supositorio','adesivo','unidade') then
      return jsonb_build_object('ok', false, 'erro', 'unidade_dose_invalida');
    end if;
    if v_unidade = 'gota' and (p_gotas_por_ml is null or p_gotas_por_ml <= 0) then
      return jsonb_build_object('ok', false, 'erro', 'gotas_por_ml_obrigatorio');
    end if;
    if v_unidade in ('gota', 'ml') and (p_volume_frasco_ml is null or p_volume_frasco_ml <= 0) then
      return jsonb_build_object('ok', false, 'erro', 'volume_frasco_obrigatorio');
    end if;

    insert into public.catalogo_medicamentos (nome, dosagem, forma_farmaceutica, unidade_dose, gotas_por_ml, volume_frasco_ml)
    values (v_nome, v_dosagem, v_forma, v_unidade,
            case when v_unidade = 'gota' then p_gotas_por_ml else null end,
            case when v_unidade in ('gota', 'ml') then p_volume_frasco_ml else null end)
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
$function$;
