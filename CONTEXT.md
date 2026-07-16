# CONTEXT — Nami Care

> Estado atual do projeto para continuidade entre sessões (Claude.ai e Claude Code).
> Última atualização: 2026-07-16 (fim da Sessão #2)

## Onde estamos

**Fase atual:** Fase 3 — Implementação via Claude Code (em andamento)

**Sessão #2 (2026-07-16) — CONCLUÍDA.** Ver `RELATORIO_SESSAO_02.md`. Entregas:
- [x] PIN definitivo (DEC-020, substitui DEC-018): bcrypt com salt por
      cuidador via pgcrypto; hash gerado e verificado só no banco;
      `pin_hash` inacessível aos papéis de API (grants por coluna)
- [x] Rate limit de PIN (DEC-021): 5 falhas / 15 min por cuidador, trilha em
      `tentativas_pin` (sem acesso de cliente)
- [x] Fluxo de turno (DEC-022): RPCs `abrir_turno` / `fechar_turno`; um turno
      aberto por vez; fechamento bloqueado com dose devida sem tratativa;
      administração exige turno aberto do cuidador (toda ação grava o
      cuidador do turno, nunca o usuário Supabase — DEC-019)
- [x] Ronda de medicação (DEC-023): `administracoes.prevista_em` ancora o
      slot; agenda do turno vem da RPC `doses_do_turno` (fonte única);
      tolerância de 30 min calculada no banco
- [x] Telas do PWA: LoginCasa (usuário único da casa), AssumirTurno
      (cuidador + teclado PIN), Ronda (atrasadas em destaque, tratativa em
      modal, tratadas com status, encerrar turno) — verificadas no navegador
- [x] Usuário Supabase da casa criado (`casa@namicare.app`; senha em
      `.env.local`, script reprodutível `npm run criar-usuario-casa`)
- [x] Seed atualizado: hash via RPC `fn_hash_pin`; banco resetado e limpo ao
      final da sessão (850 un. de estoque, 0 turnos/administrações)
- [x] 3 migrations novas (000600 pin_definitivo, 000700 turno_e_ronda,
      000800 hardening_sessao_02) — aplicadas no projeto e espelhadas em
      `supabase/migrations/`
- [x] DECISIONS.md: DEC-018 substituída; novas DEC-020 a DEC-023

**Sessão #1 (2026-07-16) — CONCLUÍDA.** Ver `RELATORIO_SESSAO_01.md`:
PWA + 7 tabelas + trigger de baixa (DEC-008) + views de estoque + RLS + seed.

**Fases anteriores:**
- Fase 2 — Documentação de projeto (concluída em 2026-07-15): BRIEFING.md v1.2,
  DECISIONS.md, modelo de 7 tabelas, regras de negócio 100% definidas

**Próxima sessão:** **Sessão Claude Code #3** — telas de cadastro (idosos,
medicamentos, horários — lembrando que cadastro de cuidador exigirá RPC
própria, pois o cliente não insere `pin_hash`), dose avulsa SOS e
movimentações manuais de estoque (compra, ajuste por contagem, perda).

## Pendências operacionais

- [ ] **Guilherme:** revisar RELATORIO_SESSAO_02.md, salvar no Drive, commit + push
- [ ] **Guilherme:** habilitar "Leaked Password Protection" no dashboard
      (Auth) — aviso dos security advisors
- [ ] **Guilherme:** testar o fluxo no celular da casa (login
      `casa@namicare.app` — senha em `.env.local` — e turno com PIN de teste)
- [ ] Ícones do PWA estão em SVG; gerar PNG 192/512 antes do teste de instalação
      no celular da casa
- [ ] Termo LGPD com a casa de repouso ANTES de inserir dados reais
- [ ] Bloqueio por inatividade (repedir PIN — implicação da DEC-002) ficou
      fora do MVP desta sessão; reavaliar após o piloto começar

## Próximos passos (ordem sugerida)

1. **Sessão Claude Code #3:** cadastros (idosos, medicamentos, horários,
   cuidadores via RPC) + dose avulsa SOS + movimentações manuais de estoque
2. **Sessão Claude Code #4:** relatórios (adesão, estoque, previsão de ruptura)
3. Deploy do frontend no Railway (DEC-007)
4. Piloto assistido: 1ª semana com acompanhamento próximo dos 4 cuidadores

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
- Regras de negócio no banco (triggers/RPCs), nunca duplicadas no cliente —
  a tela da ronda consome `doses_do_turno`, não recalcula slots

## Vínculo com a Nami Life

Projeto independente em código e banco, mas estrategicamente ligado: valida a
hipótese "casas de repouso como segmento B2B". Aprendizados de posologia, formas
farmacêuticas e estoque da Nami se aplicam diretamente. NÃO compartilhar banco de
dados nem repositório com a Nami Life. O `.mcp.json` deste repositório já aponta
o servidor MCP "supabase" para o projeto correto (`uvkmvaheupziexlunnno`).
