# SESSÃO 11 — Rastreamento de estoque por lote e validade (FEFO)

> Roteiro de entrada. Mudança estrutural no modelo de estoque: o saldo deixa de
> ser só um número e passa a ser rastreado por lote, com validade, saída
> automática por FEFO. Levantada com a Thais para aposentar a planilha de Excel.
> Anterior: SESSAO_10.md / RELATORIO_SESSAO_10.md

---

## Antes de começar

1. Fonte da verdade: BRIEFING.md, DECISIONS.md (até DEC-039 na abertura),
   CONTEXT.md, ROADMAP.md, RELATORIO_SESSAO_10.md. Em conflito com a sua memória,
   os arquivos prevalecem.
2. Banco: exclusivamente o projeto nami-care (ref uvkmvaheupziexlunnno), via
   .mcp.json.
3. Esta é a maior mudança estrutural desde o MVP. Registrar as decisões de
   produto como **DEC-040+** (a última era DEC-039). Criar SESSAO_11.md e
   RELATORIO_SESSAO_11.md no padrão das anteriores.
4. Não tocar no runbook de go-live. Banco segue com seed de teste; `npm run seed
   -- --reset` recompõe a base. **Não há dados reais da Thais no banco — ela ainda
   não usa o app.** Portanto NÃO há backfill de saldo pré-existente a tratar.

## Contexto e objetivo

Hoje o estoque é um saldo numérico por medicamento: o ledger
(movimentacoes_estoque) soma entradas e saídas e a view saldo_estoque deriva um
número. O sistema sabe *quanto* tem, não *quais* unidades, de que lote, com que
validade.

A Thais controla isso em Excel: cada entrada de medicamento (compra, ou remédio
que o residente traz de casa) é registrada com data de entrada, lote, validade e
quantidade. A enfermeira **sempre abre o lote de validade mais próxima** — a casa
já opera FEFO na bancada. O objetivo é o app refletir isso: registrar
lote/validade na entrada e abater automaticamente por FEFO na saída.

### Duas verdades sincronizadas
- **Lotes** = verdade do *saldo físico* na prateleira (lote X: N unidades, vence
  em dd/mm).
- **movimentacoes_estoque (ledger)** = verdade do *histórico e da cobertura*
  (extrato, cobertura/adesão, alertas). Continua intacto.

Toda RPC de entrada/saída escreve nos dois, na mesma transação (atômico).
saldo_estoque passa a derivar da soma dos lotes vivos (e deve bater com o ledger
— invariante a testar).

## Parte 1 — Modelo de lotes (schema) — DEC-040
Tabela lotes_estoque (medicamento_id, lote, validade, quantidade_inicial,
saldo_atual meio-em-meio, data_entrada, origem, criado_em). Não há agrupamento.
Vínculo movimentação↔lote 1-para-N (tabela de ligação ou linha por lote).

## Parte 2 — Entradas com lote e validade — DEC-041
Três caminhos ("+ Medicamento" / recompra / ajuste-para-cima) capturam lote +
validade + quantidade. As RPCs criam a linha em lotes_estoque junto com a
movimentação. Origem (compra vs. remanescente) grava também no lote.

## Parte 3 — Saídas por FEFO automático — DEC-042
Três saídas (dose, ajuste-para-baixo, perda) abatem por FEFO — validade mais
próxima primeiro, varrendo múltiplos lotes. Ronda intocada (baixa automática e
silenciosa). Empate de validade → data_entrada mais antiga. Sobras ficam
visíveis; descarte é manual. Sem alerta de vencimento nesta sessão.

## Parte 4 — Lote e validade visíveis — DEC-043
Estoque atual por residente exibe lote e validade por medicamento (próximo a
vencer em destaque). Extrato indica o(s) lote(s) de cada saída. Tema Sereníssima,
375px.

## Restrições
- JavaScript apenas; schema/regra via migration. Regra no banco; cliente
  apresenta. Atomicidade é requisito. Ronda permanece intocada (DEC-008).
  movimentacoes_estoque continua a fonte do extrato/cobertura/adesão.
  Meio-em-meio (0,5) preservado. Sem alerta de vencimento automático.

## Fora do escopo
Categoria "agudo"; início de tratamento / abertura de caixa; alerta de vencimento
próximo; "medicamento da casa" (SOS sem residente); escolha manual de lote na
perda.

## Critério de pronto
Cadastro/recompra/ajuste-para-cima pedindo lote+validade criando lote+movimentação
juntos; duas entradas com validades diferentes = dois lotes ordenados; dose menor
abate só do lote da frente; dose maior varre o próximo; caso 0,5+0,5;
ajuste-baixo e perda por FEFO; estoque atual e extrato com lote; **invariante
sum(lotes)==ledger**; `npm run build` sem erro e sem regressão.
