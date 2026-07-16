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
  (DEC-023).

**Pendências pós-sessão:** ~~commit + push~~ ✅ · habilitar Leaked Password
Protection no dashboard do Auth · testar no celular da casa (depende do
deploy, Sessão 5).

## Sessão 3 — Gestão de cadastros 🔜

Transforma o sistema de "demo com dados do seed" em sistema que a casa
administra sozinha.

- **RPC `criar_cuidador`(nome, pin):** faz o hash internamente via
  `fn_hash_pin` e insere a linha completa — necessária porque o cliente
  não tem mais acesso a `pin_hash`. Risco já mapeado no relatório da
  Sessão 2. Incluir também troca de PIN e desativação (nunca exclusão:
  cuidador com histórico de administrações não pode sumir do ledger de
  auditoria).
- **Cadastro/edição de residentes:** hoje só existem via seed.
- **Cadastro/edição de medicamentos e prescrições:** medicamento, dose,
  horários das rondas, flag SOS/PRN.
- Definir quem acessa a gestão (todas as cuidadoras? só a Thais?) —
  provável DEC nova: um "PIN de administradora" ou papel diferenciado.

**Critério de pronto:** conseguir cadastrar as 4 cuidadoras reais e os 11
residentes reais da casa sem tocar no banco na mão.

## Sessão 4 — Estoque e SOS (a dor nº 1) 🔜

Fecha o ciclo do estoque e substitui a contagem manual semanal.

- **Entradas no ledger:** fluxo de reposição — medicamento, quantidade,
  data → linha positiva em `movimentacoes_estoque`. Hoje só existem
  saídas (trigger da Sessão 1); sem entradas, o saldo só desce.
- **Visão de estoque:** saldo atual por medicamento (soma do ledger),
  histórico de movimentações (auditoria linha a linha).
- **Alerta de cobertura:** recomendação de reposição quando a cobertura
  projetada cair abaixo de 5 dias (limiar já decidido).
- **Fluxo SOS/PRN:** registro de dose avulsa fora da ronda (decisão já
  tomada: fluxo separado), com baixa de estoque pelo mesmo trigger.

**Critério de pronto:** ciclo completo compra → entrada → baixa automática
na dose → saldo e alerta visíveis, sem nenhuma contagem manual.

## Sessão 5 — Deploy e piloto 🔜

- Deploy do frontend no Railway (consolidando com a infra existente).
- Configurar URLs permitidas no Supabase Auth para o domínio de produção.
- Instalação como PWA no celular compartilhado da casa.
- Cadastro dos dados reais (cuidadoras, residentes, prescrições, estoque
  inicial contado uma última vez à mão — a última contagem manual).
- Ajustes de usabilidade a partir do teste no dispositivo real (alvos de
  toque no teclado PIN, comportamento do modal de tratativa etc.).
- Acompanhamento da primeira semana de uso com a Thais.

**Critério de pronto:** casa operando no app, sem planilha e sem contagem
manual.

---

## Fora de escopo do MVP (backlog pós-piloto)

- Relatórios/exportação para família ou vigilância sanitária.
- Multi-casa (hoje: 1 casa, 1 usuário Supabase, PIN por cuidadora —
  DEC-019).
- Notificações push de dose atrasada.
- Painel remoto para a Thais acompanhar de fora da casa.

## Princípios permanentes (valem em toda sessão)

- Stack: JavaScript apenas (Vite + PWA), Supabase, Railway.
- Banco: exclusivamente o projeto `nami-care` (ref `uvkmvaheupziexlunnno`).
- Toda mudança de schema via migration; nunca SQL avulso.
- Regra de negócio no banco (RPCs, triggers); o cliente só apresenta.
- Ledger nunca sobrescrito; toda ação grava o cuidador do turno ativo.
- Decisões novas → DEC-0XX; bugs → BUG-0XX; melhorias → MH-0XX.