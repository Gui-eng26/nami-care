# SESSAO_03 — Gestão de cadastros e identidade Sereníssima

> Roteiro da terceira sessão de implementação via Claude Code.
> Modelo recomendado: Claude Fable 5 (sessão longa e autônoma).
> Criado em: 2026-07-16 | Executada em: 2026-07-16

---

## Pré-requisitos (fazer ANTES de iniciar a sessão)

- [x] Sessão #2 concluída e commitada (PIN bcrypt, turno por RPC, tela da ronda)
- [x] `SUPABASE_SERVICE_ROLE_KEY` preenchida em `.env.local`
- [x] MCP do Supabase apontando para o projeto `nami-care`
      (ref `uvkmvaheupziexlunnno`) — ver `.mcp.json` na raiz

## Escopo

1. **RPC `criar_cuidador`** (resolve o risco nº 1 do relatório da Sessão 2):
   hash do PIN via `fn_hash_pin` dentro do banco; o cliente nunca vê
   `pin_hash`. Inclui `trocar_pin` (PIN atual ou administradora — DEC-025)
   e desativação (nunca exclusão — auditoria).
2. **Controle de acesso à gestão** — DEC-024: flag `eh_admin` + PIN de
   administradora validado server-side em cada RPC de gestão.
3. **Cadastro/edição de residentes** — CRUD com desativação (`idosos.ativo`).
4. **Cadastro/edição de medicamentos e prescrições** — dose com fração 0,5,
   horários das rondas, flag SOS/PRN; alterações não reescrevem histórico
   (versionamento — DEC-026).
5. **Identidade visual Sereníssima** — dourado #B08D4A sobre creme #FAF6EE,
   texto #3D3428; nome "Sereníssima" nas telas, nome completo no login e no
   manifest; cores funcionais (vermelho/verde/âmbar) intactas.

## Restrições

- Stack: JavaScript apenas (Vite + PWA), Supabase, Railway.
- Toda mudança de schema via migration; nunca SQL avulso.
- Regra de negócio no banco (RPCs, triggers); o cliente só apresenta.
- Ledger intacto; toda ação grava o cuidador do turno ativo.
- Não tocar no fluxo de ronda/turno da Sessão 2 além do necessário
  (tema visual é a exceção permitida).

## Critérios de aceite da sessão

- [x] RPCs de gestão como único caminho de escrita em `cuidadores`,
      `idosos`, `medicamentos` e `horarios` (INSERT/UPDATE diretos
      revogados; verificado com `set role authenticated`)
- [x] Toda RPC de gestão recusa PIN não-admin, PIN errado (com rate limit
      da DEC-021) e admin desativada
- [x] `trocar_pin` exige PIN atual; `redefinir_pin` exige administradora;
      `definir_pin` (sem verificação — BUG-001) removida
- [x] Desativação nunca apaga: cuidadora/residente/medicamento/horário
      desativados permanecem no banco e no histórico
- [x] Campos clínicos imutáveis após primeira administração (trigger),
      com versão nova criada pela RPC `atualizar_horario`
- [x] Cadastro completo pelo navegador: cuidadora nova (com PIN), residente
      novo, medicamento contínuo com horário (dose 0,5) — sem tocar no
      banco na mão; turno aberto com a cuidadora recém-criada
- [x] Ronda da Sessão 2 funciona intacta após as mudanças
- [x] Tema Sereníssima aplicado (telas existentes + gestão + manifest),
      contraste preservado nos textos
- [x] Migrations espelhadas em `supabase/migrations/` com smoke test de
      rollback antes do apply; advisors sem WARN novo não-intencional
- [x] `npm run build` OK

## Decisões tomadas nesta sessão

- **DEC-024** — Acesso à gestão: administradora com PIN verificado a cada RPC
  (substitui parcialmente a DEC-011).
- **DEC-025** — Troca de PIN: com PIN atual (self-service) ou por
  administradora; remove `definir_pin` (BUG-001).
- **DEC-026** — Prescrição versionada: campos clínicos imutáveis após uso.

## Bugs e melhorias registrados

- **BUG-001** — `definir_pin` (Sessão #2) permitia trocar o PIN de qualquer
  cuidadora sem verificação nenhuma (bastava estar autenticado como usuário
  da casa). Corrigido nesta sessão: RPC removida e substituída por
  `trocar_pin`/`redefinir_pin` (DEC-025).
- **MH-001** — `abrir_turno` duplica a lógica de verificação de PIN + rate
  limit que agora vive em `fn_verificar_pin`; unificar numa sessão futura
  (não foi feito agora para não tocar no fluxo estável da Sessão 2).
