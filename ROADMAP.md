# ROADMAP — Nami Care

**Objetivo:** MVP em piloto na casa de repouso da Thais (4 cuidadoras, 11 residentes).
**Dor nº 1 da cliente:** contagem manual semanal de estoque de medicamentos.
**Estrutura:** desenvolvimento fatiado em sessões de Claude Code. Cada sessão tem
escopo fechado, definido no prompt de abertura, e termina com SESSAO_XX.md,
RELATORIO_SESSAO_XX.md e DECISIONS/CONTEXT atualizados. Este arquivo é a visão
do todo; em caso de conflito com DECISIONS.md, o DECISIONS prevalece.

---

## Sessão 1 — Fundação ✅ (2026-07-15)

- Setup do projeto (Vite + PWA, Supabase, Railway como alvo de deploy).
- Schema completo via migrations, RLS, seed (4 cuidadores, 11 residentes,
  medicamentos e estoque inicial).
- Trigger de baixa automática de estoque na administração de dose.
- Padrão ledger em `movimentacoes_estoque`: saldo nunca é sobrescrito,
  sempre calculado como soma das transações.

## Sessão 2 — Operação do turno ✅ (2026-07-16)

- PIN definitivo: bcrypt via pgcrypto, hash e verificação 100% no banco
  (`fn_hash_pin`, `abrir_turno`); `pin_hash` invisível ao cliente
  (DEC-020/021, substitui DEC-018).
- Rate limit: 5 falhas em janela móvel de 15 min, auditoria em
  `tentativas_pin`.
- Fluxo de turno via RPCs `abrir_turno`/`fechar_turno` como único caminho;
  fechamento exige tratativa em todas as doses (DEC-022).
- Tela da ronda: agenda via RPC `doses_do_turno`, tolerância de 30 min e
  situação calculadas no banco; telas LoginCasa, AssumirTurno e Ronda
  (DEC-023). *(Tolerância revisada para 60 min na Sessão #10 — DEC-039.)*

**Pendências pós-sessão:** ~~commit + push~~ ✅ · habilitar Leaked Password
Protection no dashboard do Auth · testar no celular da casa (depende do
deploy, Sessão 5).

## Sessão 3 — Gestão de cadastros ✅ (2026-07-16)

Transformou o sistema de "demo com dados do seed" em sistema que a casa
administra sozinha.

- Acesso à gestão: flag `eh_admin` + PIN de administradora validado no
  banco em cada RPC de gestão (DEC-024, substitui parcialmente DEC-011).
- Gestão de cuidadoras 100% por RPC (`criar_cuidador` com hash no banco,
  `atualizar_cuidador`, `definir_ativo_cuidador`); troca de PIN com
  verificação do atual ou por administradora (DEC-025); `definir_pin` sem
  verificação removida (BUG-001).
- Residentes com soft delete (`idosos.ativo`) e RPCs próprias;
  `doses_do_turno` ignora residente desativado.
- Prescrições versionadas (DEC-026): campos clínicos imutáveis após a
  primeira administração (triggers); editar horário com histórico
  desativa a linha antiga e cria a versão nova.
- Identidade visual Sereníssima aplicada em todas as telas + manifest.

**Critério de pronto atingido:** cadastro completo (cuidadora com PIN,
residente, medicamento com horário fracionado) feito pelo navegador, sem
tocar no banco na mão — verificado no ciclo completo + testes SQL.

**Pendências pós-sessão:** commit + push · bootstrap da admin real (Thais)
fica para o cadastro de dados reais (Sessão 5) · MH-001 (unificar a
verificação de PIN duplicada em `abrir_turno`).

## Sessão 4 — Estoque e SOS (a dor nº 1) ✅ (2026-07-17)

Fechou o ciclo do estoque e substitui a contagem manual semanal.

- **Ledger completo por RPC:** `registrar_entrada_estoque` (compra, data
  retroativa permitida), `registrar_ajuste_estoque` (a cuidadora informa a
  contagem; o banco calcula e grava a diferença) e
  `registrar_perda_estoque` (motivo obrigatório). Escrita direta em
  `movimentacoes_estoque` revogada do cliente; o trigger de baixa virou
  SECURITY DEFINER. Toda movimentação grava o cuidador do turno aberto.
- **Visão de estoque (DEC-029):** tela nova com abas Ronda | Estoque;
  lista por residente, seção "Repor" com os alertas no topo, extrato de
  movimentações linha a linha por medicamento.
- **Alerta de reposição (DEC-027):** contínuo = cobertura determinística
  pela prescrição ativa (< 5 dias, DEC-012) com sugestão de compra para
  30 dias (DEC-028); SOS = saldo abaixo do `estoque_minimo` do cadastro.
- **Fluxo SOS/PRN (DEC-014):** dose avulsa na tela da ronda (residente →
  medicamento SOS → quantidade), baixa pelo mesmo trigger da ronda.

**Critério de pronto atingido:** ciclo completo verificado no navegador —
compra → saldo sobe → dose na ronda e dose SOS → saldo desce → alertas nos
dois casos → ajuste por contagem corrige divergência sem apagar histórico.

**Pendências pós-sessão:** commit + push · Leaked Password Protection no
dashboard (desde a S2) · ajuste por contagem não é atômico com baixas
concorrentes (aceito no piloto de dispositivo único).

## Sessão 5 — Relatório de adesão ✅ (2026-07-18)

Reordenação deliberada: o deploy (planejado originalmente aqui) foi para a
Sessão 6; a 5 fechou o último item de produto do MVP (BRIEFING §6 item 10).

- **Modelo de cálculo (DEC-030):** denominador = doses já materializadas em
  `administracoes` (nunca reconstrução da grade histórica — o fechamento
  obrigatório de turno garante a completude e o versionamento de prescrição
  é absorvido naturalmente); classificação pelo status gravado, nunca por
  timestamps; 4 categorias + pendentes à parte (via `doses_do_turno`, sem
  duplicar a lógica de slots) + SOS como contagem absoluta; percentuais no
  banco, fuso da casa.
- **Aba "Adesão" (DEC-031):** operação junto de Ronda | Estoque, sem PIN de
  gestão — indicadores visíveis a toda a equipe (escolha registrada). Macro
  (casa) = micro (residente) sem filtro, mesma RPC; atalhos + calendário
  livre; residente desativado conta no histórico com selo na lista
  (DEC-032).
- **Seed com histórico:** `npm run seed -- --com-historico` — ~7 dias pelas
  RPCs reais (turnos, 4 status, SOS, mudança de posologia versionada, hoje
  parcial com turno aberto), reprodutível para o teste funcional pré-go-live.

**Critério de pronto atingido:** números da tela conferidos contra contagem
manual por SQL em todas as visões (hoje, multi-dia com mudança de posologia,
por residente, fronteira de fuso), bateria de 7 blocos + smoke com rollback.

**Pendências pós-sessão:** commit + push · teste funcional do Guilherme com
`--com-historico` · Leaked Password Protection ENCERRADA (indisponível no
Free; mitigada — ver RELATORIO_SESSAO_05.md §5).

## Sessão 5.5 — Pendências entre turnos (BUG-002) ✅ (2026-07-20)

Sessão curta, um único problema: dose que vencia em período sem NENHUM turno
aberto era invisível por construção (`doses_do_turno` é bounded pelo início
do turno — limite que a DEC-030 documentava).

- **Fila própria (DEC-033):** consulta independente com teto de 5 dias;
  dias mais antigos apenas contados para o aviso de dado perdido;
  `doses_do_turno` intocada.
- **Tela "Pendências entre turnos":** 4ª aba, inteira vermelha com contagem
  enquanto houver pendência; dia → residente; tratativa individual pelo
  mesmo modal da ronda.
- **Lote (DEC-034):** status novo `pendente` (≠ `nao_tomado`: "decidimos não
  apurar"), só via RPC com PIN do cuidador do turno + alerta de criticidade
  cheio de tela; sem baixa de estoque (reconciliação manual).
- `fechar_turno` exige as duas filas; relatório de adesão com a 5ª categoria
  "Pendente (não apurado)".

**Critério de pronto atingido:** cenário completo (lacuna de 7,5 dias)
verificado no navegador a 375px + bateria SQL sob rollback (20 blocos).

**Pendências pós-sessão:** commit + push. (MH-002 — mostrar pendência antes
de abrir o turno — foi confirmada e implementada na própria sessão: aviso
com contagem na tela de assumir turno.)

## Sessão 6 — Catálogo de medicamentos e extrato de movimentação ✅ (2026-07-20)

Reordenação deliberada: o deploy (planejado originalmente aqui) foi para a
Sessão 7 — acompanhamento de movimentação de estoque é, junto do ciclo
fechado na Sessão #4, o que mais valor entrega para a gestão da Thais, e
entrou ainda no MVP.

- **Catálogo de medicamentos (DEC-035):** nova entidade da casa
  (`catalogo_medicamentos` + `medicamentos.catalogo_id` NOT NULL) que dá o
  elo "mesmo remédio, N residentes" por seleção humana, nunca por texto —
  construção orgânica, sem fonte externa. Cadastro busca/seleciona no
  catálogo ou cria item novo junto (atômico); nome/dosagem/forma deixam de
  ser texto livre na tela do residente; `catalogo_id` imutável após uso
  (DEC-026 estendida). Backfill do seed: 23 itens (só Losartana 50 mg
  compartilhada). Sem regressão no fluxo da Sessão #3.
- **Extrato de movimentação (DEC-036):** tela somente leitura dentro da aba
  Estoque, segmented control com "Estoque atual" (Sessão #4, inalterada,
  padrão). Consolidado por catálogo (sub-abas contínuo/SOS, calendário da
  Adesão), pior caso do grupo à frente, badge "N residentes" com
  drill-down por residente; extrato do medicamento colorido por DIREÇÃO
  (sinal da quantidade, não o tipo — o `ajuste_contagem` é bidirecional),
  filtro por subtipo combinável com o período. Inativos com selo, sem
  alerta. Duas RPCs SECURITY INVOKER reaproveitando `cobertura_estoque`;
  RPCs/trigger da Sessão #4 intocados.

**Critério de pronto atingido:** (1)–(9) do `SESSAO_06.md` conferidos no
navegador a 375px + smoke com rollback de cada migration + bateria SQL
(backfill, criação por item novo/existente, bloqueio de troca com histórico,
ordenação pelo pior caso do grupo, sinal do ajuste, filtro de subtipo).

**Pendências pós-sessão:** commit + push.

## Sessão 7 — Deploy e go-live ⏳ (2026-07-21) — app no ar, dados reais pendentes

**Produção:** https://nami-care-production.up.railway.app


Última sessão de código do MVP planejado. Sessão de infraestrutura, sem
nenhuma mudança de produto: Ronda, turno, Pendências entre turnos, Adesão,
Estoque (atual e extrato), gestão e catálogo ficaram intocados.

- **Produção no ar (DEC-037):** serviço no Railway servindo o build estático,
  reprodutível pelo repositório — `railway.json` (build + start),
  `.node-version`, `npm run start` servindo `dist/` como estático em modo SPA;
  o dev server do Vite não roda em produção. Fronteira de segredos conferida no
  bundle publicado: só `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY`; service
  role e `CASA_*` seguem restritos a script local e ausentes do bundle.
- **PWA instalável:** ícones PNG 192/512 (any e maskable) + apple-touch-icon e
  favicon, gerados do logo real da casa por `npm run icones` — símbolo isolado
  (casinha, casal e coração) sobre o creme da identidade, porque a 192px o
  texto do logo horizontal fica ilegível. Manifest atualizado e conferido no
  build servido; placeholders SVG teal da Sessão #1 removidos.
- **Ferramental do go-live:** `npm run limpar-banco` (apaga o seed de teste sem
  repopular — o `seed --reset` reinsere dados fictícios, o que não pode
  acontecer em produção) e `npm run criar-admin` (bootstrap da primeira
  administradora, DEC-024: PIN digitado pela própria pessoa sem eco na tela,
  hash gerado no banco por `fn_hash_pin`).
- **Supabase Auth de produção:** Site URL + 2 Redirect URLs (produção e
  `localhost:5173`) configuradas. **Achado (DEC-037):** o app usa só
  `signInWithPassword` — essas URLs **não bloqueiam** o login pela URL do
  Railway; foram feitas como higiene, não como pré-requisito do go-live.

**Verificado na URL pública, a 375px:** tela de login no tema Sereníssima,
console limpo, manifest e os 4 ícones em 200, service worker registrado sobre
HTTPS com escopo `/` (instalabilidade atendida), bundle com as variáveis certas
e sem segredo vazado. Guardas dos dois scripts novos testadas contra o banco
real sem escrever nada. Advisors sem novidade não intencional.

**Aberto — execução operacional, não código** (passos 4–8 do runbook em
`RELATORIO_SESSAO_07.md` §6): instalar no celular da casa; limpar o banco de
teste e cadastrar os dados reais.

**Critério de pronto do MVP:** casa operando no app, sem planilha e sem
contagem manual — **ainda não atingido**: depende do runbook acima.

---

## Sessão 8 — Acesso da operação e usabilidade do cadastro ✅ (2026-07-21)

Primeira sessão **pós-MVP**, fora do plano original: nasceu do teste real do
PWA no celular, antes de levar o app à Thais. Tema comum das quatro entregas —
tirar travas que atrapalham a operação diária da cuidadora e encurtar o caminho
do cadastro de medicamento, sem perder auditoria nem integridade clínica.

- **DEC-038 — gestão de residentes autorizada por turno (inverte parcialmente a
  DEC-024):** as 9 RPCs de residentes, medicamentos e prescrições trocaram
  `fn_autorizar_admin` por `fn_cuidador_do_turno` (novo erro
  `sem_turno_aberto`). A trava de admin não protegia o histórico clínico —
  corrompia: a cuidadora aplicava a nova prescrição no mundo real e o app ficava
  com o dado velho, porque só a admin podia registrar. O que torna a abertura
  segura é a **DEC-026 (versionamento), intacta**; a auditoria melhora, porque a
  autoria passa a ser capturada. **Gestão de equipe segue integralmente sob a
  DEC-024** — administrar quem tem acesso ao sistema não é ato de cuidado.
- **Estoque inicial no cadastro de medicamento:** opcional, com escolha da
  origem — compra (`entrada_compra`) ou remanescente na prateleira
  (`ajuste_contagem`). Encadeia as RPCs de ledger da Sessão #4; sem caminho de
  escrita novo e sem mudança de schema.
- **Atalho "+ Medicamento" na aba Estoque:** seletor de residente + o mesmo
  cadastro pelo catálogo (DEC-035) + o estoque inicial. Encurta bastante o
  passo 7 do runbook de go-live.
- **Home reorganizada:** nome da cuidadora abaixo do título (não clicável, era
  um botão falso); "Gestão residentes" (todas) e "Gestão equipe" (só admin,
  ainda com PIN) no header; pendências entre turnos deixaram de ser aba e viraram
  faixa de alerta que só existe quando há pendência; abas = Ronda, Adesão,
  Estoque.

- **BUG-003 (achado e corrigido na mesma sessão):** "Gestão equipe" não aparecia
  para a administradora logo após ela assumir o turno — só depois de entrar e
  sair da gestão de residentes. O objeto do turno era montado em dois lugares, e
  o payload da RPC `abrir_turno` não carrega `eh_admin`. O App passou a recarregar
  o turno do banco ao abri-lo: uma fonte só para o formato do turno.

1 migration nova (20260721000100) com smoke/rollback e bateria SQL; critério de
pronto (1)–(9) no navegador a 375px, nos dois perfis; build OK; advisors sem
categoria nova; seed resetado. **Nada do go-live foi tocado.**

**Postergado:** "medicamento da casa" (SOS sem residente vinculado) —
`medicamentos.idoso_id` é NOT NULL; exige decisão e sessão próprias.

---

## Sessão 9 — Dados de demonstração ✅ (2026-07-21)

Sessão curta e descartável, de DADOS — nenhuma tela, RPC, migration ou arquivo
de `src/`. Entregou `npm run seed-demo`: cenário de casa em operação sobre o
banco de teste (histórico de adesão, turno aberto, lacuna de turno acendendo a
faixa de pendências, doses na janela do horário da execução) para a conversa com
a Thais. Ver `RELATORIO_SESSAO_09.md`.

---

## Sessão 10 — Ajustes rápidos do pós-demo ✅ (2026-07-21)

Três ajustes independentes levantados na demonstração à Thais, de baixo/médio
risco, entregues juntos. Tema comum: tirar atrito do uso real sem mexer em
estrutura — nenhuma RPC nova, nenhuma mudança de schema.

- **"Encerrar turno" no cabeçalho:** antes vivia dentro da aba Ronda, e de
  Estoque ou Adesão a cuidadora precisava voltar só para encerrar. A lógica de
  fechamento é a MESMA `fechar_turno`; o que mudou é navegação — a recusa leva
  até a fila que bloqueou (Ronda, ou "Pendências entre turnos" quando o bloqueio
  vem só de lá).
- **DEC-039 — janela de "atrasada" de 30 → 60 min** (revisa a DEC-010): 30 min
  era curto para o ritmo da casa e o vermelho precoce virava ruído. Migration
  20260721000200 redefinindo `doses_do_turno`. As duas ocorrências de
  `30 minutes` no schema eram a mesma função redefinida — o `create or replace`
  resolve as duas por construção. **`fechar_turno` continua exigindo tratativa de
  toda dose devida:** a janela governa a cor, nunca a exigência de resposta.
- **Horários no cadastro de medicamento contínuo:** o `FormMedicamento` da
  Sessão #8 gravava posologia e tipo mas nunca criava horários — um contínuo
  cadastrado por ele não gerava dose nenhuma. Agora há bloco de hora + dose
  encadeando `criar_horario`, valendo para as duas portas (atalho "+ Medicamento"
  e Residentes). SOS segue sem horários; contínuo passou a exigir ao menos um.
  A edição de horário continua só na ficha do medicamento, para não esconder o
  versionamento da DEC-026.

1 migration nova (20260721000200) com smoke/rollback e bateria de fronteira
(20/45/59/61/75/200 min); critério de pronto (1)–(5) no navegador a 375px; build
OK; advisors sem nada novo; seed resetado. **Nada do go-live foi tocado.**

**Fora de escopo, aguardando sessão própria:** rastreamento por lote e validade
(muda o núcleo do ledger — a baixa passa a escolher lote, provável FEFO) e
"medicamento da casa" (SOS sem residente, `idoso_id` NOT NULL).

## Sessão 11 — Estoque por lote e validade / FEFO ✅ (2026-07-22)

A maior mudança estrutural desde o MVP. O saldo deixa de ser um número e passa a
ser rastreado por **lote físico com validade**, com saída automática por **FEFO**
— espelhando o que a Thais faz na bancada, para aposentar a planilha de Excel.
Decisões **DEC-040..043**; 4 migrations novas.

- **Modelo (DEC-040):** `lotes_estoque` (saldo físico por validade) + vínculo
  `movimentacao_lote` (1-para-N, porque uma saída FEFO varre vários lotes). O
  ledger (`movimentacoes_estoque`) segue intocado em forma — fonte do
  extrato/cobertura/adesão. `saldo_estoque` passa a derivar da soma dos lotes.
  Invariante testado: `sum(lotes) == ledger`. Dois helpers transacionais
  (`fn_registrar_lote_entrada`, `fn_consumir_fefo`).
- **Entradas (DEC-041):** os três caminhos (cadastro, recompra, ajuste-para-cima)
  capturam validade (obrigatória) + lote (opcional) e criam o lote junto da
  movimentação.
- **Saídas FEFO (DEC-042):** dose, ajuste-para-baixo e perda abatem por validade
  mais próxima, varrendo múltiplos lotes; empate → data_entrada. **A ronda não
  muda** (baixa automática e silenciosa — DEC-008 estendida). Super-administração
  é best-effort (grava a saída cheia, lotes piso em zero).
- **Visibilidade (DEC-043):** estoque atual mostra lote/validade por medicamento
  (próximo a vencer em destaque); o extrato indica o(s) lote(s) de cada movimentação.

Bateria SQL em rollback (FEFO num lote, cruzando dois, zerando, 0,5+0,5, empate,
ajuste-baixo, perda, best-effort, invariante); seed com 24 lotes e **0
divergências**; verificação no navegador a 375px; build OK; advisors sem nada
novo. **Nada do go-live foi tocado.**

**Fora de escopo, aguardando sessão própria:** categoria "agudo"; início de
tratamento / abertura de caixa; alerta de vencimento próximo; "medicamento da
casa"; escolha manual de lote na perda.

---

## Fora de escopo do MVP (backlog pós-piloto)

- Motivo de recusa agregado por medicamento (registrada na Sessão #5).
- Relatórios/exportação para família ou vigilância sanitária.
- Multi-casa (hoje: 1 casa, 1 usuário Supabase, PIN por cuidadora —
  DEC-019).
- Notificações push de dose atrasada.
- Painel remoto para a Thais acompanhar de fora da casa.
- Desempenho por cuidador: decidido NÃO construir (Sessão #5) — mudaria a
  natureza da ferramenta, de cuidado para vigilância.

## Princípios permanentes (valem em toda sessão)

- Stack: JavaScript apenas (Vite + PWA), Supabase, Railway.
- Banco: exclusivamente o projeto `nami-care` (ref `uvkmvaheupziexlunnno`).
- Toda mudança de schema via migration; nunca SQL avulso.
- Regra de negócio no banco (RPCs, triggers); o cliente só apresenta.
- Ledger nunca sobrescrito; toda ação grava o cuidador do turno ativo.
- Decisões novas → DEC-0XX; bugs → BUG-0XX; melhorias → MH-0XX.