-- =============================================================================
-- Migration: gestão de cuidadoras (DEC-024, DEC-025 — Sessão #3)
--
-- 1) cuidadores.eh_admin: quem pode usar a área de gestão (DEC-024). O acesso
--    é validado NO BANCO em cada RPC de gestão (fn_autorizar_admin): bcrypt da
--    DEC-020 + rate limit da DEC-021 + trilha em tentativas_pin. Sem sessão de
--    gestão no servidor — o app reenvia o PIN de administradora a cada chamada.
-- 2) fn_verificar_pin: verificação de PIN reutilizável (formato, cuidador
--    ativo, rate limit, bcrypt, trilha). abrir_turno mantém a própria cópia da
--    lógica para não mexer no fluxo estável da Sessão #2 (MH-001).
-- 3) RPCs de gestão de cuidadoras: criar_cuidador, atualizar_cuidador,
--    definir_ativo_cuidador (desativação, NUNCA exclusão — o histórico de
--    administrações exige a linha para auditoria).
-- 4) trocar_pin (self-service, exige PIN atual) e redefinir_pin (por
--    administradora) substituem definir_pin, que trocava PIN sem verificação
--    nenhuma (BUG-001 — qualquer authenticated trocava o PIN de qualquer uma).
-- 5) Escrita direta em cuidadores sai por completo do cliente: as RPCs são o
--    único caminho (mesmo padrão da Sessão #2 para turnos).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Flag de administradora (DEC-024).
-- -----------------------------------------------------------------------------
alter table public.cuidadores
  add column eh_admin boolean not null default false;

-- O cliente pode saber quem é admin (para a tela de entrada da gestão)…
grant select (eh_admin) on public.cuidadores to authenticated;

-- …mas perde o que restava de escrita direta (grant update (nome, ativo) da
-- Sessão #2). Toda escrita em cuidadores passa pelas RPCs abaixo.
revoke update on table public.cuidadores from anon, authenticated;
drop policy cuidadores_insert_autenticado on public.cuidadores;
drop policy cuidadores_update_autenticado on public.cuidadores;

-- Bootstrap do seed: Ana Souza vira administradora (a administradora real —
-- Thais — será criada no cadastro dos dados reais, Sessão #5). No-op se não
-- houver seed ou se já existir alguma admin.
update public.cuidadores
   set eh_admin = true
 where nome = 'Ana Souza'
   and not exists (select 1 from public.cuidadores where eh_admin);

-- -----------------------------------------------------------------------------
-- fn_verificar_pin — verificação de PIN com rate limit (DEC-020/DEC-021).
-- Interna: sem EXECUTE para os papéis de API; só as RPCs SECURITY DEFINER usam.
-- Retorno: {ok:true, nome, eh_admin} |
--          {ok:false, erro: pin_invalido | cuidador_nao_encontrado |
--                     pin_bloqueado (+desbloqueia_em) |
--                     pin_incorreto (+tentativas_restantes)}
-- -----------------------------------------------------------------------------
create or replace function public.fn_verificar_pin(p_cuidador_id uuid, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c_max_falhas constant int := 5;
  c_janela     constant interval := interval '15 minutes';
  v_cuidador     public.cuidadores;
  v_falhas       int;
  v_desbloqueia  timestamptz;
begin
  if p_pin is null or p_pin !~ '^[0-9]{4,6}$' then
    return jsonb_build_object('ok', false, 'erro', 'pin_invalido');
  end if;

  select * into v_cuidador
    from public.cuidadores
   where id = p_cuidador_id and ativo;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'cuidador_nao_encontrado');
  end if;

  select count(*), min(tentado_em) + c_janela
    into v_falhas, v_desbloqueia
    from (
      select tentado_em
        from public.tentativas_pin
       where cuidador_id = p_cuidador_id
         and not sucesso
         and tentado_em > now() - c_janela
       order by tentado_em desc
       limit c_max_falhas
    ) ultimas_falhas;

  if v_falhas >= c_max_falhas then
    return jsonb_build_object('ok', false, 'erro', 'pin_bloqueado',
                              'desbloqueia_em', v_desbloqueia);
  end if;

  if v_cuidador.pin_hash <> extensions.crypt(p_pin, v_cuidador.pin_hash) then
    insert into public.tentativas_pin (cuidador_id, sucesso)
    values (p_cuidador_id, false);
    return jsonb_build_object('ok', false, 'erro', 'pin_incorreto',
                              'tentativas_restantes',
                              greatest(c_max_falhas - v_falhas - 1, 0));
  end if;

  insert into public.tentativas_pin (cuidador_id, sucesso)
  values (p_cuidador_id, true);

  return jsonb_build_object('ok', true, 'nome', v_cuidador.nome,
                            'eh_admin', v_cuidador.eh_admin);
end;
$$;

revoke execute on function public.fn_verificar_pin(uuid, text)
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- fn_autorizar_admin — porteiro das RPCs de gestão (DEC-024).
-- Interna, como fn_verificar_pin. Acrescenta o erro: nao_administradora.
-- -----------------------------------------------------------------------------
create or replace function public.fn_autorizar_admin(p_admin_id uuid, p_admin_pin text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_verificacao jsonb;
begin
  v_verificacao := public.fn_verificar_pin(p_admin_id, p_admin_pin);
  if not (v_verificacao ->> 'ok')::boolean then
    return v_verificacao;
  end if;
  if not (v_verificacao ->> 'eh_admin')::boolean then
    return jsonb_build_object('ok', false, 'erro', 'nao_administradora');
  end if;
  return v_verificacao;
end;
$$;

revoke execute on function public.fn_autorizar_admin(uuid, text)
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- criar_cuidador — resolve o risco nº 1 do relatório da Sessão #2: o cliente
-- não conhece pin_hash; o hash nasce no banco via fn_hash_pin (DEC-020).
-- -----------------------------------------------------------------------------
create or replace function public.criar_cuidador(
  p_admin_id  uuid,
  p_admin_pin text,
  p_nome      text,
  p_pin       text,
  p_eh_admin  boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth jsonb;
  v_nome text;
  v_id   uuid;
begin
  v_auth := public.fn_autorizar_admin(p_admin_id, p_admin_pin);
  if not (v_auth ->> 'ok')::boolean then
    return v_auth;
  end if;

  v_nome := trim(coalesce(p_nome, ''));
  if v_nome = '' then
    return jsonb_build_object('ok', false, 'erro', 'nome_obrigatorio');
  end if;
  if exists (select 1 from public.cuidadores
              where ativo and lower(nome) = lower(v_nome)) then
    return jsonb_build_object('ok', false, 'erro', 'nome_duplicado');
  end if;
  if p_pin is null or p_pin !~ '^[0-9]{4,6}$' then
    return jsonb_build_object('ok', false, 'erro', 'pin_invalido_novo');
  end if;

  insert into public.cuidadores (nome, pin_hash, eh_admin)
  values (v_nome, public.fn_hash_pin(p_pin), coalesce(p_eh_admin, false))
  returning id into v_id;

  return jsonb_build_object('ok', true, 'cuidador',
    jsonb_build_object('id', v_id, 'nome', v_nome,
                       'eh_admin', coalesce(p_eh_admin, false)));
end;
$$;

revoke execute on function public.criar_cuidador(uuid, text, text, text, boolean)
  from public, anon;

-- -----------------------------------------------------------------------------
-- atualizar_cuidador — nome e flag de admin. Guarda: nunca deixar a casa sem
-- administradora ativa (a área de gestão ficaria trancada para sempre).
-- -----------------------------------------------------------------------------
create or replace function public.atualizar_cuidador(
  p_admin_id    uuid,
  p_admin_pin   text,
  p_cuidador_id uuid,
  p_nome        text,
  p_eh_admin    boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth  jsonb;
  v_nome  text;
  v_atual public.cuidadores;
begin
  v_auth := public.fn_autorizar_admin(p_admin_id, p_admin_pin);
  if not (v_auth ->> 'ok')::boolean then
    return v_auth;
  end if;

  select * into v_atual from public.cuidadores where id = p_cuidador_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'cuidador_nao_encontrado');
  end if;

  v_nome := trim(coalesce(p_nome, ''));
  if v_nome = '' then
    return jsonb_build_object('ok', false, 'erro', 'nome_obrigatorio');
  end if;
  if exists (select 1 from public.cuidadores
              where ativo and lower(nome) = lower(v_nome)
                and id <> p_cuidador_id) then
    return jsonb_build_object('ok', false, 'erro', 'nome_duplicado');
  end if;

  if v_atual.eh_admin and not coalesce(p_eh_admin, false)
     and not exists (select 1 from public.cuidadores
                      where eh_admin and ativo and id <> p_cuidador_id) then
    return jsonb_build_object('ok', false, 'erro', 'ultima_administradora');
  end if;

  update public.cuidadores
     set nome = v_nome, eh_admin = coalesce(p_eh_admin, false)
   where id = p_cuidador_id;

  return jsonb_build_object('ok', true);
end;
$$;

revoke execute on function public.atualizar_cuidador(uuid, text, uuid, text, boolean)
  from public, anon;

-- -----------------------------------------------------------------------------
-- definir_ativo_cuidador — desativação/reativação; NUNCA exclusão (auditoria).
-- Guardas: turno aberto impede desativar; última admin ativa idem; reativar
-- não pode colidir nome com outra ativa.
-- -----------------------------------------------------------------------------
create or replace function public.definir_ativo_cuidador(
  p_admin_id    uuid,
  p_admin_pin   text,
  p_cuidador_id uuid,
  p_ativo       boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth  jsonb;
  v_atual public.cuidadores;
begin
  v_auth := public.fn_autorizar_admin(p_admin_id, p_admin_pin);
  if not (v_auth ->> 'ok')::boolean then
    return v_auth;
  end if;

  select * into v_atual from public.cuidadores where id = p_cuidador_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'cuidador_nao_encontrado');
  end if;
  if v_atual.ativo = p_ativo then
    return jsonb_build_object('ok', true);
  end if;

  if not p_ativo then
    if exists (select 1 from public.turnos
                where cuidador_id = p_cuidador_id and fim is null) then
      return jsonb_build_object('ok', false, 'erro', 'turno_aberto');
    end if;
    if v_atual.eh_admin
       and not exists (select 1 from public.cuidadores
                        where eh_admin and ativo and id <> p_cuidador_id) then
      return jsonb_build_object('ok', false, 'erro', 'ultima_administradora');
    end if;
  else
    if exists (select 1 from public.cuidadores
                where ativo and lower(nome) = lower(v_atual.nome)
                  and id <> p_cuidador_id) then
      return jsonb_build_object('ok', false, 'erro', 'nome_duplicado');
    end if;
  end if;

  update public.cuidadores set ativo = p_ativo where id = p_cuidador_id;
  return jsonb_build_object('ok', true);
end;
$$;

revoke execute on function public.definir_ativo_cuidador(uuid, text, uuid, boolean)
  from public, anon;

-- -----------------------------------------------------------------------------
-- trocar_pin — self-service: exige o PIN atual (DEC-025), com o mesmo rate
-- limit do login (senão viraria um oráculo de força bruta).
-- -----------------------------------------------------------------------------
create or replace function public.trocar_pin(
  p_cuidador_id uuid,
  p_pin_atual   text,
  p_pin_novo    text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_verificacao jsonb;
begin
  if p_pin_novo is null or p_pin_novo !~ '^[0-9]{4,6}$' then
    return jsonb_build_object('ok', false, 'erro', 'pin_invalido_novo');
  end if;

  v_verificacao := public.fn_verificar_pin(p_cuidador_id, p_pin_atual);
  if not (v_verificacao ->> 'ok')::boolean then
    return v_verificacao;
  end if;

  update public.cuidadores
     set pin_hash = public.fn_hash_pin(p_pin_novo)
   where id = p_cuidador_id;

  return jsonb_build_object('ok', true);
end;
$$;

revoke execute on function public.trocar_pin(uuid, text, text)
  from public, anon;

-- -----------------------------------------------------------------------------
-- redefinir_pin — reset por administradora (esquecimento — DEC-025).
-- -----------------------------------------------------------------------------
create or replace function public.redefinir_pin(
  p_admin_id    uuid,
  p_admin_pin   text,
  p_cuidador_id uuid,
  p_pin_novo    text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth jsonb;
begin
  v_auth := public.fn_autorizar_admin(p_admin_id, p_admin_pin);
  if not (v_auth ->> 'ok')::boolean then
    return v_auth;
  end if;

  if p_pin_novo is null or p_pin_novo !~ '^[0-9]{4,6}$' then
    return jsonb_build_object('ok', false, 'erro', 'pin_invalido_novo');
  end if;

  update public.cuidadores
     set pin_hash = public.fn_hash_pin(p_pin_novo)
   where id = p_cuidador_id and ativo;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'cuidador_nao_encontrado');
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

revoke execute on function public.redefinir_pin(uuid, text, uuid, text)
  from public, anon;

-- -----------------------------------------------------------------------------
-- BUG-001: definir_pin trocava PIN sem verificação nenhuma. Fora.
-- -----------------------------------------------------------------------------
drop function public.definir_pin(uuid, text);
