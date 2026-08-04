-- Sessão #15, Parte 3 (DEC-053): fator de conversão congelado no lote.
-- Nasce nullable: nenhum lote líquido existe hoje (auditoria da Parte 0); preenchido
-- na entrada de compra quando a UI/RPC de líquidos for construída (Parte 4).
alter table public.lotes_estoque add column gotas_por_ml numeric(6,2);
