# SESSAO_02 — PIN definitivo, turno e ronda de medicação

> Roteiro da segunda sessão de implementação via Claude Code.
> Modelo recomendado: Claude Fable 5 (sessão longa e autônoma).
> Criado em: 2026-07-16 | Executada em: 2026-07-16

---

## Pré-requisitos (fazer ANTES de iniciar a sessão)

- [x] Sessão #1 concluída (schema, trigger de baixa, RLS, seed aplicados)
- [x] `SUPABASE_SERVICE_ROLE_KEY` preenchida em `.env.local`
- [x] MCP do Supabase apontando para o projeto `nami-care`
      (ref `uvkmvaheupziexlunnno`) — ver `.mcp.json` na raiz

## Prompt inicial da sessão

```
## Antes de começar
1. Leia BRIEFING.md, DECISIONS.md (DEC-001 a DEC-019), CONTEXT.md e
   RELATORIO_SESSAO_01.md. Eles são a fonte da verdade — em caso de
   conflito com sua memória, os arquivos prevalecem.
2. Banco: TODA operação Supabase desta sessão usa exclusivamente o
   projeto nami-care (ref uvkmvaheupziexlunnno), conforme o .mcp.json
   na raiz. Os projetos Nami_Life Brazil e Nami's Project estão fora
   de escopo. Se sua memória sugerir outro ref, releia o .mcp.json.
3. Crie SESSAO_02.md no mesmo padrão da Sessão 1 e registre novas
   decisões como DEC-020+, bugs como BUG-00X e melhorias como MH-00X.

## Escopo desta sessão

### 1. Mecanismo definitivo de PIN (resolve a DEC-018)
- Substituir o formato provisório do seed (SHA-256 sem salt) pelo
  mecanismo definitivo: hash com salt por cuidador.
- Verificação SEMPRE server-side, via RPC no Supabase — o hash nunca
  é comparado nem exposto no cliente.
- Rate limit nas tentativas de PIN (definir e registrar a política
  como decisão: nº de tentativas, janela, bloqueio).
- Migração para atualizar os dados de seed existentes ao novo formato.
- Ao concluir, atualizar o status da DEC-018 (substituída/ratificada).

### 2. Fluxo de turno
- Abertura de turno por PIN: identifica o cuidador ativo no
  dispositivo compartilhado (conforme DEC-019).
- Fechamento obrigatório: só permite encerrar o turno quando todas as
  doses das rondas do turno tiverem um tratamento registrado
  (administrada, recusada, adiada etc. — conforme modelo já decidido).
- Toda ação grava o cuidador do turno ativo, nunca o usuário Supabase.

### 3. Primeira tela do PWA: ronda de medicação
- Tela operacional central: doses da ronda atual, status de cada uma,
  registro de tratamento com dedução automática de estoque (trigger
  já criado na Sessão 1 — não duplicar a lógica no cliente).
- Respeitar a janela de tolerância de 30 min antes de marcar atraso.
- Medicação SOS/PRN fica FORA da ronda (fluxo separado, não incluir
  nesta tela além de eventual atalho).

## Restrições
- Stack: JavaScript apenas (Vite + PWA), Supabase, Railway.
- Padrão ledger no estoque: nunca sobrescrever saldo, sempre acumular
  transações em movimentacoes_estoque.
- Não tocar em RLS/schema fora do necessário para o escopo acima;
  qualquer mudança de schema vai por migration, nunca SQL avulso.

## Encerramento da sessão
- Gerar RELATORIO_SESSAO_02.md: o que foi feito, decisões novas,
  pendências e riscos para a Sessão 3.
```

## Critérios de aceite da sessão

- [x] `pin_hash` em bcrypt com salt por cuidador; coluna inacessível aos
      papéis de API (verificado com `set role authenticated/anon`)
- [x] PIN verificado só no servidor (RPC `abrir_turno`); 5 falhas em 15 min
      bloqueiam novas tentativas, com horário de desbloqueio na resposta
- [x] Migração converteu os 4 hashes SHA-256 do seed para bcrypt
- [x] Só um turno aberto por vez; INSERT/UPDATE em `turnos` revogados do
      cliente (abertura/fechamento só via RPC)
- [x] `fechar_turno` recusa fechamento com dose devida sem tratativa e
      fecha quando todas foram tratadas (testado via SQL e no navegador)
- [x] Administração exige turno aberto do cuidador; dupla tratativa do
      mesmo slot rejeitada (UNIQUE horario_id + prevista_em)
- [x] Ronda no navegador: atrasadas em destaque, tolerância de 30 min,
      registro de tratativa com baixa automática pelo trigger da Sessão #1
- [x] SOS fora da ronda (apenas atalho informativo na tela)
- [x] `npm run build` sem erros; console do navegador limpo
- [x] DECISIONS.md atualizado (DEC-018 substituída; DEC-020 a DEC-023)

## Pós-sessão (Guilherme)

- [ ] Revisar RELATORIO_SESSAO_02.md
- [ ] Salvar relatório no Google Drive (pasta de relatórios de sessão, padrão Nami)
- [ ] Commit + push
- [ ] Habilitar "Leaked Password Protection" no dashboard do Supabase
      (Auth > Providers) — aviso dos security advisors
- [ ] Testar o fluxo completo no celular da casa (login casa@namicare.app,
      senha em `.env.local` → assumir turno com PIN de teste)
