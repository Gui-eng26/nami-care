# Nami Care

Assistente de gestão de medicação para casas de repouso de pequeno porte.

Sistema web (PWA) que organiza a rotina de medicação em **rodadas por horário**,
mantém o **estoque atualizado automaticamente** a cada dose administrada e gera
**relatórios de adesão e de reposição** — substituindo a contagem manual semanal
de medicamentos por uma conferência de exceções.

> Projeto derivado do know-how da [Nami Life](https://github.com/Gui-eng26/Nami_life)
> (assistente de adesão via WhatsApp), com arquitetura própria para o contexto
> multiusuário de uma casa de repouso.

## O problema

Em casas de repouso pequenas, o controle de medicação é manual: planilhas ou
cadernos, contagem física de estoque toda semana e nenhuma trilha de quem
administrou o quê. O piloto deste projeto atende uma casa real com 4 cuidadores
e 11 idosos, onde a contagem semanal de estoque foi apontada como a maior dor
operacional.

## Como funciona

- **Rodada de medicação** — em vez de alarmes individuais, o app consolida todos
  os medicamentos devidos em cada horário numa única fila. O cuidador percorre a
  lista confirmando dose a dose.
- **Turno com PIN** — o app roda no celular da casa; cada cuidador assume o turno
  com seu PIN e todas as ações ficam vinculadas a ele (trilha de auditoria).
- **Fechamento de turno** — o turno só encerra quando todas as doses do período
  receberam tratativa (tomada no horário, tomada atrasada, não tomada ou recusada).
- **Estoque como livro-razão** — o saldo nunca é sobrescrito: é a soma de
  movimentações (administração, compra, ajuste de contagem, perda). Isso permite
  relatório de divergência, previsão de ruptura e alerta de reposição
  (cobertura < 5 dias).
- **Dose avulsa (SOS)** — medicamentos "se necessário" são registrados fora das
  rodadas, mantendo a acurácia do estoque.

## Funcionalidades do MVP

1. Login / assumir turno (PIN por cuidador)
2. Cadastro de idosos
3. Cadastro de medicamentos por idoso (dosagem, forma farmacêutica, posologia, tipo contínuo/SOS)
4. Cadastro e edição de horários por medicamento
5. Rodada de medicação (fila do horário corrente + doses atrasadas em destaque)
6. Confirmação de dose com tratativa obrigatória antes do fechamento do turno
7. Movimentações manuais de estoque (compra, ajuste por contagem, perda)
8. Dose avulsa (SOS/PRN) com baixa de estoque
9. Ficha do idoso com histórico
10. Relatório de adesão por idoso
11. Relatório de estoque com previsão de ruptura e sugestão de compra

## Stack

| Camada | Tecnologia |
|---|---|
| Frontend | React (PWA, mobile-first) |
| Backend / BD | Supabase (Postgres, Auth, Row Level Security) |
| Baixa automática de estoque | Trigger no Postgres (ver DEC-008) |

Sem servidor próprio nem cron: a agenda de rodadas é consulta em tempo real.

## Documentação

A documentação de projeto vive na raiz do repositório e é a fonte de verdade
para qualquer sessão de trabalho (humana ou com Claude Code):

| Arquivo | Conteúdo |
|---|---|
| [`BRIEFING.md`](./BRIEFING.md) | Visão geral, modelo de dados, regras de negócio, escopo do MVP |
| [`DECISIONS.md`](./DECISIONS.md) | Decisões arquiteturais e de produto, com racional (DEC-001+) |
| [`CONTEXT.md`](./CONTEXT.md) | Estado atual do projeto e próximos passos |

**Antes de qualquer sessão de desenvolvimento, leia os três arquivos.**

## Status

🚧 Em desenvolvimento — fase de implementação do MVP para piloto em casa de
repouso real (Campinas-SP, 2026).

## Privacidade e LGPD

O sistema trata dados de saúde de idosos (dados sensíveis, art. 11 da LGPD).
A casa de repouso atua como controladora e o projeto como operador. Nenhum dado
real é inserido sem termo de tratamento de dados assinado. O MVP segue o
princípio da minimização: coleta apenas o necessário para a gestão de medicação
(sem CPF, convênio ou prontuário).

## Autor

Guilherme Silveira
· Projeto irmão: [Nami Life](https://github.com/Gui-eng26/Nami_life)