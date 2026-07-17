# SESSAO_04 — Estoque de ponta a ponta e dose SOS

> Roteiro da quarta sessão de implementação via Claude Code.
> Modelo: Claude Fable 5 (sessão longa e autônoma).
> Criado em: 2026-07-17 | Executada em: 2026-07-17

---

## Pré-requisitos (verificados no início da sessão)

- [x] Sessão #3 concluída e commitada (`e62ca2e`)
- [x] Banco no estado limpo do seed (4 cuidadoras, 11 residentes,
      24 medicamentos, 850 un. de estoque, 0 turnos/administrações)
- [x] 12 migrations remotas espelham `supabase/migrations/`
- [x] MCP do Supabase apontando para o projeto `nami-care`
      (ref `uvkmvaheupziexlunnno`)

## Contexto

Sessão que ataca a dor nº 1 da cliente: a contagem manual semanal de
estoque. Ao final, o ciclo fecha de ponta a ponta: entrada na compra →
baixa automática na dose → saldo visível → alerta de reposição → ajuste
por contagem quando o físico divergir.

## Escopo

### Prioridade 1 — ciclo de estoque

1. **Entradas no ledger**: RPC `registrar_entrada_estoque` (medicamento,
   quantidade com fração 0,5, data default hoje, observação opcional) →
   linha positiva `entrada_compra`, gravando o cuidador do turno ativo.
   Escrita direta em `movimentacoes_estoque` revogada do cliente (RPC como
   único caminho — mesmo padrão das sessões anteriores).
2. **Visão de estoque**: saldo por medicamento reaproveitando a view
   `saldo_estoque` da Sessão 1 (nunca recalculado por fora); lista
   organizada para a cuidadora (decidir organização — DEC); extrato de
   movimentações linha a linha (data, tipo, quantidade, cuidador).
3. **Alerta de reposição — DEC-027, dois métodos por natureza**:
   - Contínuo: `cobertura_dias = saldo ÷ doses_planejadas_por_dia` da
     prescrição ativa; alerta < 5 dias (DEC-012). **Verificado antes da
     fórmula**: `horarios` modela apenas posologia diária (`hora time` +
     `qtd_dose`), então `doses_planejadas_por_dia = SUM(qtd_dose)` dos
     horários ativos — sem normalização semanal (premissa registrada no
     relatório).
   - SOS/PRN: `saldo < estoque_minimo` (novo campo por medicamento,
     definido no cadastro).
   - Sinalização legível ("dura ~4 dias", "abaixo do mínimo") + sugestão
     de quanto comprar para os contínuos.
4. **Ajuste por contagem**: RPC `registrar_ajuste_estoque` — a cuidadora
   informa a quantidade CONTADA; o banco calcula a diferença e grava
   `ajuste_contagem` (nunca sobrescreve saldo). Perda manual
   (`registrar_perda_estoque`) entra no mesmo pacote (quebra, vencimento,
   descarte de metade — DEC-013).

### Prioridade 2 — dose avulsa SOS/PRN (DEC-014)

5. Fluxo fora da ronda: residente → medicamento SOS → quantidade →
   confirmar. Registro em `administracoes` com `horario_id` nulo, cuidador
   do turno ativo; baixa pelo trigger existente (nenhum caminho paralelo).

## Restrições

- Stack: JavaScript apenas (Vite + PWA), Supabase, Railway.
- Toda mudança de schema via migration; nunca SQL avulso.
- Regra de negócio no banco; o cliente só apresenta.
- Ledger imutável: saldo é sempre soma de movimentações.
- Toda ação grava o cuidador do turno ativo.
- Não tocar em ronda/turno (S2) nem gestão (S3) além da integração do
  estoque; tema Sereníssima mantido.

## Critérios de aceite da sessão

- [x] Escrita em `movimentacoes_estoque` só por RPC/trigger (INSERT direto
      revogado; trigger de baixa continua funcionando — SECURITY DEFINER)
- [x] Entrada de compra sobe o saldo; dose na ronda desce; SOS desce
- [x] Tela de estoque mostra saldo = soma manual do ledger (0 divergências
      nos 24 medicamentos ao final do ciclo)
- [x] Alerta dispara nos dois casos: contínuo com cobertura < 5 dias e
      SOS com saldo abaixo do mínimo cadastrado
- [x] Ajuste por contagem corrige divergência proposital sem apagar
      histórico (extrato mostra a linha de ajuste com os dois números)
- [x] Campo "estoque mínimo" exposto no cadastro de medicamento SOS
- [x] Ciclo completo verificado no navegador; migrations com smoke test
      (transação + rollback) antes do apply; `npm run build` OK

## Encerramento

- RELATORIO_SESSAO_04.md; DECISIONS.md com DEC-027+ (novas DEC-028/029
  conforme a implementação); CONTEXT.md e ROADMAP.md atualizados; banco
  resetado ao estado limpo do seed.
