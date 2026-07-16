-- =============================================================================
-- Migration: hardening apontado pelos security advisors do Supabase
--
-- 1) search_path fixo nas funções de trigger (lint 0011): evita que um
--    search_path malicioso da sessão troque as tabelas referenciadas.
-- 2) rls_auto_enable(): utilitário de plataforma (event trigger) SECURITY
--    DEFINER — não precisa ser executável pelos papéis de API (lints 0028/0029).
--
-- Os avisos "RLS policy always true" NÃO serão corrigidos: são intencionais
-- no MVP (DEC-011 — todo cuidador autenticado lê e escreve tudo).
-- =============================================================================

alter function public.fn_horario_exige_continuo() set search_path = public;
alter function public.fn_medicamento_sos_sem_horarios() set search_path = public;
alter function public.fn_administracao_imutavel() set search_path = public;

revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
