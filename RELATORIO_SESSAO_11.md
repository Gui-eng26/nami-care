# Relatório da Sessão #11 — Rastreamento de estoque por lote e validade / FEFO (2026-07-22)

> A maior mudança estrutural desde o MVP: o saldo deixa de ser um número e passa
> a ser rastreado por **lote físico com validade**, com saída automática por
> **FEFO** (First-Expired-First-Out). Levantada com a Thais para aposentar a
> planilha de Excel. Entrada: `SESSAO_11.md`. Decisões: **DEC-040..043**.

---

## 1. O que foi entregue

| Arquivo | O que mudou |
| --- | --- |
| `supabase/migrations/20260722000100_lotes_estoque_modelo.sql` | **nova** — tabelas `lotes_estoque` e `movimentacao_lote`, RLS, helpers `fn_registrar_lote_entrada` e `fn_consumir_fefo`, `saldo_estoque` derivando dos lotes (DEC-040) |
| `supabase/migrations/20260722000200_entradas_com_lote.sql` | **nova** — `registrar_entrada_estoque` ganha `p_validade`/`p_lote` e cria o lote junto (DEC-041) |
| `supabase/migrations/20260722000300_saidas_fefo.sql` | **nova** — trigger de baixa, `registrar_perda_estoque` e `registrar_ajuste_estoque` abatem/criam lote por FEFO (DEC-042/041) |
| `supabase/migrations/20260722000400_lotes_visiveis.sql` | **nova** — view `lotes_estoque_vivo`; `extrato_medicamento` devolve `lotes` por movimentação (DEC-043) |
| `src/components/FormMedicamento.jsx` | estoque inicial ganha lote + validade |
| `src/pages/Estoque.jsx` | modais de compra/ajuste com lote+validade; ficha com "Lotes na prateleira"; extrato inline com lote |
| `src/pages/ExtratoMovimentacoes.jsx` | lote(s) por movimentação no extrato consolidado |
| `src/lib/estoqueInicial.js` | repassa lote/validade aos dois caminhos |
| `src/lib/formato.js` | `dataLocal`, `rotuloLote`, `resumoLotesMov` |
| `src/lib/erros.js` | `validade_obrigatoria` |
| `src/index.css` | chips de lote na lista, bloco "Lotes na prateleira", selo "Próximo a vencer", lote no extrato |
| `scripts/seed.js` | cada estoque inicial cria um lote + vínculo (invariante nasce do seed) |

Quatro migrations novas. O ledger (`movimentacoes_estoque`) segue **intocado em
forma** — uma linha por movimentação, UNIQUE de baixa preservada; extrato
(DEC-036), cobertura (DEC-027) e adesão (DEC-030) leem dele sem mudança.

## 2. O modelo de lotes (DEC-040)

Duas verdades, escritas sempre na **mesma transação** (atomicidade é o requisito
nº 1 — se divergirem, o estoque mente):

- **`lotes_estoque`** — o saldo físico na prateleira, por validade. `lote` (código
  da caixa; NULL = "não identificado"), `validade` (obrigatória — chave do FEFO),
  `quantidade_inicial`, `saldo_atual` (≥ 0, meio-em-meio), `data_entrada`,
  `origem` (compra/remanescente). **Não há agrupamento:** cada entrada é um lote,
  mesmo com lote/validade repetidos.
- **`movimentacao_lote`** — distribuição de uma movimentação pelos lotes (1-para-N,
  porque uma saída FEFO varre vários lotes). `quantidade` com o sinal do ledger.
  Optou-se pela tabela de ligação em vez de N linhas de ledger por saída: mantém
  o extrato legível e a UNIQUE de baixa (DEC-008) intactos.

**`saldo_estoque` deriva da soma dos lotes.** Invariante testado:
`sum(lotes.saldo_atual) == soma do ledger` por medicamento, em toda operação bem
abastecida. A única divergência possível é a anomalia pré-existente de
super-administração (ver §4).

Dois helpers internos (SECURITY DEFINER, execute revogado de `authenticated`)
carregam a disciplina transacional: `fn_registrar_lote_entrada` (lote + vínculo +)
e `fn_consumir_fefo` (abate FEFO + vínculos −).

## 3. Entradas com lote e validade (DEC-041)

Os três caminhos de entrada capturam **validade (obrigatória) + quantidade**, com
**lote opcional** e data de entrada (default hoje):

1. **"+ Medicamento" / estoque inicial** — passa pelas RPCs abaixo via
   `estoqueInicial.js`, sem RPC nova. Compra → `registrar_entrada_estoque`;
   remanescente → `registrar_ajuste_estoque` (subida cria o lote do excedente).
2. **Recompra** — `registrar_entrada_estoque` (+`p_validade`/`p_lote`), origem
   `compra`, tipo `entrada_compra` (DEC-016).
3. **Ajuste de recontagem para cima** — exige validade (o excedente pertence a um
   lote físico); aceita lote nulo ("não identificado"); origem `remanescente`.

Validade no passado é aceita (remanescente perto da validade; ajuste manual).

## 4. Saídas por FEFO (DEC-042, estende a DEC-008)

Dose, ajuste-para-baixo e perda **abatem por FEFO** — validade mais próxima
primeiro, varrendo múltiplos lotes, um vínculo (−) por lote tocado:

- **A ronda não mudou.** A cuidadora segue com tomado/recusado/não-tomado; a baixa
  por lote é automática e silenciosa (a trigger grava a movimentação como antes e
  distribui pelos lotes). Verificado no navegador: a tela da ronda é idêntica.
- **Varredura multi-lote:** dose (ou perda) maior que o lote da frente consome o
  que houver dele (zerando-o) e segue para o próximo por validade. O caso 0,5+0,5
  resolve-se sozinho — sem menu, sem órfão.
- **Empate de validade** → `data_entrada` mais antiga (FIFO secundário).
- **Super-administração (edge documentado):** `fn_consumir_fefo` é best-effort. Se
  a dose excede o físico, a movimentação de saída é gravada cheia (a ronda nunca
  falha) e os lotes piso em zero. Só nesse caso `sum(lotes)` fica abaixo do ledger
  — é a mesma anomalia que o saldo negativo já sinalizava. Sem alerta de
  vencimento nesta sessão (decisão do Guilherme).

## 5. Lote e validade visíveis (DEC-043)

- **Estoque atual:** cada medicamento mostra os lotes vivos por validade
  crescente (chip "venc. dd/mm/aaaa · saldo" na lista; bloco "Lotes na prateleira"
  na ficha, com o selo "Próximo a vencer" no primeiro). Fonte: `lotes_estoque_vivo`.
- **Extrato:** cada linha indica o(s) lote(s) — entrada mostra o lote que criou;
  saída, de quais lotes saiu e quanto de cada. Na ficha da aba Estoque via embed
  direto; no extrato consolidado (DEC-036) via campo `lotes` de `extrato_medicamento`.

## 6. Testes

### Bateria SQL (transação com rollback, antes de confiar no apply)
Cada migration foi *smoke-testada* em `begin; … rollback;`. A bateria de FEFO,
com medicamentos frescos (ledger limpo) e as RPCs reais, cobriu e passou:
- entrada criando **lote + movimentação atômicos**; validade obrigatória; duas
  entradas com o mesmo lote/validade = **linhas separadas**; lote nulo aceito;
- dose **dentro de um lote**; dose **cruzando dois lotes** zerando o da frente;
  **0,5 + 0,5**; recusado → **perda automática** por FEFO;
- **ajuste-para-baixo** por FEFO; **ajuste-para-cima** criando lote (validade
  exigida, origem remanescente); **perda** por FEFO; **best-effort** (dose > estoque);
- empate de validade desempatado por **data_entrada**;
- **invariante `sum(lotes) == ledger`** e "cada movimentação == soma dos vínculos"
  em todos os cenários bem abastecidos.

Após o `seed --reset`, conferência no banco inteiro: **24 lotes, 24 vínculos, 0
divergências** entre a soma dos lotes e o ledger.

### Navegador (375px, tema Sereníssima)
| # | Item | Resultado |
| --- | --- | --- |
| 1 | Estoque atual mostra lote/validade por medicamento | ✅ chip "venc. dd/mm/aaaa · saldo" por item, sem overflow horizontal |
| 2 | Ficha: "Lotes na prateleira" ordenado, próximo a vencer em destaque | ✅ |
| 3 | Recompra com lote+validade; duas entradas com validades diferentes = dois lotes ordenados | ✅ LOTE-JAN (15/01/2027) + SEED-001 (22/04/2027), próximo a vencer marcado |
| 4 | Saída varre múltiplos lotes | ✅ perda de 40 → 30 de LOTE-JAN (zerou) + 10 de SEED-001; extrato mostra ambos |
| 5 | Extrato (inline e consolidado) mostra o lote de cada movimentação | ✅ |
| 6 | "+ Medicamento" captura lote+validade no estoque inicial | ✅ |
| 7 | Ronda inalterada | ✅ tela idêntica; baixa silenciosa |
| 8 | `npm run build` sem erro; console sem erros | ✅ build limpo |

**Advisors:** nada novo. `lotes_estoque`/`movimentacao_lote` com RLS e política de
SELECT (escrita revogada); os helpers `fn_consumir_fefo`/`fn_registrar_lote_entrada`
não aparecem (execute revogado de `authenticated`); `lotes_estoque_vivo` é security
invoker. Restam só os itens conhecidos e por design (RPCs SECURITY DEFINER das
DEC-020/024, `tentativas_pin` sem policy da DEC-021, Leaked Password da Sessão #5).

**Seed final resetado** (`npm run seed -- --reset`): 4 cuidadoras, 11 residentes,
24 medicamentos, 26 horários, 24 lotes. Os dados da conferência (LOTE-JAN, perda
de teste) foram embora com o reset.

## 7. Fora de escopo — confirmado, aguardando sessão própria
- **Categoria "agudo"** (a planilha tem contínuo/agudo; o app tem contínuo/SOS —
  "agudo" ≠ "SOS").
- **Início de tratamento** e **abertura da caixa** (a abertura interage com
  validade de forma não-trivial).
- **Alerta de vencimento próximo** — fora por ora; ajuste manual da casa.
- **"Medicamento da casa"** (SOS sem residente).
- **Escolha manual de lote na perda** — no piloto tudo é FEFO.

## 8. Para o Guilherme
- Revisar este relatório, salvar no Drive, commit + push.
- **Super-administração:** decidi que, quando uma dose excede o físico, o app grava
  a saída cheia e mostra saldo zero (a prateleira não fica negativa). É a mesma
  anomalia que antes aparecia como saldo negativo — só que agora o alarme visual do
  negativo some. Se no piloto você quiser um sinal explícito de "saiu mais do que
  havia", é uma feature própria (relatório de anomalia), não um bug do FEFO.
- **Lote "não identificado":** permiti lote nulo no ajuste-para-cima. Vale conferir
  com a Thais se, no uso, ela sempre tem o código em mãos — se sim, dá para exigir.
- O runbook de go-live e o `limpar-banco` não foram tocados. ⚠️ Antes de qualquer
  dado real da casa: `npm run limpar-banco` e o runbook (`RELATORIO_SESSAO_07.md` §6).
