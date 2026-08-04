-- Sessão #15, Parte 1 (DEC-051): unidade de dose estruturada no catálogo
-- Colunas nascem nullable -> backfill -> validação -> NOT NULL (base populada, ver Parte 0)

alter table public.catalogo_medicamentos
  add column unidade_dose text,
  add column gotas_por_ml numeric(6,2),
  add column volume_frasco_ml numeric(6,2);

-- Backfill determinístico (auditoria da Parte 0: só existem 'Comprimido' e 'Cápsula' hoje).
-- Fallback genérico como rede de segurança; validado e abortado logo abaixo se disparar.
update public.catalogo_medicamentos
set unidade_dose = case forma_farmaceutica
  when 'Comprimido' then 'comprimido'
  when 'Cápsula' then 'capsula'
  else 'unidade'
end;

do $$
declare
  qtd_inesperada int;
begin
  select count(*) into qtd_inesperada
  from public.catalogo_medicamentos
  where forma_farmaceutica not in ('Comprimido', 'Cápsula');

  if qtd_inesperada > 0 then
    raise exception
      'Backfill de unidade_dose encontrou % linha(s) com forma_farmaceutica fora do esperado (Comprimido/Cápsula) — abortando, requer decisão manual (DEC-051)',
      qtd_inesperada;
  end if;
end $$;

alter table public.catalogo_medicamentos
  alter column unidade_dose set not null;

alter table public.catalogo_medicamentos
  add constraint catalogo_medicamentos_unidade_dose_check
    check (unidade_dose in (
      'comprimido', 'capsula', 'dragea', 'gota', 'ml',
      'sache', 'supositorio', 'adesivo', 'unidade'
    ));

alter table public.catalogo_medicamentos
  add constraint catalogo_medicamentos_gotas_por_ml_check
    check (
      (unidade_dose = 'gota' and gotas_por_ml is not null and gotas_por_ml > 0)
      or (unidade_dose <> 'gota' and gotas_por_ml is null)
    );

alter table public.catalogo_medicamentos
  add constraint catalogo_medicamentos_volume_frasco_ml_check
    check (
      (unidade_dose in ('gota', 'ml') and volume_frasco_ml is not null and volume_frasco_ml > 0)
      or (unidade_dose not in ('gota', 'ml') and volume_frasco_ml is null)
    );

-- Imutabilidade clínica (estende DEC-026): trocar a unidade de um catálogo já em uso
-- reinterpretaria retroativamente administracoes.qtd do histórico.
create or replace function public.fn_catalogo_unidade_dose_imutavel()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  if new.unidade_dose is distinct from old.unidade_dose
     and exists (
       select 1
       from public.medicamentos m
       join public.administracoes a on a.medicamento_id = m.id
       where m.catalogo_id = old.id
     ) then
    raise exception
      'Catálogo com medicamento em uso tem unidade_dose imutável (DEC-026/051): trocar reinterpretaria o histórico de administrações — cadastre um novo item de catálogo';
  end if;
  return new;
end;
$function$;

create trigger trg_catalogo_unidade_dose_imutavel
  before update of unidade_dose on public.catalogo_medicamentos
  for each row execute function public.fn_catalogo_unidade_dose_imutavel();
