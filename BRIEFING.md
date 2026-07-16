# BRIEFING — Nami Care (nome provisório)

> Assistente de gestão de medicação para casas de repouso.
> Documento-mestre do projeto. Leia antes de qualquer sessão de trabalho.
> Última atualização: 2026-07-15 | Versão: 1.2 (regras de negócio 100% definidas)

---

## 1. Visão geral

Sistema web (PWA) para gestão de medicação em casas de repouso de pequeno porte.
Spin-off do know-how da **Nami Life** (assistente de adesão via WhatsApp), com
arquitetura distinta: multiusuário, multi-idoso, com trilha de auditoria.

**Piloto:** casa de repouso da Thais (contato feito via Mescla Empreende / PUC-Campinas).
- 4 cuidadores
- 11 idosos
- 1 celular compartilhado da casa (dispositivo único)

**Dor principal relatada pela cliente:** contagem manual e semanal do estoque de
medicamentos. Proposta de valor central: estoque atualizado automaticamente a cada
dose administrada + relatório de previsão de ruptura → a contagem semanal vira
conferência de exceções.

## 2. Diferenças estruturais em relação à Nami Life

| Dimensão | Nami Life | Nami Care |
|---|---|---|
| Identidade | 1 número WhatsApp = 1 usuário | Login por cuidador (PIN) em app compartilhado |
| Relação usuário–paciente | 1:1 (o usuário é o paciente) | N:N (4 cuidadores × 11 idosos) |
| Canal | WhatsApp (Z-API) | PWA no navegador do celular da casa |
| Lembrete | Notificação individual por medicamento | **Rodada de medicação**: fila consolidada por horário |
| Backend | Node.js + node-cron no Railway | Sem servidor próprio: Supabase (Postgres + Auth + RLS) |
| Custo variável | Z-API por mensagem | ~zero no piloto |

## 3. Conceitos centrais

### 3.1 Rodada de medicação
Unidade operacional do sistema. Em vez de N lembretes simultâneos, o app exibe a
agenda do horário corrente: todos os idosos e medicamentos devidos naquele slot.
O cuidador confirma item a item. Cada confirmação grava: quem, o quê, a quem,
quando, com qual status.

### 3.2 Estoque como livro-razão (ledger)
O estoque NUNCA é um número sobrescrito. É a soma de movimentações:
- `saida_administracao` — baixa automática ao confirmar dose
- `entrada_compra` — reposição
- `ajuste_contagem` — acerto por contagem física (com motivo)
- `perda` — quebra, vencimento, dose descartada

Benefícios: auditoria completa, relatório de divergência (físico vs. sistema),
previsão de ruptura ("acaba em X dias no ritmo atual").

### 3.3 Turno
O cuidador assume o turno com PIN no dispositivo compartilhado. Todas as ações
ficam vinculadas ao cuidador do turno ativo. Troca de turno = novo login.

## 4. Stack técnica

- **Frontend:** React (PWA) — mobile-first, otimizado para o celular da casa
- **Backend/BD:** Supabase (Postgres, Auth, Row Level Security)
- **Hospedagem frontend:** Railway (DEC-007 — consolidação com a infra da Nami Life)
- **Linguagem única:** JavaScript em todo o projeto (DEC-015)
- **Sem cron/servidor Node:** a "agenda" é consulta em tempo real aos horários;
  notificações push ficam fora do MVP (ver seção 8)
- **Repositório:** a criar (sugestão: `Gui-eng26/nami-care`)

## 5. Modelo de dados

Tabelas (ver diagrama ER na documentação da sessão de 2026-07-15):

- **cuidadores** — id, nome, pin_hash, ativo
- **turnos** — id, cuidador_id, inicio, fim
- **idosos** — id, nome, nascimento, observacoes
- **medicamentos** — id, idoso_id, nome, dosagem, forma_farmaceutica, posologia,
  tipo (`continuo` | `sos`), ativo
- **horarios** — id, medicamento_id, hora, qtd_dose, ativo
- **administracoes** — id, medicamento_id, horario_id (NULL = dose avulsa),
  cuidador_id, qtd, registrado_em, status
  (`tomado_no_horario` | `tomado_atrasado` | `nao_tomado` | `recusado`), observacao
- **movimentacoes_estoque** — id, medicamento_id, cuidador_id, tipo, quantidade,
  motivo, criado_em; vínculo opcional com administracoes (baixa automática)

Regras de integridade:
- Saldo de estoque = SUM(movimentações) por medicamento. Nunca armazenar saldo direto
  (ou, se materializado por performance, sempre derivável do ledger).
- `administracoes.status IN (tomado_no_horario, tomado_atrasado)` → movimentação
  `saida_administracao`; `status = recusado` → movimentação `perda`;
  `status = nao_tomado` → sem movimentação. Automático (trigger ou lógica de
  aplicação — ver DEC-008).
- Remoção de medicamento/horário = desativação (`ativo = false`), nunca DELETE.
  Preserva histórico de adesão e auditoria.

## 6. Funcionalidades do MVP

1. Login/assumir turno (PIN por cuidador)
2. Cadastro de idosos (CRUD)
3. Cadastro de medicamentos por idoso (dosagem, forma farmacêutica, posologia, estoque inicial)
4. Cadastro/edição de horários por medicamento
5. **Tela principal: rodada de medicação** — fila do horário corrente + próximos horários
6. Confirmação de dose (confirmado/recusado/pulado + observação)
7. Movimentações de estoque manuais (compra, ajuste por contagem, perda)
8. **Dose avulsa (SOS/PRN):** registro de medicamento sem horário fixo, com baixa de estoque
9. Ficha do idoso (medicamentos, horários, histórico recente)
10. Relatório de adesão por idoso (período configurável)
11. Relatório de estoque (saldo atual, consumo médio diário, previsão de ruptura,
    sugestão de compra)

## 7. Regras de negócio

### Definidas (2026-07-15)

- **Dose recusada:** recusa = perda = baixa estoque. Sem cenário de devolução.
- **Janela de tolerância:** 30 minutos após o horário agendado. Depois disso a dose
  fica **atrasada** e permanece em destaque na tela até receber tratativa.
- **Tratativas possíveis para dose atrasada:** (a) tomou no horário, só não foi
  registrado no momento; (b) tomou atrasado; (c) não tomou.
- **Fechamento de turno:** o cuidador só encerra o turno quando TODAS as doses do
  período receberam tratativa. Nenhuma dose fica sem resposta — garantia de
  acurácia do ledger de estoque e do relatório de adesão.
- **Permissões:** todos os cuidadores podem cadastrar e editar (sem perfil admin no MVP).
- **Ponto de reposição:** alertar quando a cobertura de estoque for < 5 dias
  (calculada pelo consumo médio diário).

- **Doses fracionadas:** qtd_dose aceita frações de 0,5 com baixa exata no ledger;
  descarte de metade não utilizada = movimentação manual de perda.
- **Dose avulsa (SOS/PRN):** medicamentos tipo `sos` não têm horários nem entram em
  rodadas/fechamento de turno. Registro: idoso + medicamento + quantidade →
  baixa de estoque. Confirmado que existem medicamentos SOS na casa.

### Efeito no estoque por status da dose

| Status | Baixa estoque? |
|---|---|
| tomado_no_horario | Sim |
| tomado_atrasado | Sim |
| recusado | Sim (perda) |
| nao_tomado | Não |

**Não há pendências. Regras de negócio 100% definidas em 2026-07-15.**

## 8. Fora do escopo do MVP (backlog v2)

- Notificações push / alerta sonoro no celular
- Alerta de ruptura via WhatsApp para a gestora (reaproveita know-how Z-API)
- Perfil "família" com relatório de adesão do idoso
- Múltiplas casas de repouso (multi-tenant)
- Interações medicamentosas / alertas clínicos

## 9. LGPD

Dados de saúde de idosos = dados sensíveis (art. 11).
- Casa de repouso = **controladora**; Guilherme/Nami = **operador**
- Necessário: termo de tratamento de dados com a casa + base legal (tutela da saúde,
  procedimento realizado por profissionais de saúde/serviços de saúde)
- Adaptar o racional de consentimento já construído para a Nami Life
- Minimização: MVP não coleta CPF, convênio nem prontuário — apenas o necessário
  para a gestão de medicação

## 10. Contexto de negócio

- Origem: apresentação no Mescla Empreende (Trilha 2 — problem-solution fit)
- O piloto é também experimento de validação: casas de repouso como segmento B2B
  da Nami (hipótese levantada anteriormente por Guilherme)
- Métricas de sucesso do piloto (proposta):
  - Thais abandona a contagem semanal completa em ≤ 4 semanas de uso
  - 100% das rodadas registradas no sistema por 2 semanas consecutivas
  - Divergência estoque físico vs. sistema < 5% na primeira conferência mensal