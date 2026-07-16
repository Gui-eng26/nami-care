-- =============================================================================
-- Migration: hardening apontado pelos security advisors após a Sessão #2
--
-- 1) search_path fixo em fn_fuso_casa (lint 0011) — mesma medida aplicada às
--    demais funções na Sessão #1.
--
-- Avisos que NÃO serão corrigidos (intencionais, documentados no
-- RELATORIO_SESSAO_02.md):
--   - "RLS enabled no policy" em tentativas_pin: proposital — nenhum papel de
--     API acessa a tabela; só as funções SECURITY DEFINER escrevem/leem.
--   - "RLS policy always true": MVP sem perfis (DEC-011), como na Sessão #1.
--   - "SECURITY DEFINER executável por authenticated" em abrir_turno,
--     fechar_turno e definir_pin: são a API intencional do app (DEC-020/022).
-- =============================================================================

alter function public.fn_fuso_casa() set search_path = '';
