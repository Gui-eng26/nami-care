# Relatório da Sessão #9 — Dados de demonstração (2026-07-21)

> Sessão curta e descartável, de DADOS, não de produto. Nenhuma tela, RPC,
> trigger, view, migration ou arquivo de `src/` foi alterado.
> Entregável: `npm run seed-demo` + o banco de TESTE povoado para a conversa
> com a Thais.

---

## 1. O que foi entregue

| Arquivo | O que é |
| --- | --- |
| `scripts/seed-demo.js` | **novo** — gera o cenário de demonstração sobre o seed base |
| `scripts/seed.js` | flag `--demo` (mesma estrutura de `--com-historico`) |
| `package.json` | script `seed-demo` |

## 2. Como rodar (e rerodar)

```bash
npm run seed-demo
```

Depois, **recarregue o app no celular/navegador** (F5 ou puxar para atualizar):
o turno aberto é recriado a cada execução, e o app relê o turno do banco ao
carregar (invariante da Sessão #8).

O script é **reexecutável e recalcula a janela para o novo `now()`**: se a
conversa atrasar, escorregar ou se estender, rodar de novo recompõe o cenário
inteiro em torno do horário da nova execução. Ele sempre parte do zero (reset do
seed) — não acumula.

## 3. O que o cenário cria

Sobre a base de sempre (4 cuidadoras, 11 residentes, 24 medicamentos, catálogo,
estoque):

1. **Histórico de adesão** — D-6 a D-1, um turno por dia aberto e fechado pelas
   RPCs, com os quatro status distribuídos (≈82% no horário) + doses SOS. É o
   que faz a aba Adesão mostrar percentuais reais, na casa e por residente.
2. **Doses na janela de AGORA** — 16 horários novos criados pela RPC
   `criar_horario` (DEC-038, dentro de turno aberto), em deslocamentos de
   **−85 min a +110 min relativos ao instante da execução** — nunca horários
   fixos. Resultado na ronda: algumas **já tratadas**, pelo menos uma
   **atrasada** (em destaque), várias **na hora** (dentro da tolerância de 30
   min, DEC-023) e um estoque de doses que vai vencendo ao longo das ~2 h
   seguintes. Dá para tratar uma dose ao vivo a qualquer momento da janela.
3. **Turno aberto agora** — Débora Santos (PIN 4444), desde as 06:00 de hoje.
4. **Pendências entre turnos** — lacuna deliberada em **D-3**: o turno daquele
   dia encerra ~2 h antes da hora atual e as doses do resto do dia não são
   lançadas. Dentro do teto de 5 dias da DEC-033 → a **faixa vermelha aparece
   com contagem** (25 doses na execução conferida) e as doses são tratáveis
   individualmente ou em lote. **Não zere essas pendências antes da demo.**
5. **Reforço de estoque** pelo ledger (`registrar_entrada_estoque`) para os 7
   dias de histórico + a janela não zerarem nenhum saldo.

## 4. Como as regras foram respeitadas

Toda escrita passa pelas RPCs reais (`abrir_turno`/`fechar_turno`,
`criar_horario`, `registrar_entrada_estoque`) e pelos triggers (baixa de
estoque, exigência de turno aberto). Os únicos ajustes diretos por service role
são de **data** — mesma tolerância que o `seed-historico` já documenta, e pelo
mesmo motivo (o passado não pode ser encenado em tempo real):

- `turnos.inicio/fim` recuados para o dia a que cada turno se refere;
- `horarios.criado_em` recuado para antes do primeiro turno — a fila de
  pendências ignora, por construção, slot anterior à criação do horário.

Os recuos acontecem **depois** de todos os turnos fecharem: recuar antes faria o
`fechar_turno` enxergar as pendências que estamos criando de propósito.

## 5. Critério de pronto — conferido no navegador a 375px

| # | Item | Resultado |
| --- | --- | --- |
| 1 | Ronda com movimento na janela atual | ✅ 1 atrasada (15:18, em destaque), 4 na hora (15:31–15:52), 20 tratadas no turno |
| 2 | Faixa "Pendências entre turnos" vermelha, contagem > 0 | ✅ **25**, sábado 18/07, agrupadas por residente |
| 3 | Aba Adesão com percentuais e categorias reais | ✅ casa: 85% / 10% / 5% (hoje); Iracema Barros / 7 dias: 70,6% no horário, 29,4% recusadas, 1 SOS |
| 4 | Janela se sustenta ~1h30+ | ✅ 8 doses ainda a vencer nas ~2 h seguintes |
| 5 | Reexecução recompõe com nova janela | ✅ rodado duas vezes; janela recalculada |
| 6 | `npm run build` OK, `src/`/migrations intocados | ✅ |

Console do navegador limpo. Nenhuma decisão de produto nova — nenhuma DEC criada.

## 6. ⚠️ Lembrete — a demo NÃO é o piloto

O banco de teste ficou **povoado de propósito** (ao contrário das sessões de
código, que resetam o seed no fim). São dados FICTÍCIOS.

**Depois da conversa com a Thais, o runbook de go-live continua valendo
inalterado** (`RELATORIO_SESSAO_07.md` §6): antes de qualquer dado real é
preciso rodar **`npm run limpar-banco`** e seguir com o bootstrap da Thais
(`npm run criar-admin`) e o cadastro real pelo catálogo. Não comece o piloto em
cima deste cenário.
