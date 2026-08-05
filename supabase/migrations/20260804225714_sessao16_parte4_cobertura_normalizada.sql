-- SESSÃO 16 — Parte 4 (DEC-056): cobertura normalizada e alerta por OU.
--
-- Problema 1: cobertura_estoque somava qtd_dose de todo horário ativo
-- assumindo que todo horário dispara todo dia — verdade até a Parte 3, falsa
-- agora que existe recorrência. Cada horário passa a contribuir
-- qtd_dose × frequência_diária_própria (diario=1, dias_semana=cardinality/7,
-- intervalo=1/intervalo_dias).
--
-- Problema 2 (independente): o alerta de reposição só olhava cobertura_dias
-- < 5. Para um medicamento semanal isso avisa quando resta menos de 1 dia —
-- tarde demais. Alerta em OU: cobertura_dias < LIMIAR_DIAS OU
-- doses_restantes <= LIMIAR_DOSES (doses_restantes = saldo, na própria
-- unidade de dose do medicamento — vale exatamente "quantas vezes ainda dá
-- pra administrar" quando cada evento consome 1 unidade, o caso comum). O
-- limiar de doses é inclusive (<=), não estrito: o caso de validação da
-- sessão é semanal com saldo=2 acende e saldo=3 não, com LIMIAR_DOSES=2 —
-- só fecha com <=. Para os medicamentos diários (a esmagadora maioria) a
-- regra de dias acende primeiro — sem regressão.
--
-- Os dois limiares são funções (constantes nomeadas, não números soltos no
-- meio da view) para o product owner calibrar num só lugar.

begin;

create or replace function public.fn_limiar_cobertura_dias()
returns numeric
language sql
immutable
as $$ select 5::numeric $$;

create or replace function public.fn_limiar_doses_restantes()
returns numeric
language sql
immutable
as $$ select 2::numeric $$;

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
  s.volume_frasco_ml
from public.saldo_estoque s
join public.medicamentos m on m.id = s.medicamento_id
join public.idosos i on i.id = s.idoso_id
left join doses_dia d on d.medicamento_id = s.medicamento_id;

commit;
