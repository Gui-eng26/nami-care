-- =============================================================================
-- Migration: rastreamento de estoque por lote e validade — modelo (DEC-040)
--
-- Até aqui o estoque era um saldo numérico por medicamento: movimentacoes_estoque
-- (ledger) somava entradas/saídas e a view saldo_estoque derivava um número. O
-- sistema sabia QUANTO tinha, não QUAIS unidades, de que lote, com que validade.
-- A Thais controla isso em Excel (data de entrada, lote, validade, quantidade) e
-- opera FEFO na bancada (sempre abre o lote de validade mais próxima). Esta
-- sessão faz o app refletir essa operação.
--
-- Duas verdades, sempre sincronizadas na MESMA transação (atomicidade é o
-- requisito nº 1 — se divergirem, o estoque mente):
--   lotes_estoque   = verdade do SALDO FÍSICO na prateleira, por validade.
--   movimentacoes_estoque (ledger) = verdade do HISTÓRICO e da cobertura
--     (extrato/adesão/alertas leem dele). Continua INTOCADO em forma: uma
--     movimentação por administração/entrada/ajuste/perda, com a UNIQUE em
--     administracao_id preservada (DEC-008).
--
-- Vínculo movimentação↔lote (DEC-040): uma SAÍDA pode varrer vários lotes (FEFO,
-- Parte 3), logo a relação é 1-para-N. Modelada como tabela de ligação
-- movimentacao_lote — mantém o ledger com UMA linha por movimentação (extrato da
-- Sessão #6 e a UNIQUE de baixa intactos) e registra a distribuição por lote ao
-- lado. Convenção de sinal do vínculo = a do ledger: entrada > 0, saída < 0.
--
-- saldo_estoque passa a DERIVAR da soma dos saldos dos lotes (não mais do
-- ledger). Invariante a preservar/testar: sum(lotes.saldo_atual) == soma do
-- ledger, em toda operação bem abastecida. A única divergência possível é a
-- anomalia pré-existente de super-administração (dose além do físico): o ledger
-- já tolerava saldo negativo; o físico não pode ser negativo, então os lotes
-- piso em zero e o ledger guarda o registro completo para auditoria/consumo.
--
-- Esta migration cria o schema e os DOIS helpers transacionais usados pelas RPCs
-- e pelo trigger (Parte 2 e 3): fn_registrar_lote_entrada e fn_consumir_fefo.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- lotes_estoque — um lote físico de um medicamento (DEC-040).
-- "Não há agrupamento": duas entradas do mesmo medicamento com o mesmo
-- lote/validade permanecem linhas separadas se registradas separadamente
-- (cada entrada é um lote; não deduplicar por lote+validade).
--   lote      = código impresso na caixa; NULL = "não identificado" (ajuste de
--               recontagem para cima em que a casa não sabe o lote — DEC-041).
--   validade  = obrigatória: é a chave de ordenação do FEFO.
--   saldo_atual em passos de 0,5 (DEC-013), nunca negativo (prateleira física).
--   origem    = compra | remanescente (do residente); espelha o tipo de
--               movimentação (entrada_compra vs ajuste_contagem — DEC-016).
-- -----------------------------------------------------------------------------
create table public.lotes_estoque (
  id                  uuid primary key default gen_random_uuid(),
  medicamento_id      uuid not null references public.medicamentos (id),
  lote                text,
  validade            date not null,
  quantidade_inicial  numeric(8,2) not null,
  saldo_atual         numeric(8,2) not null,
  data_entrada        date not null default (now() at time zone public.fn_fuso_casa())::date,
  origem              text not null check (origem in ('compra', 'remanescente')),
  criado_em           timestamptz not null default now(),
  constraint lotes_quantidade_inicial_valida
    check (quantidade_inicial > 0 and mod(quantidade_inicial * 2, 1) = 0),
  constraint lotes_saldo_atual_valido
    check (saldo_atual >= 0 and mod(saldo_atual * 2, 1) = 0),
  constraint lotes_saldo_nao_excede_inicial
    check (saldo_atual <= quantidade_inicial)
);

create index lotes_estoque_medicamento_id_idx
  on public.lotes_estoque (medicamento_id);
-- Ordenação e varredura do FEFO: validade asc, desempate por data_entrada
-- (FIFO secundário — DEC-042). Parcial em lotes vivos (o que o FEFO percorre).
create index lotes_estoque_fefo_idx
  on public.lotes_estoque (medicamento_id, validade, data_entrada)
  where saldo_atual > 0;

-- -----------------------------------------------------------------------------
-- movimentacao_lote — distribuição de uma movimentação por lote(s) (DEC-040).
-- quantidade com o sinal do ledger (entrada > 0, saída < 0). on delete cascade:
-- movimentacoes_estoque nunca é apagada em operação normal, mas se um dia for, o
-- vínculo não pode ficar órfão.
-- Invariante estrutural: lotes_estoque.saldo_atual == SUM(quantidade) dos
-- vínculos daquele lote (a entrada cria o +inicial; as saídas somam negativos).
-- -----------------------------------------------------------------------------
create table public.movimentacao_lote (
  id               uuid primary key default gen_random_uuid(),
  movimentacao_id  uuid not null references public.movimentacoes_estoque (id) on delete cascade,
  lote_id          uuid not null references public.lotes_estoque (id),
  quantidade       numeric(8,2) not null,
  constraint movimentacao_lote_qtd_valida
    check (quantidade <> 0 and mod(quantidade * 2, 1) = 0)
);

create index movimentacao_lote_movimentacao_id_idx
  on public.movimentacao_lote (movimentacao_id);
create index movimentacao_lote_lote_id_idx
  on public.movimentacao_lote (lote_id);

-- -----------------------------------------------------------------------------
-- RLS: leitura direta pela cuidadora (a aba Estoque exibe lotes/validade e o
-- extrato mostra o lote das saídas). Escrita só via RPC/trigger SECURITY DEFINER
-- (o dono ignora RLS). anon sem acesso (nenhuma política). Mesmo padrão de
-- movimentacoes_estoque/medicamentos.
-- -----------------------------------------------------------------------------
alter table public.lotes_estoque enable row level security;
alter table public.movimentacao_lote enable row level security;

create policy lotes_select_autenticado on public.lotes_estoque
  for select to authenticated using (true);
create policy movimentacao_lote_select_autenticado on public.movimentacao_lote
  for select to authenticated using (true);

revoke insert, update, delete on public.lotes_estoque from anon, authenticated;
revoke insert, update, delete on public.movimentacao_lote from anon, authenticated;

-- -----------------------------------------------------------------------------
-- saldo_estoque agora deriva da soma dos lotes (DEC-040). Mesmas colunas, mesma
-- ordem e tipos da versão anterior (create or replace preserva cobertura_estoque
-- e extrato_medicamento, que dependem desta view). security_invoker mantido: a
-- view respeita o RLS de lotes_estoque.
-- -----------------------------------------------------------------------------
create or replace view public.saldo_estoque
  with (security_invoker = true)
as
select
  m.id   as medicamento_id,
  m.idoso_id,
  m.nome,
  m.dosagem,
  m.forma_farmaceutica,
  m.tipo,
  m.ativo,
  coalesce(sum(l.saldo_atual), 0) as saldo
from public.medicamentos m
left join public.lotes_estoque l on l.medicamento_id = m.id
group by m.id;

-- -----------------------------------------------------------------------------
-- fn_registrar_lote_entrada — cria um lote e o vínculo (+) na mesma transação da
-- movimentação de entrada. Usado por registrar_entrada_estoque, pelo estoque
-- inicial do cadastro e pelo ajuste de recontagem para cima (Parte 2).
-- Interna (SECURITY DEFINER): chamada de dentro das RPCs do ledger.
-- -----------------------------------------------------------------------------
create or replace function public.fn_registrar_lote_entrada(
  p_medicamento_id  uuid,
  p_movimentacao_id uuid,
  p_lote            text,
  p_validade        date,
  p_quantidade      numeric,
  p_data_entrada    date,
  p_origem          text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lote_id uuid;
begin
  insert into public.lotes_estoque
    (medicamento_id, lote, validade, quantidade_inicial, saldo_atual,
     data_entrada, origem)
  values
    (p_medicamento_id, nullif(trim(coalesce(p_lote, '')), ''), p_validade,
     p_quantidade, p_quantidade,
     coalesce(p_data_entrada, (now() at time zone public.fn_fuso_casa())::date),
     p_origem)
  returning id into v_lote_id;

  insert into public.movimentacao_lote (movimentacao_id, lote_id, quantidade)
  values (p_movimentacao_id, v_lote_id, p_quantidade);

  return v_lote_id;
end;
$$;

revoke execute on function
  public.fn_registrar_lote_entrada(uuid, uuid, text, date, numeric, date, text)
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- fn_consumir_fefo — abate p_quantidade (positivo) dos lotes do medicamento em
-- ordem de validade crescente (desempate: data_entrada, depois criado_em),
-- varrendo quantos lotes forem necessários e criando um vínculo (−) por lote
-- tocado. FOR UPDATE serializa baixas concorrentes do mesmo medicamento.
--
-- Best-effort por desenho: se os lotes não cobrem a quantidade (medicamento sem
-- estoque inicial, ou super-administração), consome o que houver e retorna
-- MENOS que o pedido. Quem chama SEMPRE grava a movimentação de saída cheia no
-- ledger — a ronda nunca falha (DEC-008 preservada); o físico apenas piso em
-- zero. Retorna quanto foi efetivamente abatido.
-- Interna (SECURITY DEFINER): chamada pelo trigger de baixa e pelas RPCs de
-- ajuste-para-baixo e perda (Parte 3).
-- -----------------------------------------------------------------------------
create or replace function public.fn_consumir_fefo(
  p_medicamento_id  uuid,
  p_movimentacao_id uuid,
  p_quantidade      numeric
)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restante numeric := p_quantidade;
  v_tira     numeric;
  r          record;
begin
  for r in
    select id, saldo_atual
    from public.lotes_estoque
    where medicamento_id = p_medicamento_id and saldo_atual > 0
    order by validade asc, data_entrada asc, criado_em asc
    for update
  loop
    exit when v_restante <= 0;
    v_tira := least(v_restante, r.saldo_atual);
    update public.lotes_estoque
       set saldo_atual = saldo_atual - v_tira
     where id = r.id;
    insert into public.movimentacao_lote (movimentacao_id, lote_id, quantidade)
    values (p_movimentacao_id, r.id, -v_tira);
    v_restante := v_restante - v_tira;
  end loop;

  return p_quantidade - v_restante;
end;
$$;

revoke execute on function
  public.fn_consumir_fefo(uuid, uuid, numeric)
  from public, anon, authenticated;
