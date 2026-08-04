-- HOTFIX (BUG-009): DEC-051 tornou catalogo_medicamentos.unidade_dose NOT NULL, mas
-- criar_medicamento/atualizar_medicamento inseriam item novo de catálogo sem
-- esse campo — quebrava todo cadastro de medicamento novo desde a migration
-- de hoje. Nasce 'unidade' (mesmo bucket seguro de "Outra"); a UI de lista
-- fechada da Parte 4 passa a enviar a unidade certa.

create or replace function public.criar_medicamento(p_idoso_id uuid, p_catalogo_id uuid, p_nome text, p_dosagem text, p_forma_farmaceutica text, p_posologia text, p_tipo text, p_estoque_minimo numeric DEFAULT NULL::numeric)
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
    insert into public.catalogo_medicamentos (nome, dosagem, forma_farmaceutica, unidade_dose)
    values (v_nome, v_dosagem, v_forma, 'unidade')
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

create or replace function public.atualizar_medicamento(p_medicamento_id uuid, p_catalogo_id uuid, p_nome text, p_dosagem text, p_forma_farmaceutica text, p_posologia text, p_tipo text, p_estoque_minimo numeric DEFAULT NULL::numeric)
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
    insert into public.catalogo_medicamentos (nome, dosagem, forma_farmaceutica, unidade_dose)
    values (v_nome, v_dosagem, v_forma, 'unidade')
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
