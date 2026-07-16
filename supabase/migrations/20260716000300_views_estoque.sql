-- =============================================================================
-- Migration: views de saldo e cobertura de estoque (DEC-004, DEC-012)
--
-- security_invoker = true: as views respeitam o RLS das tabelas subjacentes
-- (sem isso, rodariam com os privilégios do owner e vazariam dados ao anon).
-- =============================================================================

-- Saldo por medicamento = SUM(movimentações). Nunca armazenado (DEC-004).
create view public.saldo_estoque
  with (security_invoker = true)
as
select
  m.id   as medicamento_id,
  m.idoso_id,
  m.nome,
  m.dosagem,
  m.forma_farmaceutica,
  m.tipo,
  m.ativo,
  coalesce(sum(me.quantidade), 0) as saldo
from public.medicamentos m
left join public.movimentacoes_estoque me on me.medicamento_id = m.id
group by m.id;

-- Cobertura = saldo / consumo médio diário dos últimos 14 dias.
-- Consumo considera tudo que sai do estoque por uso ou perda
-- (saida_administracao + perda); alerta quando cobertura < 5 dias (DEC-012).
-- cobertura_dias IS NULL = sem consumo no período (sem base para previsão).
create view public.cobertura_estoque
  with (security_invoker = true)
as
with consumo as (
  select
    medicamento_id,
    sum(-quantidade) / 14.0 as consumo_medio_diario
  from public.movimentacoes_estoque
  where tipo in ('saida_administracao', 'perda')
    and criado_em >= now() - interval '14 days'
  group by medicamento_id
)
select
  s.medicamento_id,
  s.idoso_id,
  i.nome as nome_idoso,
  s.nome,
  s.dosagem,
  s.tipo,
  s.ativo,
  s.saldo,
  round(coalesce(c.consumo_medio_diario, 0), 2) as consumo_medio_diario,
  case
    when coalesce(c.consumo_medio_diario, 0) > 0
    then round(s.saldo / c.consumo_medio_diario, 1)
  end as cobertura_dias,
  coalesce(c.consumo_medio_diario, 0) > 0
    and s.saldo / c.consumo_medio_diario < 5 as alerta_reposicao
from public.saldo_estoque s
join public.idosos i on i.id = s.idoso_id
left join consumo c on c.medicamento_id = s.medicamento_id;
