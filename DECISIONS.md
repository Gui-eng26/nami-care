# DECISIONS — Nami Care

> Registro de decisões arquiteturais e de produto (ADR simplificado).
> Formato: DEC-XXX | Data | Decisão | Racional | Alternativas descartadas | Status

---

## DEC-001 — Interface: PWA web, não WhatsApp
**Data:** 2026-07-15 | **Status:** aprovada

**Decisão:** O produto será um web app (PWA), não um bot de WhatsApp como a Nami Life.

**Racional:** A premissa da Nami (1 número = 1 usuário) quebra na casa de repouso:
4 cuidadores compartilham a gestão de 11 idosos (N:N), é preciso trilha de auditoria
por turno, e visões consolidadas (rodada do horário, relatórios de estoque) são
inviáveis em conversa de texto. PWA elimina o custo por mensagem da Z-API.

**Alternativas descartadas:** WhatsApp como interface principal; app nativo
(complexidade de publicação desnecessária para piloto).

---

## DEC-002 — Dispositivo: celular compartilhado da casa
**Data:** 2026-07-15 | **Status:** aprovada (confirmado com a realidade da cliente)

**Decisão:** O app será desenhado para um único celular compartilhado, com troca de
operador via "assumir turno" (PIN).

**Racional:** A casa da Thais possui celular próprio. Um dispositivo único simplifica
autenticação (PIN curto em vez de e-mail/senha por pessoa), suporte e treinamento.

**Implicações:** sessão do turno deve expirar/perguntar "quem está no turno?" após
inatividade prolongada; UI mobile-first para uma única tela de celular.

---

## DEC-003 — Rodada de medicação como unidade central (não lembretes individuais)
**Data:** 2026-07-15 | **Status:** aprovada

**Decisão:** Em vez de disparar N lembretes por medicamento (modelo Nami), o sistema
consolida todos os medicamentos devidos num horário em uma única fila operacional
("rodada"), que o cuidador percorre confirmando item a item.

**Racional:** Resolve a colisão de horários entre idosos (problema técnico) e espelha
a rotina real do cuidador, que faz a ronda — não atende 15 alarmes (problema de UX).

---

## DEC-004 — Estoque como livro-razão de movimentações
**Data:** 2026-07-15 | **Status:** aprovada

**Decisão:** O saldo de estoque é derivado da soma de movimentações
(entrada_compra, saida_administracao, ajuste_contagem, perda), nunca um campo
sobrescrito.

**Racional:** Auditoria completa, relatório de divergência físico vs. sistema (a dor
número 1 da cliente), previsão de ruptura e histórico de consumo — padrão consolidado
de gestão de estoque no varejo farmacêutico (know-how RaiaDrogasil).

---

## DEC-005 — Stack: Supabase sem backend próprio
**Data:** 2026-07-15 | **Status:** aprovada

**Decisão:** Supabase (Postgres + Auth + RLS) como backend completo; React PWA como
frontend. Sem servidor Node/cron no MVP.

**Racional:** Reaproveita domínio existente de Supabase (Nami Life). A "agenda" do
sistema é consulta em tempo real, dispensando cron. Custo de infra ~zero no piloto.
Notificações push (que exigiriam mais infra) ficam para v2.

**Alternativas descartadas:** replicar stack completa da Nami (Node + Railway +
node-cron) — complexidade sem benefício para este caso.

---

## DEC-006 — Soft delete para medicamentos e horários
**Data:** 2026-07-15 | **Status:** aprovada

**Decisão:** Remoções são desativações (`ativo = false`); nunca DELETE físico.

**Racional:** Preserva histórico de adesão e trilha de auditoria — requisito
implícito de um sistema que registra atos de cuidado com idosos.

---

## DEC-007 — Hospedagem do frontend
**Data:** — | **Status:** PENDENTE

**Opções:** Vercel (free tier generoso para PWA estática) vs. Railway (consolidar
tudo onde já está a Nami). Decidir na fase de implementação.

---

## DEC-008 — Baixa automática de estoque: trigger no banco vs. lógica de aplicação
**Data:** — | **Status:** PENDENTE

**Contexto:** doses com status `tomado_*` geram saída; `recusado` gera perda.
Trigger no Postgres garante consistência independente do cliente; lógica na
aplicação é mais fácil de depurar. Decidir na implementação (tendência: trigger,
com constraint de unicidade administracao_id na movimentação para evitar dupla baixa).

---

## DEC-009 — Dose recusada = perda, com baixa de estoque
**Data:** 2026-07-15 | **Status:** aprovada

**Decisão:** Recusa do idoso sempre baixa estoque, registrada como perda.

**Racional:** Na prática, a dose já saiu do blister/frasco. Regra única simplifica
a UI e mantém o ledger fiel à realidade física. Sem cenário de devolução.

---

## DEC-010 — Janela de 30 min + fechamento de turno obrigatório
**Data:** 2026-07-15 | **Status:** aprovada

**Decisão:** Dose pode ser confirmada até 30 min após o horário agendado. Depois
vira "atrasada" e permanece em destaque na tela. O turno só pode ser encerrado
quando todas as doses do período receberem tratativa: tomou no horário (registro
tardio), tomou atrasado, ou não tomou.

**Racional:** Garante 100% de acurácia do ledger de estoque e do relatório de
adesão — nenhuma dose fica sem resposta. Disciplina operacional análoga ao
fechamento de caixa no varejo.

**Implicações de UX:** seção fixa de "doses pendentes de tratativa" na tela
principal; botão "encerrar turno" bloqueado enquanto houver pendências.

---

## DEC-011 — Sem perfil admin no MVP
**Data:** 2026-07-15 | **Status:** aprovada

**Decisão:** Todos os cuidadores podem cadastrar e editar idosos, medicamentos e
horários.

**Racional:** Equipe de 4 pessoas com confiança mútua; a trilha de auditoria
(toda ação vinculada ao cuidador do turno) cobre a rastreabilidade. Perfis de
permissão ficam para v2 se o produto escalar para casas maiores.

---

## DEC-012 — Ponto de reposição: cobertura < 5 dias
**Data:** 2026-07-15 | **Status:** aprovada

**Decisão:** O relatório de estoque alerta quando o saldo atual dividido pelo
consumo médio diário indicar cobertura inferior a 5 dias.

**Racional:** Definido pela realidade operacional da cliente (prazo suficiente
para compra na farmácia local). Parametrizável por medicamento em v2 se necessário.

---

## DEC-013 — Doses fracionadas (0,5)
**Data:** 2026-07-15 | **Status:** aprovada

**Decisão:** suportar qtd_dose em frações de 0,5 com baixa exata no ledger;
descarte de metade não utilizada registrado como movimentação manual de perda.

---

## DEC-014 — Dose avulsa (SOS/PRN) no MVP
**Data:** 2026-07-15 | **Status:** aprovada (confirmado: existem medicamentos SOS na casa)

**Decisão:** o MVP inclui registro de "dose avulsa" — medicamento sem horário
fixo, dado conforme necessidade (ex.: analgésico). Fluxo: selecionar idoso +
medicamento + confirmar, com baixa de estoque.

**Racional:** sem isso, doses avulsas não registradas quebram a acurácia do
ledger — a proposta de valor central do produto.

**Implicações no schema:**
- `medicamentos.tipo`: `continuo` (com horários) | `sos` (sem horários)
- `administracoes.medicamento_id` (FK obrigatória) + `administracoes.horario_id`
  passa a ser opcional (NULL = dose avulsa)
- Medicamentos `sos` não entram em rodadas nem no fechamento de turno; aparecem
  apenas no fluxo de dose avulsa e nos relatórios de estoque/consumo