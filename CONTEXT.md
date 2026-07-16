# CONTEXT — Nami Care

> Estado atual do projeto para continuidade entre sessões (Claude.ai e Claude Code).
> Última atualização: 2026-07-16

## Onde estamos

**Fase atual:** Fase 3 — Implementação via Claude Code (em andamento)

**Sessão #1 (2026-07-16) — CONCLUÍDA.** Ver `RELATORIO_SESSAO_01.md`. Entregas:
- [x] App React + Vite como PWA (manifest, service worker via vite-plugin-pwa),
      mobile-first, esqueleto rodando com checagem de conexão ao Supabase
- [x] Cliente Supabase via `.env.local` (`.env.example` versionado)
- [x] 5 migrations em `supabase/migrations/`, aplicadas no projeto Supabase
      `nami-care` (ref `uvkmvaheupziexlunnno`, sa-east-1 — separado da Nami Life):
      7 tabelas, trigger de baixa automática (DEC-008 aprovada), views
      `saldo_estoque` e `cobertura_estoque`, RLS em tudo, hardening dos advisors
- [x] Seed: `scripts/seed.js` + `scripts/seed-data.js` (4 cuidadores, 11 idosos,
      24 medicamentos sendo 3 SOS, 26 horários com colisões propositais,
      estoque inicial via `entrada_compra`) — **dados já aplicados no banco**
- [x] Critérios de aceite verificados: trigger (3 status + dupla baixa rejeitada +
      imutabilidade), saldo da view = soma do ledger, alerta de cobertura < 5 dias,
      RLS bloqueia anônimo (leitura e escrita), `npm run dev` e `npm run build` OK
- [x] DECISIONS.md: DEC-008 aprovada; novas DEC-016 (ledger sinalizado),
      DEC-017 (auditoria imutável), DEC-018 (hash de PIN provisório — REVISAR)

**Fases anteriores:**
- Fase 2 — Documentação de projeto (concluída em 2026-07-15): BRIEFING.md v1.2,
  DECISIONS.md, modelo de 7 tabelas, regras de negócio 100% definidas

**Próxima sessão:** **Sessão Claude Code #2** — login/assumir turno por PIN
(define o formato definitivo do hash — DEC-018) + telas de cadastro (idosos,
medicamentos, horários).

## Pendências operacionais

- [ ] **Guilherme:** preencher `SUPABASE_SERVICE_ROLE_KEY` em `.env.local`
      (Dashboard > Project Settings > API Keys) — necessária só para `npm run seed`
- [ ] **Guilherme:** revisar RELATORIO_SESSAO_01.md, salvar no Drive, commit + push
- [ ] Decidir na Sessão #2 o mecanismo de auth (usuário Supabase compartilhado da
      casa vs. outro esquema) — o RLS atual pressupõe papel `authenticated`
- [ ] Ícones do PWA estão em SVG; gerar PNG 192/512 antes do teste de instalação
      no celular da casa
- [ ] Termo LGPD com a casa de repouso ANTES de inserir dados reais

## Próximos passos (ordem sugerida)

1. **Sessão Claude Code #2:** autenticação por PIN + turnos + telas de cadastro
2. **Sessão Claude Code #3:** rodada de medicação + confirmações + dose avulsa SOS
3. **Sessão Claude Code #4:** relatórios (adesão, estoque, previsão de ruptura)
4. Deploy do frontend no Railway (DEC-007)
5. Piloto assistido: 1ª semana com acompanhamento próximo dos 4 cuidadores

## Convenções deste projeto

- Documentação segue o padrão Nami Life: BRIEFING.md (o quê e por quê),
  DECISIONS.md (decisões com racional), CONTEXT.md (estado e próximos passos)
- Bugs: numerar como BUG-001+; melhorias como MH-001+ (padrão Nami)
- Relatórios de sessão: salvar no Google Drive, mesma estrutura usada na Nami
- Idioma da documentação: português; código e nomes de tabelas/colunas: português
  sem acentos (ex.: `movimentacoes_estoque`)
- Linguagem única: JavaScript em todo o projeto — app e scripts (DEC-015)
- Migrations: arquivos em `supabase/migrations/` são a fonte de verdade e devem
  espelhar o histórico aplicado no projeto remoto

## Vínculo com a Nami Life

Projeto independente em código e banco, mas estrategicamente ligado: valida a
hipótese "casas de repouso como segmento B2B". Aprendizados de posologia, formas
farmacêuticas e estoque da Nami se aplicam diretamente. NÃO compartilhar banco de
dados nem repositório com a Nami Life. (Atenção: o servidor MCP "supabase"
configurado neste ambiente aponta para o banco da Nami Life — para o Nami Care,
usar o projeto `uvkmvaheupziexlunnno`.)
