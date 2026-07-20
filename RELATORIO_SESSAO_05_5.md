# RELATÓRIO — Sessão Claude Code #5.5

> Pendências entre turnos — correção do BUG-002 (doses invisíveis em lacunas
> de cobertura de turno).
> Data: 2026-07-20 | Modelo: Claude Fable 5 | Roteiro: `SESSAO_05_5.md`

---

## 1. Resumo executivo

Sessão curta, dedicada a um único problema, concluída integralmente. O
**BUG-002** — dose que vence num período sem nenhum turno aberto não aparecia
em lugar algum do sistema (limite que a DEC-030 já documentava como risco) —
foi corrigido com uma fila própria, sem tocar na `doses_do_turno`:

- **Tela nova "Pendências entre turnos"** (4ª aba da operação): doses órfãs
  dos últimos 5 dias, agrupadas por dia → residente, tratáveis uma a uma pelo
  **mesmo modal da ronda** (componente exportado, não duplicado) ou em
  **lote** com o novo status `pendente`.
- A aba fica **inteira vermelha com a contagem** — ex.: "Pendências entre
  turnos (130)" — enquanto houver pendência; neutra quando não há.
- **Lote com fricção deliberada** (DEC-034): alerta de criticidade cheio de
  tela nomeando os dois impactos (taxa de adesão no relatório + divergência
  de estoque a ajustar manualmente) e confirmação com o **PIN do próprio
  cuidador do turno**, verificado no banco com o rate limit de sempre.
- **`fechar_turno` agora exige as duas filas zeradas** (ronda + pendências
  dentro do teto), com mensagem distinguindo a origem do bloqueio.
- **Relatório de adesão** ganhou a 5ª categoria "Pendente (não apurado)",
  no denominador, separada das quatro originais (não se soma a "não tomada"
  nem às tomadas — mentiria nos dois casos).

**Decisões novas:** DEC-033 (fila própria + teto de 5 dias e sua
consequência), DEC-034 (status `pendente`, semântica, PIN e texto do alerta).
**Bug corrigido:** BUG-002. **Banco ao final:** resetado limpo (4 cuidadoras,
11 residentes, 24 medicamentos, 850 un., 0 turnos, 0 administrações,
0 pendências).

## 2. O que foi construído

### Migration nova (aplicada no projeto e espelhada no repo)

| Arquivo | Conteúdo |
|---|---|
| `20260720000100_pendencias_entre_turnos.sql` | (1) `administracoes_status_check` passa a aceitar `pendente`; trigger de guarda `trg_pendente_so_em_lote` — o status só nasce da RPC de lote (set_config transacional). (2) `fn_pendencias_entre_turnos()` — fonte única da fila: slot vencido de contínuo ativo (residente/medicamento/horário ativos), sem administração, não coberto por NENHUM intervalo `[inicio, fim ou agora]` de turno; bounded pelo primeiro turno da casa e pelo `criado_em` do horário (linha versionada não gera pendência retroativa — DEC-026); coluna `dentro_do_teto` marca a janela de 5 dias. (3) `listar_pendencias_entre_turnos()` → jsonb (doses do teto + total + contagem de DIAS além do teto). (4) `resolver_pendencias_em_lote(p_turno_id, p_pin)` — SECURITY DEFINER, `fn_verificar_pin` contra o cuidador DO TURNO, insert em massa com `on conflict do nothing` (cobre só o que restou), sem movimentação de estoque. (5) `fechar_turno` com as duas filas e retorno `total_ronda`/`total_entre_turnos`. (6) `relatorio_adesao` com a categoria `nao_apurada` no denominador |

O trigger de baixa de estoque **não mudou**: `pendente` cai no mesmo "nenhuma
movimentação" do `nao_tomado` (verificado em teste).

### App (React/PWA)

```
src/
├── App.jsx                          # 4ª aba com contagem; alerta vermelho via CSS
├── lib/erros.js                     # + turno_nao_encontrado / turno_ja_fechado
├── index.css                        # aba-alerta, alerta-critico, pendências
└── pages/
    ├── PendenciasEntreTurnos.jsx    # NOVO — dia → residente; modal reusado;
    │                                #   lote com alerta cheio de tela + TecladoPin
    ├── Ronda.jsx                    # exporta RegistrarDose/horaLocal (reuso);
    │                                #   mensagem de fechamento distingue origens
    └── Adesao.jsx                   # 5ª categoria + legenda curta
```

## 3. Verificações SQL executadas

Smoke test da migration **em transação com ROLLBACK antes do apply** (A1–A9)
e bateria com sandbox determinístico também sob rollback (B1–B11):

| Teste | Resultado |
|---|---|
| A1–A9 (smoke): lacuna de 26 h gera pendências (todas na lacuna, dentro do teto); `doses_do_turno` não vaza; INSERT direto de `pendente` bloqueado; `fechar_turno` bloqueado por `total_entre_turnos`; PIN errado recusa sem gravar; PIN certo grava tudo sem estoque; fila zera e turno fecha; guard continua fechado após o lote; relatório reconhece `nao_apurada` no denominador | OK |
| B1 — lacuna de 7,5 dias com grade controlada: 14 doses esperadas exatas (6+7+1); horário inativo, medicamento inativo, residente inativo e SOS geram zero | OK |
| B2 — fronteira de fuso: dose 23:30 local (02:30 UTC do dia seguinte) agrupada no dia LOCAL correto | OK |
| B3 — ordenação: mais antiga primeiro | OK |
| B4 — teto: flag coerente; jsonb (total, dias_alem_do_teto, doses) bate com contagem independente das linhas | OK |
| B5 — disjunção das filas: nenhuma dose aparece na ronda E nas pendências | OK |
| B6 — tratativa individual (mesmo insert do modal) remove da fila; lote depois cobre só o restante | OK |
| B7 — lote: PIN de OUTRA cuidadora recusado (verificação é contra o cuidador do turno); PIN certo grava N exato; zero movimentação de estoque | OK |
| B8 — relatório: `nao_apurada` na macro e na micro (iguais); denominador = tratadas + lote | OK |
| B9 — `fechar_turno`: doses além do teto NÃO bloqueiam; ronda pendente bloqueia com `total_ronda`; após tratar, fecha | OK |
| B10 — turno fechado normalmente: nada ressurge na abertura seguinte | OK |
| B11 — permissões: authenticated executa listar/resolver; anon negado | OK |

## 4. Critério de pronto — conferido no navegador (viewport 375px)

Cenário: seed limpo + turno antigo fechado há 7,5 dias (lacuna longa;
`criado_em` dos horários retroagido por ser dado recém-semeado) → login →
turno da Débora.

| Item | Resultado |
|---|---|
| (a) Ronda mostra só o turno atual ("Nenhuma dose aguardando…") | OK |
| (b) Aba "Pendências entre turnos (130)" inteira vermelha; contagem certa (130 = SQL) | OK |
| (f) Aviso permanente no topo: 3 dias além do teto, impacto em adesão e estoque | OK |
| Agrupamento por dia (15/07 primeiro) → residente; 0,5 comprimido exibido | OK |
| (c1) Tratativa individual pelo modal da Ronda (4 opções) → contagem 130→129 na aba e no título | OK |
| (c2) Lote: alerta cheio de tela com os 2 impactos; PIN errado → "PIN incorreto. 4 tentativa(s) antes do bloqueio", nada gravado; PIN certo (4444) → 129 gravadas, aba neutra, aviso de sucesso mencionando estoque | OK |
| Banco: 129 `pendente` com **0** movimentações; 1 `tomado_no_horario` com 1 baixa | OK |
| (e) Adesão "Últimos 7 dias": 130 doses, 5 categorias — No horário 1 (0,8%), Pendente (não apurado) 129 (99,2%) — + legenda | OK |
| (d) Encerrar turno libera após as duas filas zeradas (antes: mensagem apontava a aba nova como origem do bloqueio) | OK |
| (g) Reabrir turno: aba neutra, nada ressurge | OK |
| Console do navegador | Sem erros |
| `npm run build` | OK |

## 5. Security advisors

Um item novo e **esperado**: `resolver_pendencias_em_lote` entrou na lista de
funções SECURITY DEFINER executáveis por `authenticated` — mesma categoria já
aceita e documentada de `abrir_turno`, `fechar_turno`, `trocar_pin` e todas as
RPCs de gestão (é intencional: a função é o portão que valida o PIN no banco).
Nenhum outro aviso novo; Leaked Password Protection segue como encerrada na
Sessão #5 (indisponível no Free, mitigada).

## 6. MH-002 — pendência visível antes de abrir o turno (IMPLEMENTADA)

Registrada inicialmente como ideia (fora do escopo do roteiro), foi
**confirmada pelo Guilherme na própria sessão e implementada**: a tela
"Quem está assumindo o turno?" (e a etapa do PIN) mostra um aviso vermelho
com a contagem — "Há N dose(s) de períodos sem turno aberto aguardando
registro. Ao assumir, resolva na aba 'Pendências entre turnos' — se possível,
confirme com quem estava no plantão anterior o que aconteceu." — antes de a
cuidadora digitar o PIN, que é o momento em que ainda dá para perguntar ao
plantão anterior. Sem mudança de banco (reusa `listar_pendencias_entre_turnos`,
já acessível ao usuário autenticado da casa); aviso some quando não há
pendência. Verificado no navegador (375px, console limpo) e `npm run build` OK.

## 7. Pendências para a Sessão #6 (inalteradas + novidades)

1. Deploy/go-live (Railway, URLs no Auth, PWA, LGPD, dados reais, bootstrap
   da Thais) — escopo original da #6, sem mudança.
2. **Novidade para o treinamento das cuidadoras:** explicar a tela nova e a
   diferença entre "não tomada" (falta confirmada) e "Pendente (não apurado)"
   (decisão de não apurar) — o rótulo ajuda, mas vale 1 minuto de conversa.
3. **Cuidado no go-live:** o teto de 5 dias conta a partir do PRIMEIRO turno
   da casa e da criação dos horários — cadastros novos não geram pendência
   retroativa (regra `criado_em`), então a primeira semana não terá ruído
   falso.
4. Guilherme: revisar este relatório, salvar no Drive, commit + push.

## 8. Como testar rapidamente

```bash
npm run dev            # login casa@namicare.app (senha em .env.local)
# 1. Crie a lacuna: com o seed limpo, rode no SQL editor (service role):
#    - retroaja criado_em de horarios/medicamentos (dado recém-semeado):
#      update horarios set criado_em = now() - interval '10 days';
#      update medicamentos set criado_em = now() - interval '10 days';
#    - insira um turno FECHADO antigo (ex.: inicio hoje-9d, fim hoje-7d 12:00)
# 2. Assuma um turno no app → aba "Pendências entre turnos (N)" vermelha
# 3. Trate uma dose pelo modal; resto pelo botão de lote (PIN do turno)
# 4. Adesão (Últimos 7 dias) → categoria "Pendente (não apurado)"
# 5. Encerre o turno; reabra: nada volta

npm run seed -- --reset   # volta ao banco limpo
```
