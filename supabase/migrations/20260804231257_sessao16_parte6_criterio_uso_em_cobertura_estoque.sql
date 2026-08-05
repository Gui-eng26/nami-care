-- SESSÃO 16 — Parte 6: expõe criterio_uso em cobertura_estoque (aditivo)
-- para a tela de dose SOS mostrar "quando administrar" em evidência.
--
-- CREATE OR REPLACE VIEW só aceita coluna nova no FIM da lista (senão o
-- Postgres tenta "renomear" as colunas seguintes e recusa) — por isso
-- criterio_uso entra depois de volume_frasco_ml, não perto de estoque_minimo.

begin;

create or replace view public.cobertura_estoque as
with doses_dia as (
  select h.medicamento_id,
    sum(h.qtd_dose * (
      case h.recorrencia_tipo
        when 'diario' then 1
        when 'dias_semana' then cardinality(h.dias_semana) / 7.0
        when 'intervalo' then 1.0 / h.intervalo_dias
      end
    )) as doses_por_dia
  from public.horarios h
  where h.ativo
  group by h.medicamento_id
)
select s.medicamento_id,
  s.idoso_id,
  i.nome as nome_idoso,
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
    when (s.tipo = 'continuo' and d.doses_por_dia > 0) then round(s.saldo / d.doses_por_dia, 1)
    else null
  end as cobertura_dias,
  case
    when not (s.ativo and i.ativo) then false
    when s.tipo = 'continuo' then coalesce(
      d.doses_por_dia > 0 and (
        (s.saldo / d.doses_por_dia) < public.fn_limiar_cobertura_dias()
        or s.saldo <= public.fn_limiar_doses_restantes()
      ),
      false
    )
    else coalesce(s.saldo < m.estoque_minimo, false)
  end as alerta_reposicao,
  case
    when (
      s.ativo and i.ativo and s.tipo = 'continuo' and d.doses_por_dia > 0 and (
        (s.saldo / d.doses_por_dia) < public.fn_limiar_cobertura_dias()
        or s.saldo <= public.fn_limiar_doses_restantes()
      )
    ) then greatest(ceil((d.doses_por_dia * 30) - s.saldo), 0)
    else null
  end as sugestao_compra,
  i.eh_sentinela as idoso_da_casa,
  s.unidade_dose,
  s.catalogo_gotas_por_ml,
  s.volume_frasco_ml,
  m.criterio_uso
from public.saldo_estoque s
join public.medicamentos m on m.id = s.medicamento_id
join public.idosos i on i.id = s.idoso_id
left join doses_dia d on d.medicamento_id = s.medicamento_id;

commit;
