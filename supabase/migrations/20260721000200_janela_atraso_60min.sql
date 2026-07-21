-- =============================================================================
-- Sessão #10 — Parte 2: janela de "atrasada" de 30 para 60 minutos (DEC-039)
--
-- A DEC-010 fixara em 30 min a tolerância entre o horário previsto e a dose
-- passar a "atrasada" (destaque vermelho na ronda). No uso real da casa 30 min
-- é curto para o ritmo do plantão — a dose salta como atrasada cedo demais.
-- A DEC-039 revisa esse número para 60 min. Nada mais muda:
--   * `fechar_turno` continua exigindo tratativa de TODA dose devida, inclusive
--     a que ainda está dentro da tolerância (DEC-010/DEC-022 intactas);
--   * a janela de 15 min da "próxima ronda" (c_janela) é outra coisa e não muda;
--   * a fila de pendências entre turnos (DEC-033) não usa tolerância nenhuma.
--
-- A expressão da tolerância vive num lugar só — `doses_do_turno`, fonte única
-- da lógica de slots (DEC-023). Ela foi definida na 20260716000700 e redefinida
-- na 20260716001000 (que acrescentou o filtro de residente ativo); esta
-- migration substitui a versão vigente, de modo que os dois pontos históricos
-- do schema convergem para 60 min por construção — não existe um terceiro.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- doses_do_turno — agenda do turno: todos os slots (horário ativo × dia) de
-- medicamento contínuo ativo de residente ativo cujo instante previsto caiu
-- dentro do turno, com a situação de cada um:
--   tratada  = já existe administração para o slot
--   pendente = devida, sem tratativa, dentro da tolerância de 60 min (DEC-039,
--              que revisa os 30 min originais da DEC-010)
--   atrasada = devida, sem tratativa, tolerância estourada
-- SECURITY INVOKER: roda com o RLS do chamador.
-- -----------------------------------------------------------------------------
create or replace function public.doses_do_turno(p_turno_id uuid)
returns table (
  horario_id         uuid,
  medicamento_id     uuid,
  idoso_id           uuid,
  nome_idoso         text,
  nome_medicamento   text,
  dosagem            text,
  forma_farmaceutica text,
  qtd_dose           numeric,
  prevista_em        timestamptz,
  situacao           text,
  administracao_id   uuid,
  status_tratativa   text,
  observacao         text
)
language sql
stable
security invoker
set search_path = ''
as $$
  with turno as (
    select t.inicio, least(coalesce(t.fim, now()), now()) as fim_efetivo
    from public.turnos t
    where t.id = p_turno_id
  ),
  dias as (
    select generate_series(
             (turno.inicio at time zone public.fn_fuso_casa())::date,
             (turno.fim_efetivo at time zone public.fn_fuso_casa())::date,
             interval '1 day'
           )::date as dia
    from turno
  ),
  slots as (
    select h.id as horario_id,
           h.medicamento_id,
           h.qtd_dose,
           ((d.dia + h.hora) at time zone public.fn_fuso_casa()) as prevista_em
    from public.horarios h
    join public.medicamentos m on m.id = h.medicamento_id
    join public.idosos i on i.id = m.idoso_id
    cross join dias d
    where h.ativo
      and m.ativo
      and i.ativo
      and m.tipo = 'continuo'
  )
  select s.horario_id,
         s.medicamento_id,
         m.idoso_id,
         i.nome,
         m.nome,
         m.dosagem,
         m.forma_farmaceutica,
         s.qtd_dose,
         s.prevista_em,
         case
           when a.id is not null then 'tratada'
           when now() > s.prevista_em + interval '60 minutes' then 'atrasada'
           else 'pendente'
         end,
         a.id,
         a.status,
         a.observacao
  from slots s
  join turno on s.prevista_em >= turno.inicio
            and s.prevista_em <= turno.fim_efetivo
  join public.medicamentos m on m.id = s.medicamento_id
  join public.idosos i on i.id = m.idoso_id
  left join public.administracoes a
    on a.horario_id = s.horario_id
   and a.prevista_em = s.prevista_em
  order by s.prevista_em, i.nome, m.nome;
$$;

revoke execute on function public.doses_do_turno(uuid) from public, anon;
