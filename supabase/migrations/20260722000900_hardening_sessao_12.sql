-- =============================================================================
-- Migration: hardening da Sessão #12 (advisors)
--
-- `fn_idoso_da_casa` e `fn_bootstrap_residente_da_casa` são helpers INTERNOS
-- (DEC-044), não RPCs do app: nenhuma tela chama nenhuma das duas. O padrão da
-- casa para helper interno já está estabelecido desde a Sessão #11
-- (fn_consumir_fefo / fn_registrar_lote_entrada): execute revogado também de
-- `authenticated`, restando o service role — que é quem o seed usa para o
-- bootstrap — e os caminhos SECURITY DEFINER internos.
--
-- Some do advisor `authenticated_security_definer_function_executable` as duas
-- entradas novas desta sessão; as demais são as RPCs de verdade do app, na
-- mesma situação de sempre (uma casa, um usuário Supabase — DEC-011/019).
-- =============================================================================

revoke execute on function public.fn_idoso_da_casa()
  from authenticated;

revoke execute on function public.fn_bootstrap_residente_da_casa()
  from authenticated;
