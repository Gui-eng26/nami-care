-- Sessão #15, Parte 2 (DEC-052): alargar precisão numeric para acomodar líquidos em gotas
-- Alargamento de numeric é lossless. Recria trigger column-list e views que dependem
-- das colunas alteradas (bloqueiam ALTER COLUMN TYPE em Postgres).

drop trigger trg_horario_imutavel_apos_uso on public.horarios;
drop view public.cobertura_estoque;
drop view public.saldo_estoque;
drop view public.lotes_estoque_vivo;

alter table public.horarios alter column qtd_dose type numeric(10,2);
alter table public.medicamentos alter column estoque_minimo type numeric(10,2);
alter table public.administracoes alter column qtd type numeric(10,2);
alter table public.lotes_estoque alter column quantidade_inicial type numeric(10,2);
alter table public.lotes_estoque alter column saldo_atual type numeric(10,2);
alter table public.movimentacao_lote alter column quantidade type numeric(10,2);
alter table public.movimentacoes_estoque alter column quantidade type numeric(10,2);

create trigger trg_horario_imutavel_apos_uso
  before update of hora, qtd_dose on public.horarios
  for each row execute function public.fn_horario_imutavel_apos_uso();

create view public.lotes_estoque_vivo as
 SELECT id, medicamento_id, lote, validade, saldo_atual, quantidade_inicial, data_entrada, origem, criado_em
   FROM lotes_estoque l
  WHERE saldo_atual > 0::numeric;

create view public.saldo_estoque as
 SELECT m.id AS medicamento_id, m.idoso_id, m.nome, m.dosagem, m.forma_farmaceutica, m.tipo, m.ativo,
    COALESCE(sum(l.saldo_atual), 0::numeric) AS saldo
   FROM medicamentos m LEFT JOIN lotes_estoque l ON l.medicamento_id = m.id
  GROUP BY m.id;

create view public.cobertura_estoque as
 WITH doses_dia AS (
         SELECT h.medicamento_id, sum(h.qtd_dose) AS doses_por_dia
           FROM horarios h WHERE h.ativo GROUP BY h.medicamento_id
        )
 SELECT s.medicamento_id, s.idoso_id, i.nome AS nome_idoso, i.ativo AS idoso_ativo, s.nome, s.dosagem,
    s.forma_farmaceutica, s.tipo, s.ativo, s.saldo, m.estoque_minimo, d.doses_por_dia,
        CASE WHEN s.tipo = 'continuo'::text AND d.doses_por_dia > 0::numeric THEN round(s.saldo / d.doses_por_dia, 1) ELSE NULL::numeric END AS cobertura_dias,
        CASE WHEN NOT (s.ativo AND i.ativo) THEN false
             WHEN s.tipo = 'continuo'::text THEN COALESCE(d.doses_por_dia > 0::numeric AND (s.saldo / d.doses_por_dia) < 5::numeric, false)
             ELSE COALESCE(s.saldo < m.estoque_minimo, false) END AS alerta_reposicao,
        CASE WHEN s.ativo AND i.ativo AND s.tipo = 'continuo'::text AND d.doses_por_dia > 0::numeric AND (s.saldo / d.doses_por_dia) < 5::numeric THEN GREATEST(ceil(d.doses_por_dia * 30::numeric - s.saldo), 0::numeric) ELSE NULL::numeric END AS sugestao_compra,
    i.eh_sentinela AS idoso_da_casa
   FROM saldo_estoque s
     JOIN medicamentos m ON m.id = s.medicamento_id
     JOIN idosos i ON i.id = s.idoso_id
     LEFT JOIN doses_dia d ON d.medicamento_id = s.medicamento_id;
