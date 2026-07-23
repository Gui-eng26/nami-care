# RELATÓRIO — Sessão #13

**Data:** 2026-07-23
**Fase:** 4 — Go-live (piloto ainda não iniciado)
**Decisões novas:** DEC-048, DEC-049
**Migrations novas:** `20260723000100`, `20260723000200`, `20260723000300`
**Mudanças de schema:** **nenhuma**

---

## 1. Por que esta sessão existiu

A Sessão #12 entregou o medicamento da casa. No teste de usabilidade seguinte, o
Guilherme registrou uma dose SOS de **dipirona 500 mg da casa para a Alzira**. O
dado foi gravado corretamente: a adesão da Alzira somou +1 SOS, o extrato da
dipirona registrou a baixa. Mas **nenhuma tela do app mostrava que foi a Alzira
quem tomou aquela dipirona**, nem que a Alzira tomou dipirona. O relatório de
adesão devolvia só agregados: dava para saber que houve 3 não tomadas no período,
nunca *quais*.

Sem o "quais", não há como agir sobre uma não adesão — que é o motivo de existir
do relatório.

**A observação central:** nada disso exigia mudança de schema. Todo o dado
necessário já estava gravado desde a DEC-045. A sessão foi **inteiramente camada
de leitura e apresentação**: nenhuma coluna nova, nenhum trigger, nenhuma escrita,
nenhuma linha do ledger alterada. **Nada do caminho de go-live foi tocado.**

---

## 2. O que foi entregue

### 2.1 Fonte única da adesão (DEC-048)

`relatorio_adesao` contava as categorias com um `where` escrito dentro dela. O
detalhe precisava **listar exatamente as doses que o relatório conta**. Se
nascesse como RPC separada com `where` próprio, passariam a existir **duas
implementações da mesma pergunta** — e no dia em que divergissem, a tela diria "4
não tomadas" e listaria 3. O relatório inteiro perderia a confiança da cuidadora.

O projeto já resolveu esse padrão uma vez: a ronda consome `doses_do_turno` e não
recalcula slots. Nasce o equivalente para a adesão:

**`fn_doses_adesao(p_inicio, p_fim, p_idoso_id)`** — uma linha por administração
no período. Passam a morar num lugar só:

- a **regra de período assimétrica**: agendada filtra por `prevista_em`, SOS por
  `registrado_em` (SOS não tem `prevista_em` — DEC-014/023). Antes estava
  espalhada em dois `select`;
- o **dono resolvido** `coalesce(a.idoso_id, m.idoso_id)` (DEC-045/046);
- o mapeamento status → categoria, nas **mesmas chaves** que o JSON já devolvia e
  que a tela já usava — sem camada de tradução entre banco e tela.

`relatorio_adesao` foi reescrita para contar em cima dela, com **assinatura e JSON
idênticos, campo por campo**.

**Fora da função, de propósito:** `pendentes` (doses vencidas sem tratativa no
turno aberto). São doses que ainda **não têm linha em `administracoes`** — fonte
estruturalmente diferente, que continua vindo de `doses_do_turno`.

### 2.2 Extrato de adesão por categoria (DEC-048)

**`detalhe_adesao(p_inicio, p_fim, p_idoso_id, p_categoria)`** é a **mesma
`fn_doses_adesao`, filtrada** — não tem `where` próprio. Por construção, o que
lista é o que o relatório conta.

- **Só na visão por residente.** A RPC exige `p_idoso_id`
  (`residente_obrigatorio`); em "Toda a casa" as barras não são clicáveis e uma
  dica curta explica por quê. Uma lista de centenas de doses de onze pessoas não
  ajuda a agir sobre nenhuma.
- **As 5 categorias existentes + SOS.** Nenhuma categoria nova; nenhuma mudança
  no cálculo da adesão. Abrem mesmo com zero — a lista vazia é resposta, não um
  beco.
- **Teto de 200 linhas**, mais recentes primeiro, ordenadas pelo instante de
  referência (a mesma assimetria do período governando a ordem). `total` traz a
  contagem real **antes** do corte e `truncado` diz que houve corte: **a tela
  avisa sempre**. Uma lista que mente sobre o próprio tamanho é pior que lista
  nenhuma.
- A categoria decide o que a linha diz: **atrasada mostra previsto × registrado**
  ("previsto 21/07, 08:00, registrado 10:03"), porque o buraco entre os dois é a
  informação; "pendente" marca que veio da resolução em lote (DEC-034); SOS leva
  o chip **"Da casa"**. `observacao`, quando existe, vira linha secundária —
  quando não, a linha não é renderizada, sem placeholder.
- Trocar residente, período ou atalho **fecha** o detalhe aberto.

A faixa amarela de `pendentes` no rodapé do card **não é categoria e não ganhou
clique** — ficou exatamente como estava.

### 2.3 Dono da dose no estoque + leitura unificada do ledger (DEC-049)

Duas coisas ligadas pela mesma causa.

**(a)** No extrato de um medicamento da casa, a baixa mostrava data, hora,
cuidadora, lote e validade — mas não **quem tomou**.

**(b)** O extrato existia em **duas telas que liam o ledger por caminhos
diferentes**: `FichaEstoque` lia `movimentacoes_estoque` direto pelo PostgREST
(últimas 50, sem período, rotulando por **`tipo`**) e `ExtratoMovimentacoes` lia
pela RPC (com período e filtro, rotulando por **`subtipo`**). Isso já produzia
divergência: um ajuste de contagem para baixo lia "Ajuste de contagem" numa tela
e "Ajuste de contagem (a menos)" na outra. E impedia (a) — pelo caminho direto,
resolver o `coalesce` do dono exigiria a regra **em JavaScript**.

**Decisão: unificar.** A ficha passou a consumir `extrato_medicamento`. Uma
leitura só do ledger; a inconsistência de rótulo morreu junto e
`ROTULO_MOVIMENTACAO` saiu do `formato.js` por ficar sem uso.

Para atender a ficha, a RPC ganhou **período opcional**: ambos nulos = sem recorte
de data, **últimas 50**; ambos preenchidos = como antes; **um só nulo =
`periodo_invalido`** (meio período é engano de chamada, não intenção). A
assinatura antiga, de quatro parâmetros obrigatórios, foi removida com
`drop function` antes do replace.

**Campo novo `residente`**, preenchido **só** quando a movimentação é baixa por
dose tomada (`subtipo = 'dose'`, com `administracao_id`) **e** o medicamento é da
casa. Em medicamento vinculado a um residente seria redundante — o cabeçalho já
diz de quem é. Compra, ajuste, perda e perda por recusa nunca mostram residente.
Rótulos exatos: **`Cuidadora: Ana`** e **`Residente: Alzira`**.

---

## 3. Verificação

### 3.1 Refactor provado (critério 2)

JSON de `relatorio_adesao` capturado **antes** da mudança para a casa e cada
residente, em três períodos (hoje, 7 dias, mês), e comparado com o jsonb **inteiro**
depois:

| comparações | divergências |
|---|---|
| **39** | **0** |

### 3.2 Invariante da fonte única (critério 1)

`total` de `detalhe_adesao` × `qtd` da categoria em `relatorio_adesao`, para as 6
categorias × todos os residentes × 3 períodos:

| combinações | detalhe com erro | divergências |
|---|---|---|
| **216** | **0** | **0** |

Repetido depois do reset do seed, sobre o cenário recém-gerado: **216
combinações, 0 divergências**.

### 3.3 Bateria SQL em `begin/rollback` (critério 3)

**20 casos, 20 verdes.** Cobertura:

| bloco | caso |
|---|---|
| A | dose SOS **da casa**: categoria `sos`, dono = quem tomou, `eh_da_casa`, `prevista_em` nulo, observação; aparece no detalhe dela com o chip; **não** aparece no sentinela; **aparece com o nome dela no extrato do estoque** |
| B | dose SOS **própria**: categoria `sos`, sem chip; extrato do medicamento **sem** residente |
| C | dose **agendada**: categoria `atrasada`, dono pelo medicamento, `prevista_em` preenchida |
| D | status **`pendente`** → categoria `nao_apurada` (gravado pela mesma porta da DEC-034) |
| E | **residente sem dose** no período: as 6 categorias vazias, sem erro |
| F | invariante detalhe × relatório nas 6 categorias |
| G | 4 validações de argumento: `residente_obrigatorio`, `categoria_invalida`, `periodo_invalido`, `residente_nao_encontrado` |

Contagens antes e depois do `rollback` idênticas (207 administrações, 219
movimentações) — nenhum resíduo.

Verificações adicionais de `extrato_medicamento`: medicamento próprio com **0**
linhas trazendo residente; período com um só extremo (início ou fim) e período
invertido devolvendo `periodo_invalido`; período preenchido continuando a
funcionar.

### 3.4 Navegador a 375px (critérios 4, 5, 6, 7)

- **Toda a casa:** nenhuma categoria clicável; dica *"Selecione um residente para
  ver quais doses formam cada número."*
- **Alzira, últimos 7 dias:** as 6 listas abertas e coerentes —
  20 + 1 + 1 + 1 + 0 = 23 = total planejadas. A **dipirona da casa aparece na
  lista de SOS dela com o chip "Da casa"**, com cuidadora e observação. Atrasadas
  mostrando *"previsto 21/07, 08:00, registrado 10:03"*. "Pendente (não apurado)"
  conferida com uma linha temporária, exibindo a nota de resolução em lote (linha
  removida em seguida; contagens de volta a 207/219).
- **Ficha da dipirona (da casa):** `23/07, 09:19 — Cuidadora: Beatriz Lima ·
  Residente: Alzira Nogueira`. A compra na mesma ficha, sem residente.
- **Ficha da Losartana (própria da Alzira):** nenhuma menção a residente em
  nenhuma linha, inclusive na perda por recusa.
- **Ficha × aba "Extrato de movimentações" no mesmo medicamento:** mesmas três
  linhas, mesmos rótulos, mesmos lotes, mesmo residente.
- **Ponto de risco (critério 7), exercitado de propósito na tela:** criei um
  horário vencido há 10 min, a dose apareceu na ronda, registrei "Tomou" e ela foi
  para "Tratadas neste turno". Em seguida, fluxo SOS completo (Alzira → dipirona
  da casa → quantidade → observação), com a mensagem *"Dose SOS registrada:
  Dipirona 500 mg para Alzira Nogueira (estoque da casa)"*. **Ambos intactos.**

### 3.5 Build, advisors, seed (critério 8)

- `npm run build` OK.
- Advisors: só as espécies pré-existentes (RPCs `security definer` intencionais,
  `tentativas_pin` sem policy, leaked-password do plano Free). **As três funções
  desta sessão são `security invoker` e não aparecem** — nenhuma espécie nova.
- Seed resetado ao final (`npm run seed-demo`), cenário de demonstração
  recomposto: 241 doses de ronda + 6 SOS, turno aberto, lacuna de pendências.

---

## 4. Achado de passagem

**`npm run seed-demo` estava quebrado desde a Sessão #11.** O `seed-demo.js`
chamava `registrar_entrada_estoque` sem `p_validade`, que a DEC-041 tornou
obrigatória — o seed base rodava, e o cenário de demonstração abortava no meio
("Could not find the function ... in the schema cache"). Só apareceu agora porque
a Sessão #12 resetou com o seed simples, não com o de demonstração.

Corrigido com o mínimo: um helper `validadeDemo()` (10 meses à frente, no espírito
do `validadeSeed` do seed base) e o parâmetro na chamada. Sem isso, o critério de
"seed resetado ao final" não era alcançável.

---

## 5. O que NÃO foi feito (deliberadamente)

- Nenhuma mudança de schema, escrita ou regra de negócio.
- Detalhe de adesão na visão da casa; exportação, impressão ou compartilhamento.
- Qualquer alteração no cálculo da adesão, no denominador, nas categorias, em
  `doses_do_turno`, `fechar_turno` ou na faixa de `pendentes`.
- Residente em compra, ajuste, perda ou perda por recusa; qualquer mexida em
  lotes, FEFO ou consolidado por catálogo.
- **Alerta de alergia:** por decisão do Guilherme, virou **feature futura do
  backlog, explicitamente não bloqueante do go-live**, e saiu da lista de itens em
  aberto do MVP.

---

## 6. Pendências

- **Nada do go-live mudou.** O `npm run limpar-banco` (passo 5 do runbook)
  continua **obrigatório antes de qualquer dado real**, e os passos 4–8 seguem
  pendentes com a Thais.
- **Guilherme:** revisar este relatório, salvar no Drive, **commit + push** (o
  commit é seu, como combinado).
- O Guilherme mencionou um **segundo ajuste**, sem relação com este, a trazer
  antes do go-live. Nada foi presumido sobre ele e **nenhum gancho foi deixado no
  código** para acomodá-lo.

---

## 7. Arquivos tocados

**Migrations (novas):**
- `supabase/migrations/20260723000100_adesao_fonte_unica.sql`
- `supabase/migrations/20260723000200_detalhe_adesao.sql`
- `supabase/migrations/20260723000300_extrato_dono_da_dose.sql`

**Código:**
- `src/pages/Adesao.jsx` — categorias clicáveis + componente `DetalheAdesao`
- `src/pages/Estoque.jsx` — `FichaEstoque` passa a consumir a RPC
- `src/pages/ExtratoMovimentacoes.jsx` — `Residente:` na linha
- `src/lib/formato.js` — `ROTULO_MOVIMENTACAO` removido, `horaLocal` acrescentada
- `src/lib/erros.js` — `residente_obrigatorio`, `categoria_invalida`
- `src/index.css` — `.adesao-categoria`, `.adesao-seta`
- `scripts/seed-demo.js` — correção do `p_validade`

**Documentação:** `SESSAO_13.md`, `RELATORIO_SESSAO_13.md`, `DECISIONS.md`
(DEC-048/049), `CONTEXT.md`, `ROADMAP.md`.
