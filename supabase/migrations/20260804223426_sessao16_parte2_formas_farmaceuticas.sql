-- SESSÃO 16 — Parte 2 (DEC-054): catálogo por referência.
--
-- Problema: forma_farmaceutica (texto livre) e unidade_dose (coluna própria)
-- não têm nada no banco garantindo que concordem. A BUG-012 provou que isso
-- não é hipotético: o Prolopa nasceu com forma_farmaceutica='Comprimido' e
-- unidade_dose='unidade' numa janela de deploy. Esta migration troca a dupla
-- fonte por uma referência única: catalogo_medicamentos.forma_id aponta para
-- formas_farmaceuticas, que é quem sabe a unidade_dose de cada forma.
--
-- Sequência dentro desta transação: 1) tabela nova + seed; 2) colunas novas em
-- catalogo_medicamentos; 3) trigger que deriva forma_farmaceutica/unidade_dose
-- a partir de forma_id (e recusa divergência quando forma_id não muda);
-- 4) backfill; 5) RPCs criar_medicamento/atualizar_medicamento passam a
-- receber p_forma_id em vez de p_unidade_dose.
--
-- Migration e deploy são um eventos só (regra permanente da Sessão #16): o
-- frontend (FormMedicamento.jsx e call sites) muda no mesmo commit.

begin;

-- 1) Tabela de referência ---------------------------------------------------

create table public.formas_farmaceuticas (
  id           uuid primary key default gen_random_uuid(),
  nome         text not null unique,
  unidade_dose text not null check (unidade_dose in (
                 'comprimido','capsula','dragea','gota','ml','sache',
                 'supositorio','adesivo'
               )),
  plural       text not null,
  ordem        integer not null,
  ativo        boolean not null default true
);

comment on table public.formas_farmaceuticas is
  'Lista fechada de forma farmacêutica → unidade de dose (DEC-054, estende a DEC-051). '
  '"Outra" não entra aqui: catalogo_medicamentos.forma_id fica null e unidade_dose cai '
  'para ''unidade'' via trigger — mesmo comportamento de sempre para texto livre.';

insert into public.formas_farmaceuticas (nome, unidade_dose, plural, ordem) values
  ('Comprimido',                 'comprimido',  'comprimidos',  1),
  ('Comprimido revestido',       'comprimido',  'comprimidos',  2),
  ('Comprimido sublingual',      'comprimido',  'comprimidos',  3),
  ('Comprimido orodispersível',  'comprimido',  'comprimidos',  4),
  ('Comprimido mastigável',      'comprimido',  'comprimidos',  5),
  ('Cápsula',                    'capsula',     'cápsulas',     6),
  ('Drágea',                     'dragea',      'drágeas',      7),
  ('Solução oral em gotas',      'gota',        'gotas',        8),
  ('Xarope',                     'ml',          'ml',           9),
  ('Solução oral',               'ml',          'ml',          10),
  ('Suspensão oral',             'ml',          'ml',          11),
  ('Sachê / pó',                 'sache',       'sachês',      12),
  ('Supositório',                'supositorio', 'supositórios',13),
  ('Adesivo transdérmico',       'adesivo',     'adesivos',    14);

-- 2) Colunas novas em catalogo_medicamentos ---------------------------------

alter table public.catalogo_medicamentos
  add column forma_id uuid references public.formas_farmaceuticas(id),
  add column ativo boolean not null default true;

comment on column public.catalogo_medicamentos.forma_id is
  'Referência à forma farmacêutica (DEC-054). Null = "Outra" (texto livre em '
  'forma_farmaceutica, unidade_dose forçada para ''unidade'' pela trigger '
  'fn_catalogo_derivar_forma).';

-- 3) Derivação e recusa de incoerência --------------------------------------

create or replace function public.fn_catalogo_derivar_forma()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare
  v_forma public.formas_farmaceuticas;
begin
  if new.forma_id is null then
    new.unidade_dose := 'unidade';
    return new;
  end if;

  select * into v_forma from public.formas_farmaceuticas where id = new.forma_id;
  if not found then
    raise exception 'forma_id % não existe em formas_farmaceuticas', new.forma_id;
  end if;

  -- forma_id não mudou (ou é update de outra coisa): forma_farmaceutica e
  -- unidade_dose não podem divergir dela — recusa em vez de corrigir
  -- silenciosamente, para não mascarar uma tentativa de gravar incoerência
  -- (era assim que o Prolopa acontecia).
  if tg_op = 'UPDATE' and new.forma_id is not distinct from old.forma_id then
    if new.forma_farmaceutica is distinct from v_forma.nome
       or new.unidade_dose is distinct from v_forma.unidade_dose then
      raise exception
        'forma_farmaceutica/unidade_dose são derivados de forma_id (DEC-054): não podem divergir do item selecionado em formas_farmaceuticas';
    end if;
  else
    -- Inserção, ou forma_id mudando: a cópia denormalizada acompanha.
    new.forma_farmaceutica := v_forma.nome;
    new.unidade_dose := v_forma.unidade_dose;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_catalogo_derivar_forma on public.catalogo_medicamentos;
create trigger trg_catalogo_derivar_forma
  before insert or update of forma_id, forma_farmaceutica, unidade_dose
  on public.catalogo_medicamentos
  for each row execute function public.fn_catalogo_derivar_forma();

-- A trigger de imutabilidade (DEC-026/051, fn_catalogo_unidade_dose_imutavel)
-- já roda DEPOIS desta (ordem alfabética: "derivar" < "unidade_dose_imutavel")
-- e continua correta sem alteração: ela compara o unidade_dose já derivado
-- contra o antigo, então qualquer troca de forma_id que mude o unidade_dose
-- efetivo de um catálogo em uso continua bloqueada — é exatamente essa trava
-- que precisa ser suspensa a seguir, só para a correção pontual do Prolopa.

-- 4) Backfill ----------------------------------------------------------------

create extension if not exists unaccent with schema extensions;

do $$
begin
  -- Item de teste abandonado (Sessão #15, 0 uso real): forma_farmaceutica bate
  -- com "Solução oral em gotas", mas o registro não tem gotas_por_ml nem
  -- volume_frasco_ml — os checks de coerência de líquido rejeitariam o
  -- backfill automático. Vai para ativo=false a seguir; fica sem forma_id de
  -- propósito, não é esquecimento.
  if exists (
    select 1 from public.catalogo_medicamentos
    where nome not ilike 'TESTE%'
      and forma_id is null
      and not exists (
        select 1 from public.formas_farmaceuticas f
        where lower(extensions.unaccent(trim(f.nome)))
            = lower(extensions.unaccent(trim(catalogo_medicamentos.forma_farmaceutica)))
      )
  ) then
    raise exception 'Backfill DEC-054: há forma_farmaceutica sem correspondente em formas_farmaceuticas — abortando para conferência manual.';
  end if;

  -- Prolopa (BUG-012) já tem administrações reais: mudar seu unidade_dose de
  -- 'unidade' para 'comprimido' é uma CORREÇÃO de dado ruim, não uma edição
  -- normal — por isso, e só para este backfill, a trava de imutabilidade é
  -- suspensa.
  alter table public.catalogo_medicamentos disable trigger trg_catalogo_unidade_dose_imutavel;

  update public.catalogo_medicamentos c
  set forma_id = f.id
  from public.formas_farmaceuticas f
  where c.forma_id is null
    and c.id <> '7517c46a-d16b-4c03-a379-f541710146a5' -- TESTE abandonado, ver acima
    and lower(extensions.unaccent(trim(f.nome))) = lower(extensions.unaccent(trim(c.forma_farmaceutica)));

  alter table public.catalogo_medicamentos enable trigger trg_catalogo_unidade_dose_imutavel;

  -- Itens de teste da própria sessão (não excluir — soft delete, DEC-006).
  update public.catalogo_medicamentos
  set ativo = false
  where nome ilike 'TESTE%';
end $$;

-- 5) RPCs: p_forma_id substitui p_unidade_dose ------------------------------
--
-- BUG-010: assinatura muda (parâmetro trocado) — drop explícito da versão
-- antiga é obrigatório, ou o PostgREST fica com duas sobrecargas e todo
-- cadastro de medicamento passa a devolver "Falha de conexão".
-- Frontend (FormMedicamento.jsx e os dois call sites) muda no mesmo commit.

drop function if exists public.criar_medicamento(uuid, uuid, text, text, text, text, text, numeric, text, numeric, numeric);
drop function if exists public.atualizar_medicamento(uuid, uuid, text, text, text, text, text, numeric, text, numeric, numeric);

create or replace function public.criar_medicamento(
  p_idoso_id uuid,
  p_catalogo_id uuid,
  p_nome text,
  p_dosagem text,
  p_forma_farmaceutica text,
  p_forma_id uuid,
  p_posologia text,
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
  v_cat         public.catalogo_medicamentos;
  v_forma       public.formas_farmaceuticas;
  v_catalogo_id uuid;
  v_nome        text;
  v_dosagem     text;
  v_forma_txt   text;
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
    (idoso_id, catalogo_id, nome, dosagem, forma_farmaceutica, posologia, tipo, estoque_minimo)
  values
    (p_idoso_id, v_catalogo_id, v_nome, v_dosagem, v_forma_txt,
     nullif(trim(coalesce(p_posologia, '')), ''), p_tipo, p_estoque_minimo)
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
  p_posologia text,
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
  v_atual       public.medicamentos;
  v_cat         public.catalogo_medicamentos;
  v_forma       public.formas_farmaceuticas;
  v_catalogo_id uuid;
  v_nome        text;
  v_dosagem     text;
  v_forma_txt   text;
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
         posologia          = nullif(trim(coalesce(p_posologia, '')), ''),
         tipo               = p_tipo,
         estoque_minimo     = p_estoque_minimo
   where id = p_medicamento_id;

  return jsonb_build_object('ok', true);
end;
$function$;

commit;
