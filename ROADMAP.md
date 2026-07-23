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

## Sessão 12 — Medicamento da casa (SOS compartilhado) e SOS reestruturado ✅ (2026-07-22)

Último item estrutural do backlog da Thais: os SOS da **casa** (dipirona,
antitérmico, antiemético — a caixa comum da bancada) passam a existir, sem que o
consumo fique anônimo. O princípio: **o estoque pode ser da casa; o consumo tem
sempre um dono.** Decisões **DEC-044..047**; 5 migrations novas.

- **Sentinela (DEC-044):** um residente reservado "Da Casa"
  (`idosos.eh_sentinela`, único parcial) carrega o estoque compartilhado.
  `medicamentos.idoso_id` **seguiu NOT NULL** — schema de medicamentos intocado,
  os ~16 `join idosos` intactos, **sem flag `eh_da_casa`**. Medicamento da casa é
  sempre SOS; o sentinela não é desativável; nasce de bootstrap idempotente.
  Aparece em vermelho na gestão e no "+ Medicamento", em seção própria no
  estoque; some da adesão e do seletor de quem toma.
- **Dono da dose (DEC-045):** `administracoes.idoso_id` — a única mudança de
  schema. Preenchido só no SOS da casa. Regra única:
  `coalesce(administracoes.idoso_id, medicamentos.idoso_id)`. Trigger fecha os
  dois lados; imutabilidade estendida.
- **Adesão (DEC-046):** o relatório resolve o residente pelo coalesce — a dose da
  caixa comum entra na adesão de quem tomou, e o "Da Casa" não gera linha.
- **SOS reestruturado (DEC-047):** quem toma → qual medicamento (os dela + os da
  casa, coexistindo) → quantidade, registrado com o horário real. A dose SOS
  virou RPC; INSERT direto do cliente ficou restrito à dose agendada. **A ronda
  não mudou.** Lote/validade/FEFO da Sessão #11 valem sem exceção.

Bateria SQL em rollback (10 casos + agendada inalterada + invariante
`sum(lotes)==ledger` nos 27 medicamentos, 0 divergências); conferência a 375px
ponta a ponta (cadastro de SOS da casa com lote/validade, "Da Casa" vermelho,
seção separada no estoque, SOS da casa refletido na adesão da residente, SOS
próprio inalterado e **ronda agendada registrando normalmente**); build OK; seed
resetado criando o "Da Casa" com 3 SOS; advisors sem nada novo em espécie.
**Nada do go-live foi tocado.**

**Levantado na conferência:** a observação de alergia do residente não vira alerta
no passo de escolha do medicamento SOS. *(Encaminhado na Sessão #13: vira feature
futura do backlog, NÃO bloqueante do go-live.)*

**Fora de escopo, aguardando sessão própria:** categoria "agudo"; abertura de
caixa / início de tratamento; alerta de vencimento; escolha manual de lote na
perda; medicamento da casa contínuo (decidido não existir); múltiplas
casas/setores.

---

## Sessão 13 — Ver quem tomou: extrato de adesão e dono da dose ✅ (2026-07-23)

Veio do teste de usabilidade logo após a Sessão #12: a dose SOS de dipirona **da
casa** dada à Alzira ficou gravada certo, mas **nenhuma tela mostrava que tinha
sido ela**. O relatório de adesão só devolvia agregados — dava para saber que
houve 3 não tomadas, nunca *quais*. **Buraco de visibilidade, não de dados:**
nenhuma coluna nova, nenhum trigger, nenhuma escrita. Sessão inteiramente de
leitura e apresentação.

- **Fonte única (DEC-048):** `fn_doses_adesao` passa a ser a única definição de
  "quais doses compõem a adesão" — inclusive a **regra de período assimétrica**
  (agendada por `prevista_em`, SOS por `registrado_em`) e o dono resolvido.
  `relatorio_adesao` conta em cima dela; o detalhe é a mesma função filtrada.
  Evita o risco real: um segundo `where` divergindo e a tela dizendo "4" e
  listando 3. Mesmo padrão de `doses_do_turno` na ronda. Refactor provado com o
  jsonb inteiro idêntico antes × depois (39 comparações, 0 divergências).
- **Extrato de adesão (DEC-048):** com residente escolhido, as 5 categorias + a
  linha de SOS abrem a lista das doses. Só por residente; teto de 200 com aviso
  de corte; atrasada mostra previsto × registrado; SOS leva chip "Da casa".
  Nenhuma categoria nova, nenhum cálculo no cliente.
- **Ledger unificado (DEC-049):** a ficha do estoque lia a tabela direto
  (rótulo por `tipo`) e a aba de extrato lia pela RPC (rótulo por `subtipo`) —
  divergência real de rótulo. A ficha passou a consumir `extrato_medicamento`,
  que ganhou período opcional (nulos = últimas 50). Campo `residente` só em baixa
  por dose de medicamento da casa: `Cuidadora: … · Residente: …`.

Bateria SQL em rollback (20 casos, 20 verdes); invariante
`detalhe.total == relatorio.qtd` em 216 combinações, 0 divergências; conferência
a 375px ponta a ponta, incluindo o ponto de risco (ronda agendada e fluxo SOS
exercitados na tela, ambos intactos); build OK; advisors sem nada novo em
espécie; seed resetado. **Nada do go-live foi tocado.**

**Achado de passagem, corrigido:** `npm run seed-demo` estava quebrado desde a
Sessão #11 — chamava `registrar_entrada_estoque` sem a `p_validade` que a DEC-041
tornou obrigatória.

---

## Sessão 14 — Ajustes visuais de go-live ✅ (2026-07-23)

Sessão **inteiramente de CSS e apresentação**, nascida do teste que o Guilherme
fez no aparelho logo após a Sessão #13: quatro defeitos visuais, nenhum de dados
nem de regra de negócio. **Nenhuma migration, nenhuma RPC, nenhuma consulta,
nenhuma escrita, nenhuma mudança de schema.** Decisão nova: **DEC-050**.

- **BUG-004 — `input[type="date"]` estoura o contêiner no WebKit.** No iOS o
  campo tem **largura intrínseca própria**, derivada do formato da data, e não
  encolhe abaixo dela nem com `width: 100%`. O `min-width: 0` que existia vivia
  só no `<label>`; o input por dentro transbordava e invadia o vizinho. Visível
  na Adesão a 375px; **latente** no Extrato de movimentações, nos modais de
  validade do Estoque e nas datas do `FormMedicamento`. Corrigido com regra
  **global** em `input[type="date"]` (`appearance: none`, `min-width: 0`,
  `width: 100%`), que cobre as quatro telas de uma vez, mais a nova
  `.periodo-datas`, que empilha "De" e "Até" **sempre** — não abaixo de um
  breakpoint: resolve a classe do bug em vez da ocorrência, e não volta a apertar
  se a cuidadora usar fonte ampliada.
- **BUG-005 — atalhos de período órfãos.** Em `.atalhos` (flex-wrap, pills de
  largura intrínseca) os quatro períodos quebravam 3 + 1 a 375px e "Este mês"
  sobrava sozinho na segunda linha, com cara de item solto em vez de quarta
  opção do grupo. Nova `.atalhos-periodo` em **grade 2×2**. `.atalhos` e
  `.subabas` ficaram intactas — a alternância "Contínuo | SOS" reaproveita
  `.atalhos` e são dois botões, não uma grade.
- **BUG-006 — linha de doses SOS sem afordância de clique.** O recurso foi
  entregue na Sessão #13 e funcionava; a linha é que continuou parecendo rodapé
  (vinha depois da prosa explicativa, com o `›` no meio de uma frase e tamanho de
  legenda). **O efeito observado é o registro mais útil desta sessão: o próprio
  autor do recurso, testando no aparelho, quase concluiu que a Sessão #13 não o
  tinha entregue.** Um recurso que ninguém descobre é, na prática, um recurso que
  não existe — e isso vale dobrado para as cuidadoras, que não sabem o que
  procurar. O SOS ganhou **bloco próprio** com divisor, usando o mesmo
  `.adesao-linha` das cinco categorias: rótulo à esquerda, número à direita onde
  os olhos já procuram o percentual, seta na mesma coluna. A explicação saiu de
  dentro da área clicável e virou legenda. O aviso de pendentes **desceu para o
  fim** do card. As setas das outras cinco **não** mudaram: o problema era o SOS,
  não a afordância geral da tela.
- **BUG-007 — forma farmacêutica sem flexão de número** ("29 comprimido"), mais
  o `'unidade(s)'` que era o mesmo defeito disfarçado de solução. Resolvido pelo
  helper `fmtForma` (**DEC-050**), aplicado nos nove pontos que concatenam
  quantidade + forma e deliberadamente **fora** dos cinco onde a forma aparece
  sozinha. `'unidade(s)'` não existe mais no `src/`.

**Achado de passagem, corrigido:** em `ExtratoMovimentacoes.jsx` o bloco de
De/Até estava **fora** de um `.formulario`, então aqueles inputs não recebiam
padding nem borda — a tela "não estourava" por acidente, não por desenho. As duas
telas de período passam a ter o mesmo tratamento visual.

Conferido no navegador a 375px e a 320px ponta a ponta (Adesão, Extrato, modais
de compra e de ajuste, `FormMedicamento`), sem rolagem horizontal em nenhum;
clique do SOS reaberto e intacto; bateria do helper em Node com 10 formas × 5
quantidades; build OK; console sem erros. **Seed não resetado — nada de dados
mudou.** `git status` confirma `supabase/migrations/` intocado.

**Achado registrado, não corrigido:** nos prints do aparelho a barra de status do
iPhone aparece sobre as abas. As `.abas` não são `sticky`, então é provável que
seja artefato da moldura do print sobre uma captura já rolada — não foi
reproduzido no navegador. Fica para uma eventual sessão de `safe-area`.

---

## Fora de escopo do MVP (backlog pós-piloto)

- **Alerta de alergia** (Sessão #12 levantou, #13 encaminhou): a observação do
  residente é texto livre e não vira aviso na escolha do medicamento. Depende de
  estrutura para "a que o residente é alérgico" — texto livre não dá para
  comparar com segurança. **Não bloqueia o go-live**; conversar com a Thais com o
  piloto já rodando.
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