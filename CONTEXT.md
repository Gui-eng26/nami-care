# CONTEXT — Nami Care

> Estado atual do projeto para continuidade entre sessões (Claude.ai e Claude Code).
> Última atualização: 2026-07-18 (fim da Sessão #5)

## Onde estamos

**Fase atual:** Fase 3 — Implementação via Claude Code (MVP de produto
COMPLETO; falta deploy/go-live)

**Sessão #5 (2026-07-18) — CONCLUÍDA.** Ver `RELATORIO_SESSAO_05.md`. Entregas:
- [x] Relatório de adesão (BRIEFING §6 item 10 — último item de produto do
      MVP): RPC `relatorio_adesao` (DEC-030 — denominador = doses
      materializadas, classificação pelo status gravado, pendentes à parte
      via `doses_do_turno`, SOS como contagem absoluta, percentuais no
      banco, fuso da casa)
- [x] Aba "Adesão" junto de Ronda | Estoque, sem PIN de gestão (DEC-031);
      visão macro (casa) = micro (residente) sem filtro — mesma RPC;
      atalhos Hoje/Ontem/7 dias/Este mês + calendário livre; residente
      desativado com histórico contando e selo na lista (DEC-032)
- [x] `npm run seed -- --com-historico`: ~7 dias de histórico reprodutível
      pelas RPCs (turnos reais, 4 status, SOS, mudança de posologia
      versionada no meio do período, hoje parcial com turno aberto) — para
      o teste funcional do Guilherme antes do go-live
- [x] 1 migration nova (20260718000100) aplicada e espelhada; smoke test
      com rollback + bateria SQL de 7 blocos; conferência tela × SQL;
      `npm run build` OK; advisors sem aviso novo; banco resetado limpo
- [x] Pendência da Sessão #2 encerrada: Leaked Password Protection é
      indisponível no plano Free; mitigado com senha aleatória forte da
      casa + Minimum password length = 12 (documentado no relatório)
- [x] Deploy movido para a Sessão #6 (reordenação deliberada do ROADMAP)

**Sessão #4 (2026-07-17) — CONCLUÍDA.** Ver `RELATORIO_SESSAO_04.md`. Entregas:
- [x] Ledger completo (DEC-004 fechada de ponta a ponta): RPCs
      `registrar_entrada_estoque`, `registrar_ajuste_estoque` (contagem
      física → diferença calculada e gravada no banco, nunca sobrescrita)
      e `registrar_perda_estoque` (motivo obrigatório); todas gravam o
      cuidador do turno aberto; INSERT direto em `movimentacoes_estoque`
      revogado (trigger de baixa virou SECURITY DEFINER)
- [x] Alerta de reposição (DEC-027): contínuo = cobertura determinística
      pela prescrição ativa (< 5 dias, DEC-012) + sugestão de compra p/
      30 dias (DEC-028); SOS = `estoque_minimo` por medicamento (campo
      novo, exposto no cadastro da gestão e no seed); view
      `cobertura_estoque` redefinida (média móvel de 14 dias descartada)
- [x] Tela de estoque (DEC-029): abas Ronda | Estoque; lista por
      residente com seção "Repor" no topo; ficha por medicamento com
      extrato linha a linha (data, tipo, quantidade, cuidador, motivo)
      e ações de compra/ajuste/perda
- [x] Dose avulsa SOS (DEC-014): fluxo na tela da ronda (residente →
      medicamento SOS → quantidade → confirmar), `horario_id` nulo,
      baixa pelo trigger existente
- [x] 2 migrations novas (20260717000100 ledger, 20260717000200 view)
      aplicadas e espelhadas; smoke test com rollback + 16 blocos de
      teste SQL; ciclo completo verificado no navegador (viewport 375px);
      `npm run build` OK; banco resetado limpo ao final

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

**Próxima sessão:** **Sessão Claude Code #6** — deploy no Railway, PWA no
celular da casa, cadastro dos dados reais (incl. bootstrap da admin real,
Thais) e acompanhamento do início do piloto.

## Pendências operacionais

- [ ] **Guilherme:** revisar RELATORIO_SESSAO_05.md, salvar no Drive, commit + push
- [ ] **Guilherme:** teste funcional com `npm run seed -- --com-historico`
      antes do go-live (aba Adesão com 7 dias de dados; `--reset` para limpar)
- [ ] **Guilherme:** testar o fluxo no celular da casa (login
      `casa@namicare.app` — senha em `.env.local` — e turno com PIN de teste;
      gestão: Ana Souza, PIN 1111)
- [ ] Ícones do PWA estão em SVG; gerar PNG 192/512 antes do teste de instalação
      no celular da casa (o logo real entra na Sessão #6)
- [ ] Termo LGPD com a casa de repouso ANTES de inserir dados reais
- [ ] Bloqueio por inatividade (repedir PIN — implicação da DEC-002) ficou
      fora do MVP; reavaliar após o piloto começar
- [ ] Bootstrap da administradora real (Thais) por seed/script no cadastro
      dos dados reais — a gestão exige uma admin já existente (Sessão #6)
- [x] ~~Leaked Password Protection~~ — ENCERRADA na Sessão #5: indisponível
      no plano Free; mitigada com senha aleatória forte + comprimento
      mínimo 12 (ver RELATORIO_SESSAO_05.md §5)

## Próximos passos (ordem sugerida)

1. **Sessão Claude Code #6:** deploy no Railway, URLs no Supabase Auth,
   PWA no celular da casa, cadastro dos dados reais (bootstrap da Thais
   como admin), última contagem manual como estoque inicial
2. Piloto assistido: 1ª semana com acompanhamento próximo das 4 cuidadoras
   (observar cobertura de turnos — limite documentado na DEC-030)
3. Backlog registrado: acuracidade de estoque (extrato de movimentações por
   período — candidata a sessão própria); motivo de recusa agregado por
   medicamento (ideia futura)

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
