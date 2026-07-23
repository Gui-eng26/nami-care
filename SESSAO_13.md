# SESSÃO #13 — Ver quem tomou: extrato de adesão e dono da dose no estoque

**Data:** 2026-07-23 | **Fase 4 — go-live** | Decisões novas: **DEC-048**, **DEC-049**

---

## Por que esta sessão existe

A Sessão #12 fechou o medicamento da casa. No teste de usabilidade seguinte, o
Guilherme registrou uma dose SOS de **dipirona 500mg da casa para a Alzira**. O
dado foi gravado certo: a adesão da Alzira somou +1 SOS e o extrato da dipirona
registrou a baixa. Mas **nenhuma tela do app mostra que foi a Alzira quem tomou
aquela dipirona**, nem que a Alzira tomou dipirona. O relatório de adesão devolve
só agregados — dá para saber que houve 3 não tomadas no período, não *quais*.

**Nada disso exige mudança de schema.** `administracoes` já grava `prevista_em`,
`registrado_em`, `status`, `qtd`, `cuidador_id`, `observacao` e `idoso_id`
(DEC-045); `movimentacoes_estoque.administracao_id` já existe e é UNIQUE. Esta
sessão é **inteiramente camada de leitura e apresentação**: nenhuma coluna nova,
nenhum trigger, nenhuma escrita, nenhuma linha do ledger alterada.

**Nada do caminho de go-live é tocado.** O banco segue com o cenário de
demonstração da Sessão #9; o `npm run limpar-banco` (passo 5 do runbook) continua
pendente e obrigatório antes de qualquer dado real.

---

## Parte 1 — Fonte única da adesão (`fn_doses_adesao`) — DEC-048

**Problema:** `relatorio_adesao` conta as categorias com um `where` escrito dentro
dela. Se a listagem de detalhe nascer como RPC separada com `where` próprio,
passam a existir duas implementações da mesma pergunta. No dia em que divergirem,
a tela diz "4 não tomadas" e lista 3 — e o relatório perde a confiança da
cuidadora. O projeto já resolveu esse padrão uma vez: a ronda consome
`doses_do_turno` e não recalcula slots.

**Migration `20260723000100_adesao_fonte_unica.sql`:**

1. `public.fn_doses_adesao(p_inicio date, p_fim date, p_idoso_id uuid default null)`
   — `returns table`, `stable`, `security invoker`, `set search_path = ''`,
   `revoke execute from public, anon`. Uma linha por `administracoes` no período.

   Colunas: `administracao_id`, `categoria`, `idoso_id` (dono resolvido),
   `medicamento_id`, `nome_medicamento`, `dosagem`, `forma_farmaceutica`,
   `eh_da_casa`, `qtd`, `prevista_em`, `registrado_em`, `cuidador_nome`,
   `observacao`.

   Mapeamento de `categoria` — exatamente as chaves que `relatorio_adesao` já
   devolve e que `CATEGORIAS` já usa em `Adesao.jsx`, para não existir camada de
   tradução entre banco e tela:

   | condição | categoria |
   |---|---|
   | `horario_id is null` | `sos` |
   | `status = 'tomado_no_horario'` | `no_horario` |
   | `status = 'tomado_atrasado'` | `atrasada` |
   | `status = 'recusado'` | `recusada` |
   | `status = 'nao_tomado'` | `nao_tomada` |
   | `status = 'pendente'` | `nao_apurada` |

   **A regra de período assimétrica mora aqui e só aqui:** agendada filtra por
   `prevista_em`, SOS por `registrado_em` (SOS não tem `prevista_em` —
   DEC-014/023). Fronteira de dia no fuso da casa via `fn_fuso_casa()` (DEC-023).
   Dono resolvido = `coalesce(a.idoso_id, m.idoso_id)` (DEC-045/046), aplicado
   dentro da função, inclusive no filtro `p_idoso_id`.

   **Não vira `security definer`:** `relatorio_adesao` e `detalhe_adesao` são
   `security invoker`. A cuidadora autenticada já tem `select` em
   `administracoes` pelo RLS — a função não abre nada novo.

2. `relatorio_adesao(date, date, uuid)` reescrita com `create or replace`,
   **mesma assinatura e mesmo JSON campo por campo**, contando por
   `count(*) filter (where categoria = ...)` sobre `fn_doses_adesao`. O trecho de
   `pendentes` (via `doses_do_turno` no turno aberto) e o cálculo dos percentuais
   ficam literalmente como estão. **Refactor puro.**

`pendentes` **fica FORA da função** — são doses que ainda não têm linha em
`administracoes`, fonte estruturalmente diferente.

**Fora do escopo:** criar/remover/renomear categoria; mudar denominador ou regra
de percentual; tocar `doses_do_turno`, `fechar_turno` ou a faixa de aviso de
`pendentes`; qualquer alteração de schema.

---

## Parte 2 — Extrato de adesão por categoria — DEC-048

**Migration `20260723000200_detalhe_adesao.sql`:**

`public.detalhe_adesao(p_inicio date, p_fim date, p_idoso_id uuid, p_categoria text)`
→ `jsonb`, `stable`, `security invoker`, `set search_path = ''`,
`revoke execute from public, anon`.

- Valida período (mesma regra de `relatorio_adesao`), `p_idoso_id not null`
  (`residente_obrigatorio`), residente existente (`residente_nao_encontrado`) e
  `p_categoria` contra a lista fechada das 6 chaves (`categoria_invalida`).
- Devolve `{ ok, categoria, total, limite: 200, truncado, doses: [...] }`, onde
  `total` é a contagem real no período **antes** do corte.
- **Teto de 200 linhas**, mais recentes primeiro, ordenadas pelo **instante de
  referência** desc (`prevista_em` nas agendadas, `registrado_em` no SOS).
- O sentinela "Da Casa" não precisa de caso especial: nenhuma dose resolve para
  ele, a lista vem naturalmente vazia.

**Tela `src/pages/Adesao.jsx`:**

- O detalhe existe **apenas na visão por residente**. Com residente selecionado,
  cada linha de `CATEGORIAS` e a linha "Doses SOS no período" viram botão. Sem
  residente ("Toda a casa"), permanecem estáticas com a dica *"selecione um
  residente para ver as doses"*.
- Ao abrir, o card mostra a lista com botão de voltar, no padrão visual de
  `ExtratoMovimentacoes` (`lista-extrato`, `extrato-linha`), reaproveitando
  classes do `index.css`.
- Conteúdo por categoria: No horário / Recusadas / Não tomadas → medicamento +
  dosagem · `prevista_em` · qtd · cuidadora. Atrasadas → idem, mostrando
  **previsto × registrado**. Pendente (não apurado) → marca de resolução em lote
  (DEC-034). SOS → `registrado_em` · qtd · cuidadora · chip **"Da casa"** quando
  `eh_da_casa`.
- `observacao` vira linha secundária quando existir; quando não, a linha
  simplesmente não é renderizada — sem placeholder.
- **Truncamento sempre avisado em tela**, nunca em silêncio.
- Trocar de residente, de período ou de atalho **fecha** o detalhe aberto.
- Zero cálculo no cliente.

**A faixa amarela de `dados.pendentes`** (doses do turno aberto sem tratativa)
não é categoria e **não ganha clique** — fica exatamente como está.

**Fora do escopo:** detalhe na visão da casa; exportação/impressão/
compartilhamento; qualquer mudança no cálculo da adesão; alteração no modal da
ronda.

---

## Parte 3 — Dono da dose no estoque + leitura unificada do ledger — DEC-049

**Problema (a):** no extrato de um medicamento **da casa**, a baixa mostra data,
hora, cuidadora, lote e validade — mas não **quem tomou**, que é justamente o que
a DEC-045 passou a gravar.

**Problema (b):** o extrato existe hoje em **duas telas que leem o ledger por
caminhos diferentes** — `FichaEstoque` lê a tabela direto via PostgREST (últimas
50, sem período, rotulando por **`tipo`**) e `ExtratoMovimentacoes` lê pela RPC
`extrato_medicamento` (com período e filtro, rotulando por **`subtipo`**). Um
ajuste de contagem para baixo já lê "Ajuste de contagem" numa tela e "Ajuste de
contagem (a menos)" na outra. E pelo caminho direto do PostgREST resolver o
`coalesce` do dono exigiria a regra **em JavaScript**, contra a convenção do
projeto.

**Decisão: Opção A — unificar.**

**Migration `20260723000300_extrato_dono_da_dose.sql`:**

1. `drop function` da assinatura antiga de 4 parâmetros obrigatórios (para não
   ficarem duas sobrecargas ambíguas) + `create or replace` de
   `extrato_medicamento(p_medicamento_id uuid, p_inicio date default null,
   p_fim date default null, p_subtipos text[] default null)`, preservando tudo o
   que ela já faz (subtipo derivado pelo sinal, filtro combinável, `lotes` da
   DEC-043, bloco `medicamento`).
   - **Período opcional:** ambos nulos = sem recorte de data, **últimas 50** (o
     comportamento atual da ficha). Ambos preenchidos = como hoje. **Um só nulo =
     `periodo_invalido`.**
   - Campo novo por movimentação: **`residente`** (nome ou `null`), preenchido só
     quando `administracao_id is not null` **e** `subtipo = 'dose'` **e** o
     medicamento é da casa. Nome vindo do dono resolvido
     `coalesce(a.idoso_id, m.idoso_id)`.
2. `src/pages/Estoque.jsx` (`FichaEstoque`): `carregarExtrato` passa a chamar a
   RPC com período nulo; lista renderizada com `ROTULO_SUBTIPO`, mantendo
   aparência atual (lote, motivo, cuidadora, sinal +/− e cores). **Não tocar** em
   saldo, lotes na prateleira, botões nem modais; a rechamada após cada RPC de
   movimentação continua igual.
3. `src/pages/ExtratoMovimentacoes.jsx`: exibir `Residente: X` quando o campo
   vier preenchido.
4. `src/lib/formato.js`: remover `ROTULO_MOVIMENTACAO` (fica sem uso).

**Rótulos exatos:** `Cuidadora: Ana` e `Residente: Alzira`.

**Em medicamento já vinculado a um residente o campo não aparece** — é
redundante, o cabeçalho da tela já diz de quem é. Perda por recusa, compra,
ajuste e perda avulsa **nunca** mostram residente.

**Fora do escopo:** alterar ações de compra/ajuste/perda; mexer em lotes, FEFO ou
consolidado por catálogo; qualquer escrita no ledger.

---

## Parte 4 — Documentação

- **`DECISIONS.md`:** DEC-048 (fonte única da adesão e extrato por categoria,
  estende DEC-030/046) e DEC-049 (dono da dose visível no extrato e leitura
  unificada do ledger, estende DEC-036/043/045).
- **Alerta de alergia:** vira **feature futura no backlog**, explicitamente **não
  bloqueante do go-live** — decisão do Guilherme. Sai da lista de itens em aberto
  do MVP no `CONTEXT.md`.
- **`CONTEXT.md`:** fechar os checkboxes de "revisar relatório, salvar no Drive,
  commit + push" das Sessões **05, 05_5, 06, 07, 08 e 12** (já commitados e
  empurrados — estão desatualizados, não pendentes); adicionar o bloco da Sessão
  #13; **manter intactas** as pendências reais de go-live.
- **`ROADMAP.md`:** refletir a Sessão #13 e o backlog de alergia.

---

## Critério de pronto

1. **Invariante da fonte única:** para cada uma das 6 categorias, em vários
   períodos (hoje, 7 dias, mês) e para cada residente ativo, `total` de
   `detalhe_adesao` == `qtd` da categoria em `relatorio_adesao`. **0 divergências.**
2. **Refactor provado:** JSON de `relatorio_adesao` **idêntico** antes e depois,
   para a casa e para cada residente, nos três períodos — comparando o jsonb
   inteiro, não campo a campo escolhido a dedo.
3. Bateria SQL completa em `begin/rollback`: dose SOS da casa, dose SOS própria,
   dose agendada, status `pendente`, residente sem dose no período.
4. **375px, ponta a ponta:** com a Alzira selecionada, cada uma das 6 linhas abre
   lista coerente; a dose SOS de dipirona **da casa** aparece na lista de SOS dela
   com o chip "Da casa"; na visão "Toda a casa" nada é clicável.
5. **Ficha do medicamento da casa:** a linha da dose mostra `Cuidadora: … ·
   Residente: Alzira`. **Ficha de medicamento próprio:** nenhuma menção a residente.
6. Ficha e aba "Extrato de movimentações" no mesmo medicamento: **mesmas linhas,
   mesmos rótulos, mesmos lotes.**
7. **Ponto de risco a conferir de propósito:** a ronda continua registrando dose
   agendada normalmente e o fluxo SOS (residente → medicamento → quantidade)
   continua intacto — nenhuma das duas foi tocada, mas ambas dependem de tabelas
   que esta sessão passou a ler de outro jeito.
8. `npm run build` OK; advisors sem nada novo em espécie; seed resetado ao final.
