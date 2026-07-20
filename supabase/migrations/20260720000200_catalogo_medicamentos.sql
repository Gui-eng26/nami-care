-- =============================================================================
-- Migration: catálogo de medicamentos da casa (Sessão #6 — DEC-035)
--
-- Problema: medicamentos.idoso_id é obrigatório — cada residente tem o próprio
-- registro, mesmo quando o remédio físico é o mesmo de outro residente (ex.:
-- dois tomando Losartana 50 mg). Não há elo entre os registros. Para agrupar
-- "mesmo remédio, N residentes" na tela nova SEM comparar texto (frágil:
-- divergência de digitação = falso negativo; normalização = risco de falso
-- positivo), cria-se uma entidade da CASA: catalogo_medicamentos.
--
-- O estoque em si continua SEMPRE separado por residente (saldo, ledger) — custo
-- e consumo são individuais. O catálogo só dá o elo de identidade do remédio.
--
-- Construção orgânica (DEC-035): o primeiro cadastro de um remédio cria o item
-- do catálogo; cadastros seguintes reaproveitam por SELEÇÃO HUMANA (busca por
-- nome), nunca por comparação de string. Sem fonte externa (bulário/CMED).
--
-- 1) Tabela catalogo_medicamentos (sem idoso_id — é da casa).
-- 2) medicamentos.catalogo_id (FK, NOT NULL ao final). medicamentos mantém a
--    cópia de nome/dosagem/forma: o histórico (administracoes) as lê por join e
--    a imutabilidade clínica (DEC-026) depende dessa cópia estável.
-- 3) Backfill: um item de catálogo por combinação exata (nome, dosagem, forma)
--    hoje presente — seguro porque só há dado de seed até aqui (dados reais
--    entram na Sessão #7, já com o catálogo pronto).
-- 4) Imutabilidade clínica (DEC-026) estendida: catalogo_id também fica imutável
--    após a primeira administração — trocar o item mudaria nome/dosagem/forma de
--    quem tem histórico, reescrevendo a leitura do passado.
-- 5) criar_medicamento / atualizar_medicamento passam a operar pelo catálogo:
--    ou selecionam um item existente (herança de nome/dosagem/forma), ou criam
--    um item novo junto com o medicamento (atômico). Nome/dosagem/forma deixam
--    de ser texto livre editável na tela do residente.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- catalogo_medicamentos — item de medicamento da CASA (DEC-035).
-- Sem restrição de unicidade: o reaproveitamento é por seleção humana na busca,
-- não por comparação de texto no banco (uma quase-duplicata criada por engano é
-- escolha humana, não erro de integridade — e travar por texto seria a própria
-- normalização que a DEC-035 descarta).
-- -----------------------------------------------------------------------------
create table public.catalogo_medicamentos (
  id                  uuid primary key default gen_random_uuid(),
  nome                text not null,
  dosagem             text,
  forma_farmaceutica  text,
  criado_em           timestamptz not null default now()
);

create index catalogo_medicamentos_nome_idx on public.catalogo_medicamentos (nome);

alter table public.catalogo_medicamentos enable row level security;

-- Busca no catálogo é leitura direta do cliente (seleção humana, DEC-035).
-- Escrita só via RPC SECURITY DEFINER (criar/atualizar medicamento). anon sem
-- acesso (nenhuma política). Mesmo padrão de medicamentos pós-Sessão #3.
create policy catalogo_select_autenticado on public.catalogo_medicamentos
  for select to authenticated using (true);

revoke insert, update, delete on public.catalogo_medicamentos from anon, authenticated;

-- -----------------------------------------------------------------------------
-- medicamentos.catalogo_id + backfill do seed.
-- -----------------------------------------------------------------------------
alter table public.medicamentos
  add column catalogo_id uuid references public.catalogo_medicamentos (id);

with combos as (
  select distinct nome, dosagem, forma_farmaceutica
  from public.medicamentos
),
novos as (
  insert into public.catalogo_medicamentos (nome, dosagem, forma_farmaceutica)
  select nome, dosagem, forma_farmaceutica from combos
  returning id, nome, dosagem, forma_farmaceutica
)
update public.medicamentos m
   set catalogo_id = n.id
  from novos n
 where m.nome               is not distinct from n.nome
   and m.dosagem            is not distinct from n.dosagem
   and m.forma_farmaceutica is not distinct from n.forma_farmaceutica;

alter table public.medicamentos alter column catalogo_id set not null;
create index medicamentos_catalogo_id_idx on public.medicamentos (catalogo_id);

-- -----------------------------------------------------------------------------
-- Imutabilidade clínica após uso (DEC-026) estendida ao catalogo_id (DEC-035).
-- -----------------------------------------------------------------------------
create or replace function public.fn_medicamento_imutavel_apos_uso()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if (new.nome is distinct from old.nome
      or new.dosagem is distinct from old.dosagem
      or new.forma_farmaceutica is distinct from old.forma_farmaceutica
      or new.catalogo_id is distinct from old.catalogo_id)
     and exists (select 1 from public.administracoes a
                  where a.medicamento_id = old.id) then
    raise exception
      'Medicamento com administrações registradas tem nome/dosagem/forma/catálogo imutáveis (DEC-026/035): desative e cadastre a nova versão';
  end if;
  return new;
end;
$$;

drop trigger trg_medicamento_imutavel_apos_uso on public.medicamentos;
create trigger trg_medicamento_imutavel_apos_uso
  before update of nome, dosagem, forma_farmaceutica, catalogo_id on public.medicamentos
  for each row execute function public.fn_medicamento_imutavel_apos_uso();

-- -----------------------------------------------------------------------------
-- criar_medicamento (DEC-035): dois caminhos, sempre por catálogo.
--   p_catalogo_id não nulo  → seleciona item existente; nome/dosagem/forma vêm
--                             do catálogo (p_nome/p_dosagem/p_forma ignorados).
--   p_catalogo_id nulo      → cria item novo do catálogo COM p_nome/p_dosagem/
--                             p_forma e o medicamento na MESMA transação.
-- Assinatura muda (ganha p_catalogo_id) → drop + recreate.
-- -----------------------------------------------------------------------------
drop function public.criar_medicamento(uuid, text, uuid, text, text, text, text, text, numeric);

create or replace function public.criar_medicamento(
  p_admin_id           uuid,
  p_admin_pin          text,
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
  v_auth       jsonb;
  v_cat        public.catalogo_medicamentos;
  v_catalogo_id uuid;
  v_nome       text;
  v_dosagem    text;
  v_forma      text;
  v_id         uuid;
begin
  v_auth := public.fn_autorizar_admin(p_admin_id, p_admin_pin);
  if not (v_auth ->> 'ok')::boolean then
    return v_auth;
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
    -- Caminho 1: item existente do catálogo.
    select * into v_cat from public.catalogo_medicamentos where id = p_catalogo_id;
    if not found then
      return jsonb_build_object('ok', false, 'erro', 'catalogo_nao_encontrado');
    end if;
    v_catalogo_id := v_cat.id;
    v_nome    := v_cat.nome;
    v_dosagem := v_cat.dosagem;
    v_forma   := v_cat.forma_farmaceutica;
  else
    -- Caminho 2: cria item novo do catálogo + medicamento juntos.
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

  -- Duplicata é por item de catálogo (mesmo remédio para o mesmo residente),
  -- nunca por texto. Item novo do catálogo nunca colide.
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
  public.criar_medicamento(uuid, text, uuid, uuid, text, text, text, text, text, numeric)
  from public, anon;

-- -----------------------------------------------------------------------------
-- atualizar_medicamento (DEC-035): nome/dosagem/forma NÃO mudam por texto livre
-- na tela do residente — pertencem ao catálogo (que pode ter outros residentes
-- vinculados). Trocar o remédio = trocar o item do catálogo (selecionar outro
-- existente ou criar um novo), com a mesma guarda de histórico da DEC-026.
-- posologia/tipo/estoque_minimo continuam por residente e sempre editáveis.
--   p_catalogo_id não nulo → vincula a esse item existente.
--   p_catalogo_id nulo + p_nome → cria item novo do catálogo e vincula.
-- Assinatura muda → drop + recreate.
-- -----------------------------------------------------------------------------
drop function public.atualizar_medicamento(uuid, text, uuid, text, text, text, text, text, numeric);

create or replace function public.atualizar_medicamento(
  p_admin_id           uuid,
  p_admin_pin          text,
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
  v_auth        jsonb;
  v_atual       public.medicamentos;
  v_cat         public.catalogo_medicamentos;
  v_catalogo_id uuid;
  v_nome        text;
  v_dosagem     text;
  v_forma       text;
begin
  v_auth := public.fn_autorizar_admin(p_admin_id, p_admin_pin);
  if not (v_auth ->> 'ok')::boolean then
    return v_auth;
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

  -- Resolve o item de catálogo alvo (existente ou novo).
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

  -- Trocar o item do catálogo em medicamento COM histórico reescreveria a
  -- leitura clínica do passado (DEC-026): bloqueia (o trigger também barra).
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

  -- Duplicata por item de catálogo entre os medicamentos ativos do residente.
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
  public.atualizar_medicamento(uuid, text, uuid, uuid, text, text, text, text, text, numeric)
  from public, anon;
