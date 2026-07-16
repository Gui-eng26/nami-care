-- =============================================================================
-- Migration: schema inicial — 7 tabelas do Nami Care (BRIEFING.md §5)
-- Convenções: nomes em português sem acentos; ids uuid; timestamps timestamptz.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- cuidadores
-- pin_hash: hash do PIN de login (formato definitivo do hash é da Sessão #2;
-- o seed usa SHA-256 hex provisório).
-- -----------------------------------------------------------------------------
create table public.cuidadores (
  id         uuid primary key default gen_random_uuid(),
  nome       text not null,
  pin_hash   text not null,
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- turnos
-- fim IS NULL = turno aberto (em andamento).
-- -----------------------------------------------------------------------------
create table public.turnos (
  id           uuid primary key default gen_random_uuid(),
  cuidador_id  uuid not null references public.cuidadores (id),
  inicio       timestamptz not null default now(),
  fim          timestamptz,
  constraint turnos_fim_apos_inicio check (fim is null or fim > inicio)
);

create index turnos_cuidador_id_idx on public.turnos (cuidador_id);

-- -----------------------------------------------------------------------------
-- idosos
-- Minimização LGPD (BRIEFING.md §9): sem CPF, convênio ou prontuário.
-- -----------------------------------------------------------------------------
create table public.idosos (
  id           uuid primary key default gen_random_uuid(),
  nome         text not null,
  nascimento   date,
  observacoes  text,
  criado_em    timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- medicamentos
-- tipo: 'continuo' (com horários fixos) | 'sos' (dose avulsa, DEC-014).
-- Soft delete via ativo (DEC-006).
-- -----------------------------------------------------------------------------
create table public.medicamentos (
  id                  uuid primary key default gen_random_uuid(),
  idoso_id            uuid not null references public.idosos (id),
  nome                text not null,
  dosagem             text,
  forma_farmaceutica  text,
  posologia           text,
  tipo                text not null check (tipo in ('continuo', 'sos')),
  ativo               boolean not null default true,
  criado_em           timestamptz not null default now()
);

create index medicamentos_idoso_id_idx on public.medicamentos (idoso_id);

-- -----------------------------------------------------------------------------
-- horarios
-- qtd_dose em múltiplos de 0,5 (DEC-013). Soft delete via ativo (DEC-006).
-- unique (id, medicamento_id) permite FK composta em administracoes garantindo
-- que o horário informado pertence ao medicamento informado.
-- -----------------------------------------------------------------------------
create table public.horarios (
  id              uuid primary key default gen_random_uuid(),
  medicamento_id  uuid not null references public.medicamentos (id),
  hora            time not null,
  qtd_dose        numeric(6,2) not null,
  ativo           boolean not null default true,
  criado_em       timestamptz not null default now(),
  constraint horarios_qtd_dose_valida
    check (qtd_dose > 0 and mod(qtd_dose * 2, 1) = 0),
  constraint horarios_id_medicamento_unico unique (id, medicamento_id)
);

create index horarios_medicamento_id_idx on public.horarios (medicamento_id);
create index horarios_hora_ativo_idx on public.horarios (hora) where ativo;

-- Medicamentos SOS não têm horários (DEC-014).
create or replace function public.fn_horario_exige_continuo()
returns trigger
language plpgsql
as $$
begin
  if (select tipo from public.medicamentos where id = new.medicamento_id) <> 'continuo' then
    raise exception 'Medicamento SOS não pode ter horários fixos (DEC-014)';
  end if;
  return new;
end;
$$;

create trigger trg_horario_exige_continuo
  before insert or update of medicamento_id on public.horarios
  for each row execute function public.fn_horario_exige_continuo();

-- Contrapartida: medicamento não pode virar SOS enquanto tiver horários ativos.
create or replace function public.fn_medicamento_sos_sem_horarios()
returns trigger
language plpgsql
as $$
begin
  if new.tipo = 'sos' and old.tipo = 'continuo'
     and exists (select 1 from public.horarios h
                 where h.medicamento_id = new.id and h.ativo) then
    raise exception
      'Medicamento com horários ativos não pode virar SOS: desative os horários antes (DEC-014)';
  end if;
  return new;
end;
$$;

create trigger trg_medicamento_sos_sem_horarios
  before update of tipo on public.medicamentos
  for each row execute function public.fn_medicamento_sos_sem_horarios();

-- -----------------------------------------------------------------------------
-- administracoes
-- horario_id IS NULL = dose avulsa (DEC-014).
-- qtd em múltiplos de 0,5 (DEC-013).
-- FK composta (horario_id, medicamento_id): o horário deve pertencer ao
-- medicamento da administração.
-- -----------------------------------------------------------------------------
create table public.administracoes (
  id              uuid primary key default gen_random_uuid(),
  medicamento_id  uuid not null references public.medicamentos (id),
  horario_id      uuid,
  cuidador_id     uuid not null references public.cuidadores (id),
  qtd             numeric(6,2) not null,
  status          text not null check (status in
                    ('tomado_no_horario', 'tomado_atrasado', 'nao_tomado', 'recusado')),
  observacao      text,
  registrado_em   timestamptz not null default now(),
  constraint administracoes_qtd_valida
    check (qtd > 0 and mod(qtd * 2, 1) = 0),
  constraint administracoes_horario_do_medicamento
    foreign key (horario_id, medicamento_id)
    references public.horarios (id, medicamento_id)
);

create index administracoes_medicamento_id_idx on public.administracoes (medicamento_id);
create index administracoes_cuidador_id_idx on public.administracoes (cuidador_id);
create index administracoes_registrado_em_idx on public.administracoes (registrado_em);

-- -----------------------------------------------------------------------------
-- movimentacoes_estoque — livro-razão (DEC-004)
-- Convenção de sinal: entradas > 0, saídas < 0; saldo = SUM(quantidade).
-- administracao_id UNIQUE impede dupla baixa da mesma administração (DEC-008);
-- NULL = movimentação manual (compra, ajuste, perda avulsa).
-- -----------------------------------------------------------------------------
create table public.movimentacoes_estoque (
  id                uuid primary key default gen_random_uuid(),
  medicamento_id    uuid not null references public.medicamentos (id),
  cuidador_id       uuid references public.cuidadores (id),
  administracao_id  uuid unique references public.administracoes (id),
  tipo              text not null check (tipo in
                      ('entrada_compra', 'saida_administracao', 'ajuste_contagem', 'perda')),
  quantidade        numeric(8,2) not null,
  motivo            text,
  criado_em         timestamptz not null default now(),
  constraint movimentacoes_quantidade_meio_em_meio
    check (mod(quantidade * 2, 1) = 0),
  constraint movimentacoes_sinal_por_tipo check (
    case tipo
      when 'entrada_compra'       then quantidade > 0
      when 'saida_administracao'  then quantidade < 0
      when 'perda'                then quantidade < 0
      when 'ajuste_contagem'      then quantidade <> 0
    end
  ),
  constraint movimentacoes_saida_exige_administracao check (
    (tipo = 'saida_administracao') = (administracao_id is not null)
    or (tipo = 'perda' and administracao_id is not null)
  )
);

create index movimentacoes_estoque_medicamento_id_idx
  on public.movimentacoes_estoque (medicamento_id);
create index movimentacoes_estoque_criado_em_idx
  on public.movimentacoes_estoque (criado_em);
