-- =============================================================================
-- Migration: visão de estoque com alerta de reposição por natureza (DEC-027)
--
-- Substitui a cobertura por média móvel de 14 dias (Sessão #1) pelos dois
-- métodos da DEC-027:
--   continuo — cobertura determinística pela prescrição ativa:
--              cobertura_dias = saldo ÷ SUM(qtd_dose dos horários ativos).
--              Alerta quando < 5 dias (DEC-012). A posologia da Sessão #3 é
--              estritamente diária (horarios.hora time), então a soma dos
--              horários ativos JÁ é a base diária — sem normalização semanal.
--   sos      — estoque mínimo de segurança: alerta quando
--              saldo < medicamentos.estoque_minimo (campo do cadastro).
--
-- saldo_estoque (Sessão #1) permanece a fonte única de saldo; esta view só
-- acrescenta a leitura de cobertura/alerta por cima (nunca recalcula o saldo).
--
-- sugestao_compra (contínuos em alerta): quanto comprar para voltar a 30 dias
-- de cobertura (DEC-028) — compra mensal, caixas de 30 na farmácia local.
--
-- Alerta exige medicamento E residente ativos: estoque de item desativado
-- continua visível (o físico existe — exibido com selo), mas não pede compra.
-- Contínuo ativo sem horário ativo fica com cobertura NULL (fora das rondas,
-- consumo planejado zero) e sem alerta.
-- =============================================================================

drop view public.cobertura_estoque;

create view public.cobertura_estoque
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
  end as sugestao_compra
from public.saldo_estoque s
join public.medicamentos m on m.id = s.medicamento_id
join public.idosos i on i.id = s.idoso_id
left join doses_dia d on d.medicamento_id = s.medicamento_id;
