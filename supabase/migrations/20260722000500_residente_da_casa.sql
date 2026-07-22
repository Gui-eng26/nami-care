-- =============================================================================
-- Migration: residente-sentinela "Da Casa" (Sessão #12 — DEC-044)
--
-- A casa tem medicamentos SOS que não pertencem a ninguém em particular
-- (dipirona para dor de cabeça, antitérmico, antiemético). Até aqui o app
-- exigia que todo medicamento tivesse dono: `medicamentos.idoso_id` é NOT NULL.
--
-- Desenho escolhido (Modelo B): UM RESIDENTE RESERVADO carrega esse estoque.
--   - `medicamentos.idoso_id` PERMANECE NOT NULL — o schema de medicamentos não
--     muda, e os ~16 pontos do banco que fazem `join idosos` continuam intactos.
--   - Não há flag `eh_da_casa` em medicamentos: um medicamento é "da casa"
--     porque pertence AO residente da casa, e pronto.
--   - O sentinela é identificado por `idosos.eh_sentinela` (booleano estável),
--     não por id hardcodado: nada no código nem no seed depende de um uuid fixo.
--
-- O princípio que governa a sessão: o ESTOQUE pode ser da casa, mas o CONSUMO
-- tem sempre um dono. "Saiu uma dipirona da casa, não sei pra quem" é
-- exatamente o rastro opaco que o Nami Care existe para eliminar — daí a coluna
-- de dono da dose na migration seguinte (DEC-045).
--
-- Bootstrap, não migration de dados: a linha do "Da Casa" nasce de uma função
-- IDEMPOTENTE (`fn_bootstrap_residente_da_casa`), chamada aqui uma vez e também
-- pelo seed. Rodar de novo não duplica; um banco recriado do zero pelo seed
-- chega ao mesmo estado sem depender desta migration ter inserido nada.
--
-- Medicamento da casa é SEMPRE SOS (Parte 4 do roteiro): a casa não tem
-- medicamento contínuo compartilhado — contínuo tem horário, e horário é de
-- alguém. Garantido por trigger (pega também o seed, que escreve com service
-- role e passa por fora das RPCs).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) idosos.eh_sentinela — o marcador do residente da casa. Único por índice
--    parcial: existe no máximo um sentinela (não há "múltiplas casas"/setores).
-- -----------------------------------------------------------------------------
alter table public.idosos
  add column eh_sentinela boolean not null default false;

create unique index idosos_sentinela_unico
  on public.idosos (eh_sentinela) where eh_sentinela;

comment on column public.idosos.eh_sentinela is
  'Residente reservado que carrega o estoque compartilhado da casa (DEC-044). Não é uma pessoa: não aparece no seletor de "quem tomou" nem gera linha de adesão.';

-- -----------------------------------------------------------------------------
-- 2) fn_idoso_da_casa — o id do sentinela, para quem precisa dele no banco.
--    stable: o sentinela não muda dentro de uma transação.
-- -----------------------------------------------------------------------------
create or replace function public.fn_idoso_da_casa()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id from public.idosos where eh_sentinela limit 1;
$$;

revoke execute on function public.fn_idoso_da_casa() from public, anon;

-- -----------------------------------------------------------------------------
-- 3) fn_bootstrap_residente_da_casa — cria o "Da Casa" se ele ainda não existe.
--    Idempotente por construção; devolve o id em qualquer caso.
-- -----------------------------------------------------------------------------
create or replace function public.fn_bootstrap_residente_da_casa()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select id into v_id from public.idosos where eh_sentinela;
  if found then
    return v_id;
  end if;

  insert into public.idosos (nome, observacoes, eh_sentinela)
  values (
    'Da Casa',
    'Estoque compartilhado da casa: medicamentos SOS que não pertencem a um '
    || 'residente. Quem toma é sempre registrado no nome da pessoa (DEC-044).',
    true
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function public.fn_bootstrap_residente_da_casa()
  from public, anon;

select public.fn_bootstrap_residente_da_casa();

-- -----------------------------------------------------------------------------
-- 4) Medicamento da casa é sempre SOS. Trigger (não CHECK): a regra depende de
--    uma linha de idosos, fora do alcance de um CHECK. Vale para todo caminho
--    de escrita — RPC, seed, correção manual.
-- -----------------------------------------------------------------------------
create or replace function public.fn_medicamento_da_casa_eh_sos()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.tipo <> 'sos'
     and exists (select 1 from public.idosos i
                  where i.id = new.idoso_id and i.eh_sentinela) then
    raise exception
      'Medicamento da casa é sempre SOS: contínuo tem horário, e horário é de alguém (DEC-044)';
  end if;
  return new;
end;
$$;

create trigger trg_medicamento_da_casa_eh_sos
  before insert or update on public.medicamentos
  for each row execute function public.fn_medicamento_da_casa_eh_sos();

-- -----------------------------------------------------------------------------
-- 5) O sentinela não é desativável. Desativá-lo tiraria o estoque da casa da
--    cobertura e do fluxo SOS sem que nada tivesse mudado no mundo físico — a
--    caixa comum continua na prateleira. Renomear e editar segue permitido
--    (atualizar_residente intocado): o rótulo é da casa.
-- -----------------------------------------------------------------------------
create or replace function public.definir_ativo_residente(
  p_idoso_id uuid,
  p_ativo    boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_atual public.idosos;
begin
  if public.fn_cuidador_do_turno() is null then
    return jsonb_build_object('ok', false, 'erro', 'sem_turno_aberto');
  end if;

  select * into v_atual from public.idosos where id = p_idoso_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'residente_nao_encontrado');
  end if;
  if v_atual.eh_sentinela and not p_ativo then
    return jsonb_build_object('ok', false, 'erro', 'residente_da_casa_fixo');
  end if;
  if v_atual.ativo = p_ativo then
    return jsonb_build_object('ok', true);
  end if;
  if p_ativo and exists (select 1 from public.idosos
                          where ativo and lower(nome) = lower(v_atual.nome)
                            and id <> p_idoso_id) then
    return jsonb_build_object('ok', false, 'erro', 'nome_duplicado');
  end if;

  update public.idosos set ativo = p_ativo where id = p_idoso_id;
  return jsonb_build_object('ok', true);
end;
$$;

revoke execute on function public.definir_ativo_residente(uuid, boolean)
  from public, anon;

-- -----------------------------------------------------------------------------
-- 6) cobertura_estoque ganha `idoso_da_casa` — a única coisa que as telas
--    precisam para separar a seção "Medicamentos da casa" do estoque dos
--    residentes e para montar a lista do SOS. Coluna acrescentada ao FIM
--    (create or replace view exige preservar nome/ordem/tipo das existentes);
--    nada mais da view muda. `extrato_medicamento`, que lê colunas nomeadas
--    daqui, segue funcionando sem tocar.
-- -----------------------------------------------------------------------------
create or replace view public.cobertura_estoque
  with (security_invoker = true)
as
with doses_dia as (
  select h.medicamento_id, sum(h.qtd_dose) as doses_por_dia
  from public.horarios h
  where h.ativo
  group by h.medicamento_id
)
select
  s.medicamento_id,
  s.idoso_id,
  i.nome  as nome_idoso,
  i.ativo as idoso_ativo,
  s.nome,
  s.dosagem,
  s.forma_farmaceutica,
  s.tipo,
  s.ativo,
  s.saldo,
  m.estoque_minimo,
  d.doses_por_dia,
  case
    when s.tipo = 'continuo' and d.doses_por_dia > 0
    then round(s.saldo / d.doses_por_dia, 1)
  end as cobertura_dias,
  case
    when not (s.ativo and i.ativo) then false
    when s.tipo = 'continuo'
      then coalesce(d.doses_por_dia > 0 and s.saldo / d.doses_por_dia < 5, false)
    else coalesce(s.saldo < m.estoque_minimo, false)
  end as alerta_reposicao,
  case
    when s.ativo and i.ativo and s.tipo = 'continuo'
         and d.doses_por_dia > 0 and s.saldo / d.doses_por_dia < 5
    then greatest(ceil(d.doses_por_dia * 30 - s.saldo), 0)
  end as sugestao_compra,
  i.eh_sentinela as idoso_da_casa
from public.saldo_estoque s
join public.medicamentos m on m.id = s.medicamento_id
join public.idosos i on i.id = s.idoso_id
left join doses_dia d on d.medicamento_id = s.medicamento_id;
