# RELATÓRIO — Sessão Claude Code #2

> PIN definitivo, fluxo de turno e tela da ronda de medicação.
> Data: 2026-07-16 | Modelo: Claude Fable 5 | Roteiro: `SESSAO_02.md`

---

## 1. Resumo executivo

A Sessão #2 foi concluída integralmente. O app deixou de ser esqueleto: o
celular da casa faz login uma única vez com o usuário Supabase da casa
(DEC-019), o cuidador assume o turno com PIN verificado exclusivamente no
banco (bcrypt + rate limit), e a tela central da ronda lista as doses devidas
do turno com a tolerância de 30 min, registra tratativas (com baixa
automática de estoque pelo trigger da Sessão #1) e só libera o encerramento
do turno quando toda dose devida tem tratativa. O ciclo completo — login →
PIN errado/bloqueio → PIN correto → ronda com atrasadas → tratativa →
fechamento negado → fechamento aceito — foi verificado no navegador e por
testes SQL.

**Decisões registradas:** DEC-018 (hash provisório) foi **substituída** pela
DEC-020 (bcrypt server-side). Novas: DEC-021 (rate limit 5 falhas/15 min),
DEC-022 (turno único, abertura/fechamento só por RPC) e DEC-023
(`prevista_em` ancora a dose no slot; fuso fixo da casa).

**Banco ao final da sessão:** resetado para o estado limpo do seed
(4 cuidadores com hash bcrypt, 850 unidades de estoque, 0 turnos e 0
administrações) — os dados gerados nos testes foram descartados via
`npm run seed -- --reset`.

## 2. O que foi construído

### Migrations novas (aplicadas no projeto `nami-care` e espelhadas no repo)

| Arquivo | Conteúdo |
|---|---|
| `20260716000600_pin_definitivo.sql` | Tabela `tentativas_pin` (RLS sem políticas, sem grants de API); grants por coluna em `cuidadores` (API não lê `pin_hash`, não insere linhas); `fn_hash_pin` (bcrypt `bf/10`, só service_role); RPC `definir_pin`; conversão dos 4 hashes SHA-256 do seed para bcrypt |
| `20260716000700_turno_e_ronda.sql` | Índice único de turno aberto; `turnos` sem INSERT/UPDATE pelo cliente (políticas removidas); `administracoes.prevista_em` + CHECK + UNIQUE `(horario_id, prevista_em)`; trigger "administração exige turno aberto do cuidador"; `prevista_em` imutável (DEC-017); `fn_fuso_casa`; RPCs `doses_do_turno`, `abrir_turno`, `fechar_turno` |
| `20260716000800_hardening_sessao_02.sql` | `search_path` fixo em `fn_fuso_casa` (lint 0011 dos advisors) |

### RPCs (contrato do app)

- **`abrir_turno(p_cuidador_id, p_pin)`** → jsonb. Sucesso: `{ok, retomado,
  turno{id, cuidador_id, cuidador_nome, inicio}}` (mesmo cuidador com turno
  aberto = retomada, cobre a reautenticação da DEC-002). Erros:
  `pin_invalido`, `cuidador_nao_encontrado`, `pin_incorreto`
  (+`tentativas_restantes`), `pin_bloqueado` (+`desbloqueia_em`),
  `turno_aberto_outro_cuidador`.
- **`fechar_turno(p_turno_id)`** → jsonb. Erros: `turno_nao_encontrado`,
  `turno_ja_fechado`, `doses_pendentes` (+`total` e lista com idoso,
  medicamento e horário previsto).
- **`doses_do_turno(p_turno_id)`** → tabela com a agenda do turno: cada slot
  devido (horário ativo × dia, no fuso da casa, entre o início do turno e
  agora) com situação `tratada` / `pendente` / `atrasada` (tolerância de 30
  min calculada no banco). É a fonte única usada pela tela e pelo
  `fechar_turno` — o cliente não recalcula slots.

### App (React/PWA)

```
src/
├── App.jsx                    # máquina de estados: sessão da casa → turno → ronda
├── components/TecladoPin.jsx  # teclado numérico (4–6 dígitos)
└── pages/
    ├── LoginCasa.jsx          # login único do dispositivo (DEC-019)
    ├── AssumirTurno.jsx       # escolha do cuidador + PIN (RPC abrir_turno)
    └── Ronda.jsx              # atrasadas em destaque, ronda atual, tratadas,
                               # modal de tratativa, atalho SOS (Sessão #3),
                               # encerrar turno; recarrega a cada 60 s
```

- Tratativas no modal seguem o BRIEFING §7: dentro da janela →
  tomou/recusou/não tomou; atrasada → tomou no horário (registro tardio,
  enviado com `registrado_em = prevista_em` para a baixa cair na data real —
  DEC-008), tomou agora (atrasado), recusou, não tomou.
- `Home.jsx` (esqueleto da Sessão #1) foi removido.
- Scripts: `seed.js` agora obtém o hash via RPC `fn_hash_pin` (nunca calcula
  hash localmente) e limpa `tentativas_pin` no reset; novo
  `scripts/criar-usuario-casa.js` (`npm run criar-usuario-casa`).

### Usuário Supabase da casa

Criado `casa@namicare.app` (id `3b4937be-…`). A senha gerada está em
`.env.local` (`CASA_EMAIL` / `CASA_SENHA`) — git-ignorada; é a credencial a
digitar uma única vez no celular da casa.

## 3. Política de segurança do PIN (como ficou)

1. Hash bcrypt com salt por cuidador, gerado e comparado apenas no Postgres.
2. `pin_hash` invisível para `anon` e `authenticated` (grants por coluna) —
   verificado com `set role` nos dois papéis.
3. Rate limit: 5 falhas em janela móvel de 15 min bloqueiam o cuidador até a
   falha mais antiga sair da janela; toda tentativa fica auditada em
   `tentativas_pin`.
4. `turnos` sem escrita direta pelo cliente: abrir/fechar só pelas RPCs.
5. Trigger garante que administração só entra com turno aberto do cuidador.

## 4. Verificações executadas

| Critério | Resultado |
|---|---|
| Migrations aplicam limpas (smoke test em transação com rollback antes do apply) | OK |
| Hashes do seed convertidos para bcrypt (`$2a$10$…`, 60 chars) | OK — 4/4 |
| PIN errado 5× → 6ª tentativa bloqueada com `desbloqueia_em` | OK (SQL + UI: "PIN incorreto. 4 tentativa(s) antes do bloqueio.") |
| PIN correto abre turno; mesmo cuidador retoma; outro cuidador é barrado | OK |
| `authenticated` não lê `pin_hash`, não escreve `turnos`, não lê `tentativas_pin`; `anon` não executa `abrir_turno` | OK — 42501 em todos |
| `fechar_turno` com dose devida sem tratativa → `doses_pendentes`; com tudo tratado → fecha | OK (SQL + UI) |
| Dupla tratativa do mesmo slot → `unique_violation`; administração sem turno aberto → rejeitada | OK |
| Baixa automática: tratativa na UI gerou `saida_administracao` de −1 datada no horário real da dose (registro tardio); recusa gera `perda` | OK |
| Saldo da view = soma do ledger após os testes (833,50 = 833,50) e após o reset (850) | OK |
| Fluxo completo no navegador (viewport 375px): login → PIN → ronda (2 slots atrasados, depois 3) → tratativa → encerrar bloqueado → encerrar OK → volta a "Quem está assumindo o turno?" | OK — console sem erros |
| `npm run build` | OK |
| Security advisors | 1 WARN corrigido (migration 000800); demais avisos são intencionais e documentados abaixo |

## 5. Avisos dos advisors mantidos de propósito

- **`tentativas_pin` com RLS sem política (INFO):** é o desenho — nenhum papel
  de API acessa a tabela; só as funções SECURITY DEFINER.
- **Políticas `always true` (WARN):** MVP sem perfis (DEC-011), igual à
  Sessão #1.
- **RPCs SECURITY DEFINER executáveis por `authenticated` (WARN):**
  `abrir_turno`, `fechar_turno` e `definir_pin` são exatamente a API do app;
  `anon` e `public` tiveram EXECUTE revogado.
- **Leaked Password Protection desabilitada (WARN):** configuração de
  dashboard (não vai por migration) — ação do Guilherme no pós-sessão.

## 6. Pendências e riscos para a Sessão #3

1. **Cadastro de cuidadores exigirá RPC própria** — o cliente não tem mais
   INSERT em `cuidadores` (não conhece `pin_hash`). Sugestão: RPC
   `criar_cuidador(nome, pin)` na Sessão #3, reaproveitando `fn_hash_pin`.
2. **Horário desativado no meio do turno** some da agenda (`doses_do_turno`
   só considera horários ativos) — inclusive uma dose já tratada daquele
   horário deixa de ser exibida (o registro permanece no banco). Aceitável
   enquanto não há tela de edição de horários; reavaliar na Sessão #3 junto
   com os cadastros.
3. **Bloqueio por inatividade** (repedir PIN — DEC-002) ficou fora: quem pegar
   o celular com turno aberto age em nome do cuidador do turno. Espelha a
   realidade do dispositivo compartilhado, mas reavaliar após o piloto.
4. **`prevista_em` não é validada contra a grade de horários** — a UNIQUE e a
   FK composta seguram duplicidade e pertencimento, mas um INSERT direto pode
   gravar um instante que não corresponde a um slot real. Risco baixo (só a
   tela da ronda insere hoje); endurecer se surgir outro caminho de escrita.
5. **Fuso fixo `America/Sao_Paulo`** (`fn_fuso_casa`) — suficiente para o
   piloto; vira configuração por casa num eventual multi-tenant (v2).
6. **Turnos não são "encerráveis" por terceiros:** se um cuidador esquecer o
   turno aberto e for embora, o próximo precisa tratar as doses devidas para
   fechar (ou tratar e fechar em nome próprio após abrir… não — o turno
   segue do anterior até ser fechado). Para o piloto: orientar a equipe a
   fechar o turno na troca; reavaliar um "fechar turno alheio com PIN" se
   incomodar na prática.
7. **Commit** — as mudanças desta sessão estão no working tree, sem commit
   (pós-sessão do roteiro prevê commit + push pelo Guilherme).

## 7. Como rodar / testar

```bash
npm install
npm run dev                    # http://localhost:5173
# login: casa@namicare.app / senha em .env.local (CASA_SENHA)
# PINs de teste: Ana 1111, Beatriz 2222, Carlos 3333, Débora 4444

npm run seed -- --reset        # repopula dados de teste (service role key)
npm run criar-usuario-casa     # recria o usuário da casa (CASA_EMAIL/CASA_SENHA)
```

Dica para ver a ronda cheia fora dos horários (07/08/12/20 h): abrir um turno
e retroagir o início —
`update turnos set inicio = now() - interval '6 hours' where fim is null;`
