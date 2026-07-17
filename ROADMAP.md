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

## Sessão 3 — Gestão de cadastros ✅ (2026-07-16)

Transformou o sistema de "demo com dados do seed" em sistema que a casa
administra sozinha.

- Acesso à gestão: flag `eh_admin` + PIN de administradora validado no
  banco em cada RPC de gestão (DEC-024, substitui parcialmente DEC-011).
- Gestão de cuidadoras 100% por RPC (`criar_cuidador` com hash no banco,
  `atualizar_cuidador`, `definir_ativo_cuidador`); troca de PIN com
  verificação do atual ou por administradora (DEC-025); `definir_pin` sem
  verificação removida (BUG-001).
- Residentes com soft delete (`idosos.ativo`) e RPCs próprias;
  `doses_do_turno` ignora residente desativado.
- Prescrições versionadas (DEC-026): campos clínicos imutáveis após a
  primeira administração (triggers); editar horário com histórico
  desativa a linha antiga e cria a versão nova.
- Identidade visual Sereníssima aplicada em todas as telas + manifest.

**Critério de pronto atingido:** cadastro completo (cuidadora com PIN,
residente, medicamento com horário fracionado) feito pelo navegador, sem
tocar no banco na mão — verificado no ciclo completo + testes SQL.

**Pendências pós-sessão:** commit + push · bootstrap da admin real (Thais)
fica para o cadastro de dados reais (Sessão 5) · MH-001 (unificar a
verificação de PIN duplicada em `abrir_turno`).

## Sessão 4 — Estoque e SOS (a dor nº 1) ✅ (2026-07-17)

Fechou o ciclo do estoque e substitui a contagem manual semanal.

- **Ledger completo por RPC:** `registrar_entrada_estoque` (compra, data
  retroativa permitida), `registrar_ajuste_estoque` (a cuidadora informa a
  contagem; o banco calcula e grava a diferença) e
  `registrar_perda_estoque` (motivo obrigatório). Escrita direta em
  `movimentacoes_estoque` revogada do cliente; o trigger de baixa virou
  SECURITY DEFINER. Toda movimentação grava o cuidador do turno aberto.
- **Visão de estoque (DEC-029):** tela nova com abas Ronda | Estoque;
  lista por residente, seção "Repor" com os alertas no topo, extrato de
  movimentações linha a linha por medicamento.
- **Alerta de reposição (DEC-027):** contínuo = cobertura determinística
  pela prescrição ativa (< 5 dias, DEC-012) com sugestão de compra para
  30 dias (DEC-028); SOS = saldo abaixo do `estoque_minimo` do cadastro.
- **Fluxo SOS/PRN (DEC-014):** dose avulsa na tela da ronda (residente →
  medicamento SOS → quantidade), baixa pelo mesmo trigger da ronda.

**Critério de pronto atingido:** ciclo completo verificado no navegador —
compra → saldo sobe → dose na ronda e dose SOS → saldo desce → alertas nos
dois casos → ajuste por contagem corrige divergência sem apagar histórico.

**Pendências pós-sessão:** commit + push · Leaked Password Protection no
dashboard (desde a S2) · ajuste por contagem não é atômico com baixas
concorrentes (aceito no piloto de dispositivo único).

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