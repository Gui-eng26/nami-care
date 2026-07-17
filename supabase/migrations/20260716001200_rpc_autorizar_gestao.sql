-- =============================================================================
-- Migration: RPC autorizar_gestao (Sessão #3 — DEC-024)
--
-- Porta de entrada da área de gestão no app: valida a credencial de
-- administradora ANTES de abrir as telas (PIN errado é descoberto na entrada,
-- não na hora de salvar). É só um invólucro exposto de fn_autorizar_admin —
-- cada RPC de gestão continua revalidando a credencial por conta própria
-- (o app não ganha nenhum "estado autorizado" no servidor).
-- =============================================================================

create or replace function public.autorizar_gestao(p_admin_id uuid, p_admin_pin text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  return public.fn_autorizar_admin(p_admin_id, p_admin_pin);
end;
$$;

revoke execute on function public.autorizar_gestao(uuid, text)
  from public, anon;
