-- =============================================================================
-- Migration: mecanismo definitivo de PIN (DEC-020, DEC-021 — substitui DEC-018)
--
-- 1) Hash: bcrypt via pgcrypto (crypt + gen_salt('bf', 10)), salt por cuidador
--    embutido no próprio hash. PIN aceito: 4 a 6 dígitos numéricos.
-- 2) Verificação SEMPRE server-side: o hash nunca chega ao cliente — os papéis
--    de API perdem acesso à coluna pin_hash (grants por coluna).
-- 3) Rate limit (DEC-021): tentativas registradas em tentativas_pin; 5 falhas
--    do mesmo cuidador em janela móvel de 15 min bloqueiam novas tentativas
--    até a mais antiga das 5 sair da janela. A checagem vive em abrir_turno
--    (migration seguinte).
-- 4) Dados de seed: converte os pin_hash SHA-256 dos PINs de teste conhecidos
--    para bcrypt.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- tentativas_pin — trilha de tentativas de login por PIN (sucesso e falha).
-- Sem nenhuma política de RLS e sem grants de API: só as funções SECURITY
-- DEFINER (e o service_role) leem/escrevem.
-- -----------------------------------------------------------------------------
create table public.tentativas_pin (
  id           uuid primary key default gen_random_uuid(),
  cuidador_id  uuid not null references public.cuidadores (id),
  sucesso      boolean not null,
  tentado_em   timestamptz not null default now()
);

create index tentativas_pin_falhas_recentes_idx
  on public.tentativas_pin (cuidador_id, tentado_em desc)
  where not sucesso;

alter table public.tentativas_pin enable row level security;

-- O projeto tem default privileges que dão ALL aos papéis de API em tabelas
-- novas de public — revogação explícita obrigatória.
revoke all on table public.tentativas_pin from anon, authenticated;

-- -----------------------------------------------------------------------------
-- pin_hash sai do alcance do cliente: acesso por coluna em cuidadores.
-- INSERT direto também sai (pin_hash é NOT NULL e só nasce via seed/RPC);
-- cadastro de cuidador pelo app entra em sessão futura com RPC própria.
-- -----------------------------------------------------------------------------
revoke all on table public.cuidadores from anon, authenticated;
grant select (id, nome, ativo, criado_em) on public.cuidadores to authenticated;
grant update (nome, ativo) on public.cuidadores to authenticated;

-- -----------------------------------------------------------------------------
-- fn_hash_pin — único ponto que produz hash de PIN.
-- SECURITY DEFINER apenas para alcançar extensions.gen_salt (os papéis de API
-- não têm EXECUTE no schema extensions); não lê nenhum dado.
-- -----------------------------------------------------------------------------
create or replace function public.fn_hash_pin(p_pin text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_pin is null or p_pin !~ '^[0-9]{4,6}$' then
    raise exception 'PIN deve ter de 4 a 6 dígitos numéricos';
  end if;
  return extensions.crypt(p_pin, extensions.gen_salt('bf', 10));
end;
$$;

revoke execute on function public.fn_hash_pin(text) from public, anon, authenticated;
grant execute on function public.fn_hash_pin(text) to service_role;

-- -----------------------------------------------------------------------------
-- definir_pin — troca de PIN pelo app (qualquer cuidador autenticado; DEC-011).
-- -----------------------------------------------------------------------------
create or replace function public.definir_pin(p_cuidador_id uuid, p_pin text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.cuidadores
     set pin_hash = public.fn_hash_pin(p_pin)
   where id = p_cuidador_id;
  if not found then
    raise exception 'Cuidador não encontrado';
  end if;
end;
$$;

revoke execute on function public.definir_pin(uuid, text) from public, anon;

-- -----------------------------------------------------------------------------
-- Dados de seed: SHA-256 (formato provisório da DEC-018) → bcrypt.
-- Converte apenas linhas que ainda estejam exatamente no hash antigo dos PINs
-- de teste conhecidos; num banco recém-criado (zero linhas) é um no-op.
-- -----------------------------------------------------------------------------
update public.cuidadores c
   set pin_hash = public.fn_hash_pin(p.pin)
  from (values ('1111'), ('2222'), ('3333'), ('4444')) as p(pin)
 where c.pin_hash = encode(extensions.digest(p.pin, 'sha256'), 'hex');

do $$
declare
  v_restantes int;
begin
  select count(*) into v_restantes
    from public.cuidadores
   where pin_hash not like '$2%';
  if v_restantes > 0 then
    raise warning
      'Nami Care: % cuidador(es) seguem com pin_hash fora do formato bcrypt — redefinir via definir_pin()',
      v_restantes;
  end if;
end;
$$;
