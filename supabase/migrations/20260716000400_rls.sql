-- =============================================================================
-- Migration: Row Level Security
--
-- MVP (DEC-011): qualquer cuidador autenticado lê e escreve; anônimos sem
-- acesso (nenhuma política para anon).
--
-- Granularidade por operação:
--   - Cadastros (cuidadores, idosos, medicamentos, horarios, turnos):
--     select / insert / update. Sem DELETE — remoção é soft delete (DEC-006).
--   - Auditoria (administracoes, movimentacoes_estoque): select / insert
--     apenas — ledger e trilha de administração são imutáveis pelo app;
--     correções entram como novas movimentações (ajuste_contagem / perda).
-- =============================================================================

alter table public.cuidadores            enable row level security;
alter table public.turnos                enable row level security;
alter table public.idosos                enable row level security;
alter table public.medicamentos          enable row level security;
alter table public.horarios              enable row level security;
alter table public.administracoes        enable row level security;
alter table public.movimentacoes_estoque enable row level security;

-- Cadastros: leitura + escrita + edição para autenticados
create policy cuidadores_select_autenticado on public.cuidadores
  for select to authenticated using (true);
create policy cuidadores_insert_autenticado on public.cuidadores
  for insert to authenticated with check (true);
create policy cuidadores_update_autenticado on public.cuidadores
  for update to authenticated using (true) with check (true);

create policy turnos_select_autenticado on public.turnos
  for select to authenticated using (true);
create policy turnos_insert_autenticado on public.turnos
  for insert to authenticated with check (true);
create policy turnos_update_autenticado on public.turnos
  for update to authenticated using (true) with check (true);

create policy idosos_select_autenticado on public.idosos
  for select to authenticated using (true);
create policy idosos_insert_autenticado on public.idosos
  for insert to authenticated with check (true);
create policy idosos_update_autenticado on public.idosos
  for update to authenticated using (true) with check (true);

create policy medicamentos_select_autenticado on public.medicamentos
  for select to authenticated using (true);
create policy medicamentos_insert_autenticado on public.medicamentos
  for insert to authenticated with check (true);
create policy medicamentos_update_autenticado on public.medicamentos
  for update to authenticated using (true) with check (true);

create policy horarios_select_autenticado on public.horarios
  for select to authenticated using (true);
create policy horarios_insert_autenticado on public.horarios
  for insert to authenticated with check (true);
create policy horarios_update_autenticado on public.horarios
  for update to authenticated using (true) with check (true);

-- Auditoria: somente leitura + inserção
create policy administracoes_select_autenticado on public.administracoes
  for select to authenticated using (true);
create policy administracoes_insert_autenticado on public.administracoes
  for insert to authenticated with check (true);

create policy movimentacoes_select_autenticado on public.movimentacoes_estoque
  for select to authenticated using (true);
create policy movimentacoes_insert_autenticado on public.movimentacoes_estoque
  for insert to authenticated with check (true);
