-- SESSÃO 16 — Parte 5 (DEC-057): posologia estruturada, critério de uso e
-- observações.
--
-- Problema: medicamentos.posologia é texto livre guardando DUAS coisas,
-- nenhuma delas posologia de fato:
--   - tipo continuo: narração redundante do horário estruturado ("1
--     comprimido pela manhã") — dupla fonte do mesmo fato.
--   - tipo sos: o critério clínico de administração ("Se dor ou febre") — a
--     informação mais importante da tela no momento da dose SOS.
--
-- Auditoria desta sessão (RELATORIO_SESSAO_16.md) conferiu TODOS os 8
-- registros de posologia continuo contra horarios+forma: são integralmente
-- redundantes (inclusive o Prolopa, "4 comprimidos ao dia (jejum, manhã,
-- tarde e noite)" ↔ 4 horários ativos de 1 comprimido, 06h/11h/18h/22h). Não
-- há nenhum caso de informação ausente do dado estruturado — nenhum motivo
-- para abortar.
--
-- Migration NÃO é aditiva (troca p_posologia por p_criterio_uso/p_observacoes
-- nas RPCs) — frontend (FormMedicamento.jsx e os três call sites) muda no
-- mesmo commit, regra permanente da Parte 0.

begin;

alter table public.medicamentos
  add column criterio_uso text,
  add column observacoes text;

-- Migração dos 5 SOS reais: texto preservado integralmente em criterio_uso.
update public.medicamentos
set criterio_uso = posologia
where tipo = 'sos' and posologia is not null;

-- 3 itens de teste SOS inativos (Sessão #15/#16) sem posologia: placeholder
-- só para satisfazer o NOT NULL condicional abaixo sem afrouxar a regra para
-- dado real — já estão com ativo=false.
update public.medicamentos
set criterio_uso = 'Item de teste — sem critério real definido.'
where tipo = 'sos' and criterio_uso is null;

-- continuo: posologia descartada (auditada acima, redundante em todos os
-- casos) — não copiada para lugar nenhum.

alter table public.medicamentos
  add constraint medicamentos_criterio_uso_check
    check (
      (tipo = 'sos' and criterio_uso is not null and length(trim(criterio_uso)) > 0)
      or (tipo = 'continuo' and criterio_uso is null)
    );

alter table public.medicamentos drop column posologia;

-- RPCs: p_criterio_uso + p_observacoes substituem p_posologia -------------
--
-- BUG-010: já é a segunda troca de assinatura destas duas RPCs nesta sessão
-- (a primeira foi a Parte 2, forma_id) — drop explícito de novo, contra a
-- assinatura ATUAL (pós-Parte-2), não a original da Sessão #15.

drop function if exists public.criar_medicamento(uuid, uuid, text, text, text, uuid, text, text, numeric, numeric, numeric);
drop function if exists public.atualizar_medicamento(uuid, uuid, text, text, text, uuid, text, text, numeric, numeric, numeric);

create or replace function public.criar_medicamento(
  p_idoso_id uuid,
  p_catalogo_id uuid,
  p_nome text,
  p_dosagem text,
  p_forma_farmaceutica text,
  p_forma_id uuid,
  p_criterio_uso text,
  p_observacoes text,
  p_tipo text,
  p_estoque_minimo numeric default null,
  p_gotas_por_ml numeric default null,
  p_volume_frasco_ml numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_cat          public.catalogo_medicamentos;
  v_forma        public.formas_farmaceuticas;
  v_catalogo_id  uuid;
  v_nome         text;
  v_dosagem      text;
  v_forma_txt    text;
  v_unidade      text;
  v_criterio_uso text;
  v_observacoes  text;
  v_id           uuid;
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

  v_observacoes := nullif(trim(coalesce(p_observacoes, '')), '');
  if p_tipo = 'sos' then
    v_criterio_uso := nullif(trim(coalesce(p_criterio_uso, '')), '');
    if v_criterio_uso is null then
      return jsonb_build_object('ok', false, 'erro', 'criterio_uso_obrigatorio');
    end if;
  else
    v_criterio_uso := null;
  end if;

  if p_catalogo_id is not null then
    select * into v_cat from public.catalogo_medicamentos where id = p_catalogo_id;
    if not found then
      return jsonb_build_object('ok', false, 'erro', 'catalogo_nao_encontrado');
    end if;
    v_catalogo_id := v_cat.id;
    v_nome    := v_cat.nome;
    v_dosagem := v_cat.dosagem;
    v_forma_txt := v_cat.forma_farmaceutica;
  else
    v_nome := trim(coalesce(p_nome, ''));
    if v_nome = '' then
      return jsonb_build_object('ok', false, 'erro', 'nome_obrigatorio');
    end if;
    v_dosagem := nullif(trim(coalesce(p_dosagem, '')), '');

    if p_forma_id is not null then
      select * into v_forma from public.formas_farmaceuticas where id = p_forma_id and ativo;
      if not found then
        return jsonb_build_object('ok', false, 'erro', 'forma_nao_encontrada');
      end if;
      v_forma_txt := v_forma.nome;
      v_unidade   := v_forma.unidade_dose;
    else
      v_forma_txt := nullif(trim(coalesce(p_forma_farmaceutica, '')), '');
      v_unidade   := 'unidade';
    end if;

    if v_unidade = 'gota' and (p_gotas_por_ml is null or p_gotas_por_ml <= 0) then
      return jsonb_build_object('ok', false, 'erro', 'gotas_por_ml_obrigatorio');
    end if;
    if v_unidade in ('gota', 'ml') and (p_volume_frasco_ml is null or p_volume_frasco_ml <= 0) then
      return jsonb_build_object('ok', false, 'erro', 'volume_frasco_obrigatorio');
    end if;

    insert into public.catalogo_medicamentos
      (nome, dosagem, forma_id, forma_farmaceutica, unidade_dose, gotas_por_ml, volume_frasco_ml)
    values
      (v_nome, v_dosagem, p_forma_id, v_forma_txt, v_unidade,
       case when v_unidade = 'gota' then p_gotas_por_ml else null end,
       case when v_unidade in ('gota', 'ml') then p_volume_frasco_ml else null end)
    returning id into v_catalogo_id;
  end if;

  if exists (select 1 from public.medicamentos
              where idoso_id = p_idoso_id and ativo and catalogo_id = v_catalogo_id) then
    return jsonb_build_object('ok', false, 'erro', 'medicamento_duplicado');
  end if;

  insert into public.medicamentos
    (idoso_id, catalogo_id, nome, dosagem, forma_farmaceutica, criterio_uso, observacoes, tipo, estoque_minimo)
  values
    (p_idoso_id, v_catalogo_id, v_nome, v_dosagem, v_forma_txt, v_criterio_uso, v_observacoes, p_tipo, p_estoque_minimo)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'medicamento',
    jsonb_build_object('id', v_id, 'nome', v_nome, 'tipo', p_tipo,
                       'catalogo_id', v_catalogo_id));
end;
$function$;

create or replace function public.atualizar_medicamento(
  p_medicamento_id uuid,
  p_catalogo_id uuid,
  p_nome text,
  p_dosagem text,
  p_forma_farmaceutica text,
  p_forma_id uuid,
  p_criterio_uso text,
  p_observacoes text,
  p_tipo text,
  p_estoque_minimo numeric default null,
  p_gotas_por_ml numeric default null,
  p_volume_frasco_ml numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_atual        public.medicamentos;
  v_cat          public.catalogo_medicamentos;
  v_forma        public.formas_farmaceuticas;
  v_catalogo_id  uuid;
  v_nome         text;
  v_dosagem      text;
  v_forma_txt    text;
  v_unidade      text;
  v_criterio_uso text;
  v_observacoes  text;
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

  v_observacoes := nullif(trim(coalesce(p_observacoes, '')), '');
  if p_tipo = 'sos' then
    v_criterio_uso := nullif(trim(coalesce(p_criterio_uso, '')), '');
    if v_criterio_uso is null then
      return jsonb_build_object('ok', false, 'erro', 'criterio_uso_obrigatorio');
    end if;
  else
    v_criterio_uso := null;
  end if;

  if p_catalogo_id is not null then
    select * into v_cat from public.catalogo_medicamentos where id = p_catalogo_id;
    if not found then
      return jsonb_build_object('ok', false, 'erro', 'catalogo_nao_encontrado');
    end if;
    v_catalogo_id := v_cat.id;
    v_nome    := v_cat.nome;
    v_dosagem := v_cat.dosagem;
    v_forma_txt := v_cat.forma_farmaceutica;
  else
    v_nome := trim(coalesce(p_nome, ''));
    if v_nome = '' then
      return jsonb_build_object('ok', false, 'erro', 'nome_obrigatorio');
    end if;
    v_dosagem := nullif(trim(coalesce(p_dosagem, '')), '');

    if p_forma_id is not null then
      select * into v_forma from public.formas_farmaceuticas where id = p_forma_id and ativo;
      if not found then
        return jsonb_build_object('ok', false, 'erro', 'forma_nao_encontrada');
      end if;
      v_forma_txt := v_forma.nome;
      v_unidade   := v_forma.unidade_dose;
    else
      v_forma_txt := nullif(trim(coalesce(p_forma_farmaceutica, '')), '');
      v_unidade   := 'unidade';
    end if;

    if v_unidade = 'gota' and (p_gotas_por_ml is null or p_gotas_por_ml <= 0) then
      return jsonb_build_object('ok', false, 'erro', 'gotas_por_ml_obrigatorio');
    end if;
    if v_unidade in ('gota', 'ml') and (p_volume_frasco_ml is null or p_volume_frasco_ml <= 0) then
      return jsonb_build_object('ok', false, 'erro', 'volume_frasco_obrigatorio');
    end if;

    insert into public.catalogo_medicamentos
      (nome, dosagem, forma_id, forma_farmaceutica, unidade_dose, gotas_por_ml, volume_frasco_ml)
    values
      (v_nome, v_dosagem, p_forma_id, v_forma_txt, v_unidade,
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
         forma_farmaceutica = v_forma_txt,
         criterio_uso       = v_criterio_uso,
         observacoes        = v_observacoes,
         tipo               = p_tipo,
         estoque_minimo     = p_estoque_minimo
   where id = p_medicamento_id;

  return jsonb_build_object('ok', true);
end;
$function$;

commit;
