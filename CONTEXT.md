# CONTEXT — Nami Care

> Estado atual do projeto para continuidade entre sessões (Claude.ai e Claude Code).
> Última atualização: 2026-07-22 (fim da Sessão #11)

## Onde estamos

**Fase atual:** Fase 4 — Go-live. **App no ar em
https://nami-care-production.up.railway.app**; o piloto ainda não começou
(falta o banco de produção receber os dados reais).

**Sessão #11 (2026-07-22) — CONCLUÍDA.** Ver `RELATORIO_SESSAO_11.md`. A maior
mudança estrutural desde o MVP: estoque rastreado por **lote físico com validade**
e saída automática por **FEFO** (espelha a operação da Thais, aposenta a planilha).
Decisões **DEC-040..043**; 4 migrations novas (`20260722000100..000400`).
- [x] **Modelo (DEC-040):** `lotes_estoque` (saldo físico por validade) + vínculo
      `movimentacao_lote` (1-para-N — uma saída FEFO varre vários lotes). O ledger
      `movimentacoes_estoque` segue **intocado em forma** (fonte do
      extrato/cobertura/adesão); `saldo_estoque` passa a derivar da soma dos lotes.
      Dois helpers transacionais (`fn_registrar_lote_entrada`, `fn_consumir_fefo`,
      SECURITY DEFINER com execute revogado). Invariante `sum(lotes)==ledger`.
- [x] **Entradas (DEC-041):** cadastro/recompra/ajuste-para-cima capturam validade
      (obrigatória) + lote (opcional); criam o lote junto da movimentação.
      `registrar_entrada_estoque` ganhou `p_validade`/`p_lote`;
      `registrar_ajuste_estoque` para cima cria lote de origem `remanescente`.
- [x] **Saídas FEFO (DEC-042):** trigger de baixa, ajuste-para-baixo e perda abatem
      por validade mais próxima, varrendo múltiplos lotes (empate → data_entrada).
      **A ronda não mudou** — baixa automática e silenciosa (DEC-008 estendida).
      Super-administração é best-effort (saída cheia, lotes piso em zero).
- [x] **Visibilidade (DEC-043):** estoque atual mostra lote/validade por
      medicamento (próximo a vencer em destaque, via `lotes_estoque_vivo`); extrato
      indica o(s) lote(s) de cada movimentação.
- [x] Bateria SQL em rollback; seed com 24 lotes e **0 divergências**; navegador a
      375px (compra, FEFO multi-lote na perda, extrato com lote, ronda inalterada);
      build OK; advisors sem nada novo; seed resetado. **Nada do go-live tocado.**
- [ ] **Fora de escopo, aguardando sessão própria:** categoria "agudo"; abertura
      de caixa / início de tratamento; alerta de vencimento; "medicamento da casa";
      escolha manual de lote na perda.

**Sessão #10 (2026-07-21) — CONCLUÍDA.** Ver `RELATORIO_SESSAO_10.md`. Três
ajustes independentes vindos da demonstração à Thais, de baixo/médio risco:
- [x] **"Encerrar turno" no cabeçalho** (antes vivia dentro da aba Ronda):
      visível de qualquer aba, pill branco sólido no canto superior direito,
      distinto dos botões de gestão. A lógica de fechamento é a MESMA
      `fechar_turno` — o que mudou é navegação: a recusa leva a cuidadora até a
      fila que a bloqueou (Ronda, ou "Pendências entre turnos" se o bloqueio for
      só de lá)
- [x] **DEC-039 — janela de "atrasada" de 30 → 60 min** (revisa a DEC-010):
      migration 20260721000200 redefinindo `doses_do_turno`. As duas ocorrências
      de `30 minutes` no schema eram **a mesma função redefinida**, então o
      `create or replace` resolve as duas por construção. `fechar_turno` continua
      exigindo tratativa de toda dose devida — a janela governa a cor, nunca a
      exigência de resposta
- [x] **Horários no cadastro de medicamento contínuo** (`FormMedicamento`): o
      cadastro nascia incompleto — um contínuo sem horário não gera dose. Agora
      há bloco de hora + dose, encadeando `criar_horario` via
      `src/lib/horariosIniciais.js` (padrão do `estoqueInicial.js`). Vale para as
      duas portas (atalho "+ Medicamento" e Residentes). SOS segue sem horários.
      Contínuo passou a **exigir ao menos um horário**; a edição de horário
      continua só na ficha, para não esconder o versionamento da DEC-026
- [x] Correção de passagem: a linha Dosagem + Forma estourava os 375px e fazia o
      modal inteiro rolar na horizontal (`min-width: 0`) — defeito pré-existente
      da Sessão #8
- [x] Smoke test com rollback + bateria de fronteira (20/45/59/61/75/200 min);
      critério de pronto (1)–(5) no navegador a 375px; build OK; advisors sem
      nada novo; seed resetado limpo
- [ ] **Fora de escopo, aguardando sessão própria:** rastreamento por lote e
      validade (muda o núcleo do ledger — provável FEFO) e "medicamento da casa"

**Sessão #9 (2026-07-21) — CONCLUÍDA.** Ver `RELATORIO_SESSAO_09.md`. Sessão
curta de DADOS (nenhuma linha de `src/`, migration, RPC ou tela), para a
demonstração ao vivo do app à Thais:
- [x] **`npm run seed-demo`** (flag `--demo` no seed + `scripts/seed-demo.js`):
      cenário de casa em operação sobre o banco de TESTE — histórico de adesão
      D-6..D-1, turno aberto agora, lacuna de turno em D-3 que acende a faixa
      vermelha de "Pendências entre turnos", e doses na **janela do horário em
      que o script roda** (−85 min a +110 min relativos ao `now()`, nunca
      horário fixo), com tratadas + atrasada + na hora + a vencer
- [x] Reexecutável: rodar de novo recompõe tudo com a janela recalculada
- [x] Escrita toda pelas RPCs reais; ajustes diretos só de DATA (turnos e
      `horarios.criado_em`), mesma tolerância documentada no `seed-historico`
- [x] Critério de pronto (1)–(6) conferido no navegador a 375px; build OK
- [x] **O banco ficou POVOADO de propósito** — dados fictícios de demo
- [ ] ⚠️ **`npm run limpar-banco` do go-live AINDA PRECISA RODAR depois da
      conversa**, antes de qualquer dado real. A demo não é o piloto

**Sessão #8 (2026-07-21) — CONCLUÍDA.** Ver `RELATORIO_SESSAO_08.md`. Primeira
sessão pós-MVP, a partir do teste real do PWA no celular. Quatro entregas:
- [x] **DEC-038 — gestão de residentes autorizada por TURNO, não por PIN de
      admin (inverte parcialmente a DEC-024):** as 9 RPCs de residentes,
      medicamentos e prescrições passaram de `fn_autorizar_admin` para
      `fn_cuidador_do_turno` (erro novo `sem_turno_aberto`); toda a validação de
      negócio preservada. Motivo: a trava não protegia o histórico clínico —
      corrompia, porque a cuidadora aplicava a nova prescrição no mundo real e
      não conseguia registrá-la. A **DEC-026 (versionamento) é o que torna isso
      seguro**, e a auditoria melhora (a autoria passa a ficar no app). A gestão
      de **equipe** continua integralmente sob a DEC-024
- [x] **Estoque inicial no cadastro de medicamento:** passo opcional com escolha
      da origem — compra (`entrada_compra`) ou remanescente (`ajuste_contagem`);
      encadeia as RPCs de ledger existentes, sem caminho de escrita novo
- [x] **Atalho "+ Medicamento" na aba Estoque:** seletor de residente + mesmo
      cadastro pelo catálogo (DEC-035) + estoque inicial
- [x] **Home reorganizada:** nome da cuidadora abaixo do título (não clicável);
      "Gestão residentes" (todas) e "Gestão equipe" (só admin, ainda com PIN) no
      header; pendências entre turnos viraram faixa de alerta que só existe com
      pendência; abas = Ronda, Adesão, Estoque
- [x] **BUG-003 corrigido na mesma sessão** (achado pelo Guilherme no celular,
      após a entrega): "Gestão equipe" não aparecia para a admin logo depois de
      ela assumir o turno — só depois de entrar e sair da gestão. Causa: DOIS
      lugares montavam o objeto do turno, e o payload da RPC `abrir_turno` não
      tem (nem deve ter) `eh_admin`. Correção: o App recarrega o turno do banco
      ao abri-lo; `setTurno` passa a receber o objeto de um lugar só.
      **Invariante:** campo novo que a UI precise do turno entra em
      `carregarTurnoAberto` (`App.jsx`), nunca no retorno de uma RPC de operação
- [x] 1 migration nova (20260721000100) com smoke/rollback + bateria SQL;
      critério de pronto (1)–(9) no navegador (375px); build OK; advisors sem
      categoria nova; seed resetado limpo

**Sessão #7 (2026-07-21) — PARCIALMENTE CONCLUÍDA.** Ver
`RELATORIO_SESSAO_07.md`. Sessão de infraestrutura, sem nenhuma mudança de
produto. Deploy e PWA prontos e verificados na URL pública; o que depende de
dado que só a casa tem (nomes, prescrições, contagem, PIN da Thais) está
preparado e documentado como runbook (§6 do relatório), não executado.
- [x] **Produção no ar (DEC-037):** serviço no Railway servindo o build
      estático, reprodutível pelo repositório — `railway.json` (build + start),
      `.node-version`, `npm run start` servindo `dist/` em modo SPA; o dev
      server do Vite não roda em produção. Fronteira de segredos verificada no
      bundle publicado: só `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY`;
      service role e `CASA_SENHA` ausentes
- [x] **PWA instalável:** ícones PNG 192/512 (any e maskable) + apple-touch-icon
      e favicon, gerados do logo real da casa por `npm run icones` (símbolo
      isolado sobre creme, blend multiply); manifest atualizado; SVGs teal da
      Sessão #1 removidos. Conferido NA URL PÚBLICA: manifest, os 4 ícones e o
      SW em 200, SW registrado sobre HTTPS com escopo `/`, console limpo, tela
      de login no tema Sereníssima a 375px
- [x] **Ferramental do go-live:** `npm run limpar-banco` (apaga o seed sem
      repopular, exige digitar APAGAR) e `npm run criar-admin` (primeira
      administradora; PIN digitado por ela sem eco na tela, hash no banco;
      recusa rodar se já houver cuidadora)
- [x] **Achado verificado:** o app só usa `signInWithPassword` — Site URL e
      Redirect URLs NÃO bloqueiam o login pela URL do Railway (CORS do Auth ecoa
      qualquer origem). Cadastrar a URL segue recomendado como higiene, mas não
      é pré-requisito do go-live
- [x] Advisors revisados: sem novidade não intencional; build final OK
- [x] **Supabase Auth de produção configurado:** Site URL
      `https://nami-care-production.up.railway.app` + 2 Redirect URLs (produção
      e `localhost:5173`). Higiene — não bloqueava o login (ver DEC-037)
- [ ] **Aberto:** instalar no celular da casa; limpar o banco de teste e
      cadastrar os dados reais

**Sessão #6 (2026-07-20) — CONCLUÍDA.** Ver `RELATORIO_SESSAO_06.md`. Duas
entregas na ordem (a 2ª depende da 1ª):
- [x] **Catálogo de medicamentos (DEC-035):** nova entidade da casa
      `catalogo_medicamentos` + `medicamentos.catalogo_id` (FK NOT NULL);
      elo "mesmo remédio, N residentes" por SELEÇÃO HUMANA, nunca por
      texto. Cadastro busca/seleciona no catálogo ou cria item novo junto
      (atômico); nome/dosagem/forma deixam de ser texto livre na tela do
      residente; `catalogo_id` imutável após uso (DEC-026 estendida).
      Backfill do seed: **23 itens** (só Losartana 50 mg compartilhada).
- [x] **Extrato de movimentação (DEC-036):** tela SOMENTE LEITURA dentro
      da aba Estoque, segmented control com "Estoque atual" (Sessão #4,
      inalterada, padrão). Consolidado por catálogo (sub-abas Contínuo/SOS,
      calendário da Adesão), pior caso do grupo à frente, badge "N
      residentes" + detalhe por residente; drill-in colorido por DIREÇÃO
      (sinal), filtro por subtipo. Inativos com selo, sem alerta.
- [x] 2 migrations novas (000200 catálogo, 000300 extrato) com smoke/
      rollback + bateria SQL; critério de pronto (1)–(9) no navegador
      (375px); build OK; advisors sem novidade; seed atualizado (cria
      catálogo) e resetado limpo (23 itens de catálogo)

**Sessão #5.5 (2026-07-20) — CONCLUÍDA.** Ver `RELATORIO_SESSAO_05_5.md`.
Sessão curta dedicada ao **BUG-002** (dose vencida em período sem turno
aberto era invisível — limite documentado na DEC-030). Entregas:
- [x] Fila própria "Pendências entre turnos" (DEC-033): consulta
      independente com teto de 5 dias + contagem de dias perdidos além do
      teto; `doses_do_turno` intocada
- [x] 4ª aba da operação, inteira vermelha com contagem enquanto houver
      pendência; agrupamento dia → residente; tratativa individual pelo
      MESMO modal da ronda (export, sem duplicar)
- [x] Resolução em lote (DEC-034): novo status `pendente` ("não sabemos e
      decidimos não apurar" ≠ `nao_tomado`), só alcançável pela RPC com PIN
      do cuidador do turno + alerta de criticidade cheio de tela; sem
      movimentação de estoque (reconciliação manual)
- [x] `fechar_turno` exige as duas filas (dentro do teto) zeradas, com
      mensagem distinguindo a origem; relatório de adesão com 5ª categoria
      "Pendente (não apurado)" no denominador
- [x] 1 migration nova (20260720000100) com smoke/rollback + bateria SQL
      (A1–A9, B1–B11); critério de pronto (a)–(g) no navegador (375px);
      build OK; advisors sem novidade não-intencional; seed resetado
- [x] MH-002 (mostrar pendência antes de abrir o turno) — confirmada pelo
      Guilherme na sessão e IMPLEMENTADA: aviso com contagem na tela de
      assumir turno, antes do PIN (reusa a RPC; sem mudança de banco)

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
      tolerância de 30 min calculada no banco (**hoje 60 min — DEC-039,
      Sessão #10**)
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

**Reordenação (2026-07-20):** antes do deploy, o Guilherme trouxe uma
necessidade de negócio — acompanhamento de movimentação de estoque — que
entra no MVP como **Sessão #6**. Ver `SESSAO_06.md`. O deploy/go-live
(escopo que estava previsto aqui) vira **Sessão #7**.

**Próximo passo (inalterado pelas Sessões #8 e #9 — a demo da #9 povoou o banco
de TESTE com dados fictícios e não substitui nenhum passo abaixo; o
`npm run limpar-banco` do passo 5 continua obrigatório antes dos dados reais):**
não é uma sessão de código — são
os **passos 4 a 8 do runbook
de go-live** (§6 do `RELATORIO_SESSAO_07.md`), pelo Guilherme com a Thais:
instalar no celular da casa, limpar o banco de teste, bootstrap da Thais,
cadastrar os dados reais pela tela de gestão (medicamentos SEMPRE pelo catálogo
da Sessão #6 — o 1º cadastro cria o item, os demais residentes reaproveitam por
busca) e lançar a última contagem manual como movimentação. Só depois disso o
MVP entra em piloto.

## Pendências operacionais

- [ ] ⚠️ **Guilherme:** o banco de teste está POVOADO com o cenário de
      demonstração da Sessão #9 (dados fictícios). Rodar `npm run limpar-banco`
      (passo 5 do runbook) antes de cadastrar qualquer dado real da casa
- [ ] **Guilherme + Thais:** executar os passos 4–8 do runbook de go-live
      (`RELATORIO_SESSAO_07.md` §6) — instalação no celular, limpeza do banco,
      bootstrap da Thais, dados reais. Passos 1–3 (publicar, Railway, URLs do
      Auth) concluídos em 2026-07-21. **A Sessão #8 encurtou o passo 7:** o
      cadastro de medicamento agora tem estoque inicial embutido (compra ou
      remanescente) e atalho dentro da aba Estoque — a viagem separada à aba
      para lançar a primeira entrada deixou de ser necessária
- [ ] **Guilherme:** revisar RELATORIO_SESSAO_10.md, salvar no Drive, commit + push
- [ ] Acompanhar no piloto: se **60 min** (DEC-039) é a tolerância certa. Agora
      que o vermelho é mais raro, ele deve voltar a significar alguma coisa;
      eventual reajuste deve vir de uso observado, não de suposição
- [ ] Acompanhar no piloto: a exigência de **ao menos um horário** no cadastro de
      medicamento contínuo (Sessão #10). Se existir caso legítimo de cadastrar
      antes de saber a posologia, é fácil afrouxar
- [x] **Rastreamento por lote e validade — FEITO na Sessão #11** (DEC-040..043):
      cada entrada com lote/validade próprios, exibidos no estoque por residente;
      baixa por FEFO (validade mais próxima primeiro, varrendo lotes). O ledger
      virou duas verdades sincronizadas (lotes + `movimentacoes_estoque`).
      Levantado na demo à Thais
- [ ] **Guilherme:** revisar RELATORIO_SESSAO_08.md, salvar no Drive, commit + push
- [ ] Acompanhar no piloto: mudar prescrição no meio do dia versiona (DEC-026) e
      faz o slot novo pedir tratativa naquele mesmo dia — comportamento antigo,
      mas que ficará muito mais visível agora que a edição é da cuidadora do
      turno (ver `RELATORIO_SESSAO_08.md` §6)
- [ ] "Medicamento da casa" (SOS sem residente vinculado) — postergado na
      Sessão #8: `medicamentos.idoso_id` é NOT NULL; exige decisão e sessão
      próprias
- [ ] **Guilherme:** logo definitivo refinado do PWA (os ícones atuais vêm de um
      print, upscalado de 147px — legível e on-brand, mas um vetor original
      daria traço mais limpo). Trocar o arquivo e rodar `npm run icones`
- [ ] Usar o logo horizontal completo no cabeçalho / tela de login — não coube
      na Sessão #7 (que não podia mexer em tela); sessão futura
- [ ] **Guilherme:** revisar RELATORIO_SESSAO_07.md, salvar no Drive, commit + push
- [ ] **Guilherme:** revisar RELATORIO_SESSAO_06.md, salvar no Drive, commit + push
- [ ] **Guilherme:** revisar RELATORIO_SESSAO_05_5.md, salvar no Drive, commit + push
- [ ] **Guilherme:** revisar RELATORIO_SESSAO_05.md, salvar no Drive, commit + push
- [ ] **Guilherme:** teste funcional com `npm run seed -- --com-historico`
      **antes** do passo 5 do runbook (`npm run limpar-banco`) — depois da
      limpeza não há mais base de teste
- [ ] **Guilherme:** testar o fluxo no celular da casa (login
      `casa@namicare.app` — senha em `.env.local` — e turno com PIN de teste;
      gestão: Ana Souza, PIN 1111)
- [x] ~~Ícones do PWA em SVG~~ — RESOLVIDA na Sessão #7: PNG 192/512 (any e
      maskable) gerados do logo real por `npm run icones`
- [x] ~~Termo LGPD com a casa~~ — resolvido fora das sessões; não bloqueante
- [x] ~~Bootstrap da administradora real (Thais)~~ — script pronto na Sessão #7
      (`npm run criar-admin`); falta executar com ela junto
- [ ] Bloqueio por inatividade (repedir PIN — implicação da DEC-002) ficou
      fora do MVP; reavaliar após o piloto começar
- [x] ~~Leaked Password Protection~~ — ENCERRADA na Sessão #5: indisponível
      no plano Free; mitigada com senha aleatória forte + comprimento
      mínimo 12 (ver RELATORIO_SESSAO_05.md §5)

## Próximos passos (ordem sugerida)

1. **Runbook de go-live** (`RELATORIO_SESSAO_07.md` §6), pelo Guilherme com a
   Thais — não é sessão de código: Railway, limpeza do banco de teste,
   bootstrap da Thais, cadastro real pelo catálogo, última contagem manual como
   movimentação de estoque, instalação no celular
2. Piloto assistido: 1ª semana com acompanhamento próximo das 4 cuidadoras
   (lacunas de cobertura de turno agora são visíveis e tratáveis pela tela
   "Pendências entre turnos" — BUG-002 corrigido na Sessão #5.5; observar o
   uso real dela e explicar a diferença "não tomada" × "pendente")
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