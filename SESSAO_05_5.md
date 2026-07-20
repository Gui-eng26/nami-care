# SESSAO_05_5 — Pendências entre turnos (BUG-002)

> Roteiro da sessão intermediária 5.5 — curta, dedicada a um único problema.
> Modelo: Claude Fable 5.
> Criado em: 2026-07-20 | Executada em: 2026-07-20

---

## Pré-requisitos (verificados no início da sessão)

- [x] Sessão #5 concluída (`0e1bfd5`); 15 migrations remotas espelham
      `supabase/migrations/`
- [x] MCP do Supabase apontando para o projeto `nami-care`
      (ref `uvkmvaheupziexlunnno`)
- [x] Banco quase limpo: havia 1 turno **aberto** de teste manual do
      Guilherme (Ana, 19/07 23:58 local, 0 administrações) — sem efeito nos
      testes; eliminado nos resets de seed da sessão
- [x] Numeração conferida: último bug registrado era BUG-001 → este é
      **BUG-002**; últimas decisões DEC-030..032 → novas são **DEC-033/034**

## O problema (BUG-002)

`doses_do_turno` (Sessão #2) delimita a janela por `turno.inicio → agora`.
Se um período fica sem NENHUM turno aberto (madrugada, cuidadora esqueceu de
abrir o app) e depois um novo turno abre, as doses vencidas nesse intervalo
não entram na consulta — invisíveis por construção: nem pendentes, nem
atrasadas, nem no denominador da adesão (limite que a DEC-030 já documentava).
Uma dose real pode ter sido dada ou não, e ninguém é avisado de revisar.

## Decisão de produto (já tomada — implementada assim)

Não misturar com a ronda: `doses_do_turno` **não muda**. As doses órfãs vão
para uma tela própria, "Pendências entre turnos".

## Escopo

### 1. Consulta nova, independente (DEC-033)

- [x] `fn_pendencias_entre_turnos()` — dose vencida sem administração cujo
      instante não foi coberto por nenhum turno (`[inicio, fim ou agora]`);
      só residente/medicamento/horário ativos; só contínuos (SOS fora);
      só a partir do primeiro turno da casa e do `criado_em` do horário
      (sem pendência retroativa de linha versionada — DEC-026)
- [x] Teto de 5 dias (janela móvel de 120 h) + contagem de DIAS além do
      teto com pendência (sem listar as doses) — DEC-033
- [x] `listar_pendencias_entre_turnos()` → jsonb {doses, total,
      dias_alem_do_teto, teto_dias} para a tela

### 2. Tela "Pendências entre turnos"

- [x] Aba junto de Ronda | Estoque | Adesão, visível com turno aberto;
      aba INTEIRA vermelha com contagem de doses `(N)` enquanto houver
      pendência; neutra sem selo quando não há
- [x] Agrupamento por dia (mais antigo primeiro) e, no dia, por residente
- [x] Tratativa individual: MESMO modal da Ronda (export de `RegistrarDose`,
      mesmas 4 opções, mesmo insert) — nada duplicado
- [x] Aviso permanente no topo quando há dias além do teto: dado perdido,
      com impacto explícito em adesão e estoque

### 3. Lote + status `pendente` (DEC-034)

- [x] Botão "Resolver pendências em lote" — cobre só o que resta sem
      tratativa no momento do clique
- [x] Alerta de criticidade cheio de tela com os DOIS impactos
      (adesão E estoque/ajuste manual)
- [x] Confirmação com PIN do próprio cuidador do turno, verificado no banco
      (`fn_verificar_pin`, rate limit DEC-021) — RPC
      `resolver_pendencias_em_lote(p_turno_id, p_pin)`
- [x] Novo status `pendente` na constraint; semântica distinta de
      `nao_tomado`; trigger de guarda: só a RPC de lote grava `pendente`
- [x] Estoque: `pendente` não movimenta nada (trigger de baixa já ignora);
      reconciliação manual via `registrar_ajuste_estoque`

### 4. `fechar_turno` com as duas filas

- [x] Só fecha com doses_do_turno E pendências entre turnos (dentro do teto)
      100% tratadas — `pendente` conta como resolvida; além do teto não
      bloqueia, por definição
- [x] Retorno/mensagem distingue a origem do bloqueio (ronda × aba nova)

### 5. Relatório de adesão

- [x] 5ª categoria "Pendente (não apurado)" — chave `nao_apurada` (para não
      colidir com `pendentes` do turno aberto); entra no denominador com
      percentual próprio; legenda curta na tela

## Restrições respeitadas

- JavaScript apenas; schema/função via migration (1 nova: 20260720000100)
- `doses_do_turno` e a exigência de turno aberto intocadas
- Modal individual reaproveitado por export (não duplicado)
- `pendente` inalcançável pelo modal individual (guard no banco)
- Rótulos legíveis, sem jargão

## Fora do escopo (mantido)

- Deploy/PWA/bootstrap da admin real → Sessão #6
- Feature nova de estoque; automação de abertura de turno
- Mostrar pendência antes de abrir o turno — registrada como **MH-002** e,
  após confirmação do Guilherme ainda na sessão, **implementada** (aviso na
  tela de assumir turno; ver relatório §6)

## Critério de pronto

Ver RELATORIO_SESSAO_05_5.md §4 — itens (a)–(g) verificados no navegador
(viewport 375px) + smoke com rollback + bateria SQL A1–A9 / B1–B11.
