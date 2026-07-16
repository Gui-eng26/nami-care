-- =============================================================================
-- Migration: baixa automática de estoque (DEC-008 — implementada como trigger)
--
-- Regra (BRIEFING.md §7):
--   tomado_no_horario / tomado_atrasado → movimentação 'saida_administracao'
--   recusado                            → movimentação 'perda' (DEC-009)
--   nao_tomado                          → sem movimentação
--
-- A movimentação herda registrado_em como criado_em: a baixa acontece no
-- momento da administração, inclusive em registros tardios (DEC-010).
-- A UNIQUE em movimentacoes_estoque.administracao_id impede dupla baixa.
-- =============================================================================

create or replace function public.fn_baixa_automatica_estoque()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status in ('tomado_no_horario', 'tomado_atrasado') then
    insert into public.movimentacoes_estoque
      (medicamento_id, cuidador_id, administracao_id, tipo, quantidade, motivo, criado_em)
    values
      (new.medicamento_id, new.cuidador_id, new.id, 'saida_administracao',
       -new.qtd, 'Baixa automática — dose administrada', new.registrado_em);
  elsif new.status = 'recusado' then
    insert into public.movimentacoes_estoque
      (medicamento_id, cuidador_id, administracao_id, tipo, quantidade, motivo, criado_em)
    values
      (new.medicamento_id, new.cuidador_id, new.id, 'perda',
       -new.qtd, 'Perda — dose recusada pelo idoso (DEC-009)', new.registrado_em);
  end if;
  -- nao_tomado: nenhuma movimentação
  return new;
end;
$$;

create trigger trg_baixa_automatica_estoque
  after insert on public.administracoes
  for each row execute function public.fn_baixa_automatica_estoque();

-- Administrações são registro de auditoria: campos com efeito no ledger não
-- podem mudar depois de criados. Correções = novo registro + ajuste manual.
create or replace function public.fn_administracao_imutavel()
returns trigger
language plpgsql
as $$
begin
  if new.status is distinct from old.status
     or new.qtd is distinct from old.qtd
     or new.medicamento_id is distinct from old.medicamento_id
     or new.horario_id is distinct from old.horario_id
     or new.cuidador_id is distinct from old.cuidador_id
     or new.registrado_em is distinct from old.registrado_em then
    raise exception
      'Administração é imutável (auditoria): corrija com novo registro e ajuste de estoque';
  end if;
  return new;
end;
$$;

create trigger trg_administracao_imutavel
  before update on public.administracoes
  for each row execute function public.fn_administracao_imutavel();
