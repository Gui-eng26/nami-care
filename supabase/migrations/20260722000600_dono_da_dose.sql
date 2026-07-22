-- =============================================================================
-- Migration: dono real da dose em administracoes (Sessão #12 — DEC-045)
--
-- O problema: `administracoes` não tem "quem tomou". O residente sempre foi
-- DERIVADO por `administracoes.medicamento_id → medicamentos.idoso_id`. Para um
-- medicamento da casa (DEC-044) essa corrente aponta para o "Da Casa", não para
-- quem tomou — e o consumo cairia na adesão de um residente que não existe. O
-- rastro clínico se perderia exatamente onde ele mais importa.
--
-- Esta é a ÚNICA mudança de schema do Modelo B.
--
-- Regra de preenchimento (uma coluna, três casos):
--   dose agendada (contínua, horario_id não nulo)      → idoso_id NULO
--   dose SOS de medicamento DE UM RESIDENTE            → idoso_id NULO
--   dose SOS de medicamento DA CASA                    → idoso_id PREENCHIDO
-- Ou seja: o único caminho que preenche é o SOS da casa. Nos demais a coluna
-- fica nula e é ignorada — O FLUXO DA DOSE AGENDADA NÃO MUDA EM NADA (nem o
-- insert da ronda, nem a tela).
--
-- Resolução do dono (uma regra, vale para todos):
--     coalesce(administracoes.idoso_id, medicamentos.idoso_id)
-- o residente-que-tomou se preenchido, senão o dono do medicamento. Aplicada na
-- adesão (DEC-046) e em qualquer lugar que derive o residente de uma dose.
--
-- Integridade por TRIGGER e não por CHECK: a regra depende de uma linha de
-- `idosos` (o medicamento é da casa?), fora do alcance de um CHECK. Os dois
-- lados são fechados — SOS da casa SEM dono é rejeitado, e dose de medicamento
-- de residente COM dono também é (divergência entre dois donos é pior que a
-- ausência de um, porque parece informação).
--
-- `administracoes` continua imutável após gravada (DEC-008): a coluna entra no
-- INSERT e passa a ser protegida pelo trigger de imutabilidade.
-- =============================================================================

alter table public.administracoes
  add column idoso_id uuid references public.idosos (id);

create index administracoes_idoso_id_idx
  on public.administracoes (idoso_id) where idoso_id is not null;

comment on column public.administracoes.idoso_id is
  'Residente que efetivamente TOMOU a dose. Preenchido só no SOS de medicamento da casa (DEC-045); nulo nos demais, onde o dono vem de medicamentos.idoso_id. Dono resolvido = coalesce(administracoes.idoso_id, medicamentos.idoso_id).';

-- -----------------------------------------------------------------------------
-- Integridade do dono da dose.
-- -----------------------------------------------------------------------------
create or replace function public.fn_administracao_dono_valido()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_da_casa boolean;
begin
  select i.eh_sentinela
    into v_da_casa
    from public.medicamentos m
    join public.idosos i on i.id = m.idoso_id
   where m.id = new.medicamento_id;

  if coalesce(v_da_casa, false) then
    -- Medicamento da casa: o dono da dose é obrigatório, senão o consumo fica
    -- órfão ("saiu da caixa comum, não sei pra quem") — DEC-045.
    if new.idoso_id is null then
      raise exception
        'Dose de medicamento da casa exige o residente que tomou (DEC-045)';
    end if;
    if new.horario_id is not null then
      raise exception
        'Medicamento da casa é SOS: dose agendada não existe para ele (DEC-044)';
    end if;
    if not exists (select 1 from public.idosos i
                    where i.id = new.idoso_id and i.ativo and not i.eh_sentinela) then
      raise exception
        'O residente que tomou precisa ser um residente ativo — ninguém toma "como a casa" (DEC-047)';
    end if;
  else
    -- Medicamento de residente: o dono já vem do medicamento. Um segundo dono
    -- na dose só criaria divergência.
    if new.idoso_id is not null then
      raise exception
        'Dose de medicamento de residente não leva residente-que-tomou: o dono vem do medicamento (DEC-045)';
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_administracao_dono_valido
  before insert on public.administracoes
  for each row execute function public.fn_administracao_dono_valido();

-- -----------------------------------------------------------------------------
-- Imutabilidade (DEC-008) estendida à coluna nova: o dono da dose é registro de
-- auditoria como o resto da linha. Único acréscimo em relação à versão da
-- Sessão #2.
-- -----------------------------------------------------------------------------
create or replace function public.fn_administracao_imutavel()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status is distinct from old.status
     or new.qtd is distinct from old.qtd
     or new.medicamento_id is distinct from old.medicamento_id
     or new.horario_id is distinct from old.horario_id
     or new.idoso_id is distinct from old.idoso_id
     or new.cuidador_id is distinct from old.cuidador_id
     or new.registrado_em is distinct from old.registrado_em
     or new.prevista_em is distinct from old.prevista_em then
    raise exception
      'Administração é imutável (auditoria): corrija com novo registro e ajuste de estoque';
  end if;
  return new;
end;
$$;
