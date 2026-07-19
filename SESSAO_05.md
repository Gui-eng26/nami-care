# SESSAO_05 — Relatório de adesão

> Roteiro da quinta sessão de implementação via Claude Code.
> Modelo: Claude Fable 5 (sessão longa e autônoma).
> Criado em: 2026-07-18 | Executada em: 2026-07-18

---

## Pré-requisitos (verificados no início da sessão)

- [x] Sessão #4 concluída e commitada (`b64de56`)
- [x] Banco no estado limpo do seed (4 cuidadoras, 11 residentes,
      24 medicamentos, 850 un. de estoque, 0 administrações; havia 2 turnos
      fechados de teste manual pós-Sessão #4 — sem efeito, apagados no reset)
- [x] 14 migrations remotas espelham `supabase/migrations/`
- [x] MCP do Supabase apontando para o projeto `nami-care`
      (ref `uvkmvaheupziexlunnno`)

## Contexto

O ROADMAP previa deploy nesta sessão. **Reordenação deliberada** (não é corte
de escopo): deploy e go-live foram movidos para a Sessão #6; a #5 constrói o
relatório de adesão (BRIEFING §6 item 10) — o último item de produto do MVP.

## Escopo

### 0. Verificação de premissas ANTES de qualquer agregação

- [x] Valores reais de `administracoes.status` confirmados no schema:
      `tomado_no_horario | tomado_atrasado | nao_tomado | recusado`.
      A classificação "no horário × atrasada" sai do **status gravado**,
      nunca de aritmética de timestamps — o registro tardio grava
      `registrado_em = prevista_em` (DEC-023), o que tornaria a comparação
      de timestamps incorreta.
- [x] Dose SOS = `horario_id IS NULL` (constraint garante `prevista_em`
      também nulo — DEC-014/023). Único caminho.
- [x] Fronteira de dia no fuso da casa via `fn_fuso_casa()` =
      `America/Sao_Paulo` (DEC-023), nunca UTC.

### 1. Modelo de cálculo (DEC-030)

- [x] Denominador = doses já **materializadas** (linhas de `administracoes`
      com `prevista_em` no período); grade histórica de `horarios` nunca é
      reconstruída. Sustentado pelo fechamento obrigatório de turno
      (DEC-010/022); prescrição versionada (DEC-026) absorvida naturalmente.
- [x] Quatro categorias mutuamente exclusivas em % do total; "recusada" e
      "não tomada" nunca somadas.
- [x] SOS fora dos percentuais — contagem absoluta.
- [x] Dia corrente: futura fora do denominador; vencida sem tratativa =
      **pendente**, categoria à parte, vinda de `doses_do_turno` (reuso da
      fonte única de slots — nenhuma segunda implementação).

### 2. Visões

- [x] Macro (casa) = micro (residente) sem o filtro — mesma RPC, mesmo
      caminho de cálculo (`p_idoso_id` opcional).
- [x] Residente desativado (DEC-032): histórico conta, aparece na macro,
      selo "— inativo" na lista da micro (mesmo tratamento da DEC-029).

### 3. Seletor de período

- [x] Calendário livre (De/Até) + atalhos Hoje, Ontem, Últimos 7 dias,
      Este mês — atalhos apenas pré-calculam as datas, mesmo caminho de
      consulta.

### 4. Acesso (DEC-031)

- [x] Aba "Adesão" junto de Ronda | Estoque, sem PIN adicional — operação,
      não gestão. Consequência registrada: indicadores visíveis a toda a
      equipe.

### 5. Dados de teste

- [x] `npm run seed -- --com-historico`: ~7 dias de histórico pelas RPCs
      (turnos abertos/fechados por `abrir_turno`/`fechar_turno`), 4 status,
      SOS em vários dias, mudança de posologia versionada no meio do
      período, hoje parcial com turno aberto. `--reset` continua gerando o
      banco limpo.

## Restrições

- Stack: JavaScript apenas (Vite + PWA), Supabase, Railway.
- Toda mudança de schema via migration; nunca SQL avulso.
- Regra de negócio no banco; percentuais calculados na RPC, nunca no JS.
- Ledger e `administracoes` intactos: a sessão só lê o histórico.
- Ronda/turno/gestão/estoque intocados além da aba nova; tema Sereníssima.
- Rótulos legíveis, sem jargão (padrão DEC-027).

## Fora do escopo (registrado, não construído)

- Deploy no Railway, URLs do Auth, ícones PNG, bootstrap da Thais: Sessão #6.
- Carga de dados reais (depende de LGPD).
- Motivo de recusa agregado por medicamento — ideia futura registrada.
- Extrato de movimentações de estoque por período ("acuracidade de
  estoque") — candidata a sessão própria no ROADMAP.
- Desempenho por cuidador — não construir (muda a natureza da ferramenta).

## Critérios de aceite da sessão

- [x] "Hoje": quatro percentuais + SOS coerentes com as doses vencidas
      (futuras fora; pendentes à parte) — conferido tela × SQL
- [x] Intervalo atravessando mudança de posologia soma corretamente
      (Sinvastatina: 1/dia → 2/dia; micro Alzira = 24 doses em 7 dias)
- [x] Visão por residente = mesmos indicadores filtrados
- [x] Números da tela = contagem manual das linhas de `administracoes`
      (bateria SQL de 7 blocos + conferências pontuais)

## Encerramento

- [x] Smoke test da migration em transação com rollback antes do apply
- [x] Bateria SQL: classificação, SOS, corte do dia corrente, fuso,
      versionamento, residente desativado, permissões
- [x] `npm run build` OK; security advisors sem aviso novo
- [x] Reset final do seed (banco limpo)
- [x] RELATORIO_SESSAO_05.md; DECISIONS (DEC-030/031/032); CONTEXT e
      ROADMAP atualizados; pendência do Leaked Password Protection encerrada
