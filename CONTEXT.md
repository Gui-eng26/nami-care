# CONTEXT — Nami Care

> Estado atual do projeto para continuidade entre sessões (Claude.ai e Claude Code).
> Última atualização: 2026-07-16 (fim da Sessão #3)

## Onde estamos

**Fase atual:** Fase 3 — Implementação via Claude Code (em andamento)

**Sessão #3 (2026-07-16) — CONCLUÍDA.** Ver `RELATORIO_SESSAO_03.md`. Entregas:
- [x] Acesso à gestão (DEC-024, substitui parcialmente DEC-011): flag
      `eh_admin` + PIN de administradora validado NO BANCO em cada RPC de
      gestão (`fn_autorizar_admin`; rate limit da DEC-021; trilha em
      `tentativas_pin`); porta de entrada `autorizar_gestao`
- [x] Gestão de cuidadoras por RPC (único caminho — escrita direta
      revogada): `criar_cuidador` (hash só no banco), `atualizar_cuidador`,
      `definir_ativo_cuidador` (nunca exclusão); guardas de última admin e
      turno aberto
- [x] Troca de PIN (DEC-025): `trocar_pin` (exige PIN atual) e
      `redefinir_pin` (por admin); `definir_pin` removida (BUG-001 — trocava
      PIN sem verificação)
- [x] Residentes: `idosos.ativo` + RPCs criar/atualizar/definir_ativo;
      `doses_do_turno` ignora residente desativado
- [x] Prescrições versionadas (DEC-026): triggers de imutabilidade clínica
      após primeira administração; `atualizar_horario` desativa + cria
      versão nova quando há histórico; índice único de horário ativo
- [x] Telas de gestão (Gestao, GestaoCuidadoras, GestaoResidentes com
      navegação residente → medicamentos → horários) + "Trocar meu PIN" no
      AssumirTurno
- [x] Identidade Sereníssima: dourado #B08D4A / creme #FAF6EE / texto
      #3D3428 nas variáveis globais; "Sereníssima" no cabeçalho, nome
      completo no login e no manifest (short_name "Sereníssima"); cores
      funcionais intactas
- [x] 4 migrations novas (000900–001200) aplicadas e espelhadas; 16 testes
      SQL + testes de permissão + ciclo completo no navegador; seed com
      `admin: true` na Ana; banco resetado limpo ao final

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

**Próxima sessão:** **Sessão Claude Code #4** — estoque e SOS (a dor nº 1):
entradas no ledger (compra, ajuste por contagem, perda manuais), visão de
saldo/cobertura com alerta de reposição (< 5 dias) e fluxo de dose avulsa
SOS/PRN.

## Pendências operacionais

- [ ] **Guilherme:** revisar RELATORIO_SESSAO_03.md, salvar no Drive, commit + push
- [ ] **Guilherme:** habilitar "Leaked Password Protection" no dashboard
      (Auth) — aviso dos security advisors (pendente desde a Sessão #2)
- [ ] **Guilherme:** testar o fluxo no celular da casa (login
      `casa@namicare.app` — senha em `.env.local` — e turno com PIN de teste;
      gestão: Ana Souza, PIN 1111)
- [ ] Ícones do PWA estão em SVG; gerar PNG 192/512 antes do teste de instalação
      no celular da casa (o logo real entra na Sessão #5)
- [ ] Termo LGPD com a casa de repouso ANTES de inserir dados reais
- [ ] Bloqueio por inatividade (repedir PIN — implicação da DEC-002) ficou
      fora do MVP; reavaliar após o piloto começar
- [ ] Bootstrap da administradora real (Thais) por seed/script no cadastro
      dos dados reais — a gestão exige uma admin já existente (Sessão #5)

## Próximos passos (ordem sugerida)

1. **Sessão Claude Code #4:** estoque (entradas, ajuste, perda, saldo,
   alerta de cobertura) + dose avulsa SOS
2. **Sessão Claude Code #5:** deploy no Railway, PWA no celular da casa,
   cadastro dos dados reais
3. Piloto assistido: 1ª semana com acompanhamento próximo das 4 cuidadoras

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
