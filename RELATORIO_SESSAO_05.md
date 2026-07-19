# RELATÓRIO — Sessão Claude Code #5

> Relatório de adesão (BRIEFING §6 item 10) — o último item de produto do MVP.
> Data: 2026-07-18 | Modelo: Claude Fable 5 | Roteiro: `SESSAO_05.md`

---

## 1. Resumo executivo

A Sessão #5 foi concluída integralmente. O relatório de adesão está no ar
como terceira aba de operação (Ronda | Estoque | **Adesão**), com visão da
casa e por residente, calendário livre + atalhos, os quatro percentuais
calculados no banco, pendentes à parte e SOS como contagem absoluta. Todos
os números da tela foram conferidos contra contagem manual por SQL — mesma
disciplina da conferência saldo × ledger da Sessão #4.

O deploy previsto originalmente para esta sessão foi **movido para a
Sessão #6** (reordenação deliberada, não corte): com a adesão pronta, o MVP
de produto está completo e a #6 fica dedicada a deploy, dados reais e
go-live.

**Decisões novas:** DEC-030 (modelo de cálculo: denominador = doses
materializadas, classificação pelo status), DEC-031 (aba de operação, sem
PIN de gestão — indicadores visíveis a toda a equipe) e DEC-032 (residente
desativado: histórico conta, macro inclui, selo na micro).

**Banco ao final da sessão:** resetado para o estado limpo do seed
(4 cuidadoras, 11 residentes, 24 medicamentos, 850 unidades, 0 turnos e
0 administrações).

## 2. Premissas verificadas ANTES da agregação (§0 do roteiro)

| Premissa | O que o schema real mostrou |
|---|---|
| Valores de `status` | Constraint com exatamente `tomado_no_horario`, `tomado_atrasado`, `nao_tomado`, `recusado` — as 4 categorias do relatório mapeiam 1:1 |
| De onde sai a classificação | **Do status gravado, nunca de timestamps.** Confirmado no app (Ronda.jsx): o registro tardio de dose tomada no horário envia `registrado_em = prevista_em` — comparar timestamps classificaria errado exatamente esses casos. O seed de histórico reproduz esse padrão de propósito (30% dos "no horário" com `registrado_em = prevista_em`) |
| Dose SOS | `horario_id IS NULL` é o critério, e a constraint `administracoes_prevista_so_na_ronda` garante `prevista_em` nulo junto — não há outro caminho. O instante do fato SOS é `registrado_em` |
| Fuso | `fn_fuso_casa()` = `America/Sao_Paulo`; toda fronteira de dia do relatório usa esse fuso (testado com dose SOS às 22:10 local, que cai no dia seguinte em UTC) |

## 3. O que foi construído

### Migration nova (aplicada no projeto e espelhada no repo)

| Arquivo | Conteúdo |
|---|---|
| `20260718000100_relatorio_adesao.sql` | RPC `relatorio_adesao(p_inicio date, p_fim date, p_idoso_id uuid default null)` → jsonb com qtd + % das 4 categorias, `pendentes`, `devidas_ate_agora` e `sos`. SECURITY INVOKER (roda com o RLS do chamador); EXECUTE revogado de `public`/`anon`. Denominador = linhas materializadas (DEC-030); pendentes vêm de `doses_do_turno` do turno aberto — **reuso da fonte única de slots da Sessão #2, nenhuma lógica duplicada** (a alternativa de reimplementar a grade cairia no mesmo custo já registrado na MH-001). Percentuais no banco (`round(x*100.0/total, 1)`; nulos com total 0). Macro = micro sem filtro: um único caminho de cálculo |

### Seed com histórico (`npm run seed -- --com-historico`)

`scripts/seed-historico.js`, chamado pelo `seed.js` (a flag implica reset).
Gera ~7 dias respeitando TODAS as regras do banco:

- turnos abertos/fechados **pelas RPCs** `abrir_turno`/`fechar_turno` (um
  por dia, cuidadoras em rodízio); administrações inseridas só com o turno
  aberto da cuidadora (trigger); baixa de estoque pelo trigger de sempre;
- D-6..D-1 completos + **hoje parcial**: doses vencidas há mais de 45 min
  tratadas, as recentes ficam sem tratativa; o turno de hoje fica **aberto**
  (Débora) com `inicio` recuado para 06:00 — único ajuste direto (UPDATE em
  `turnos.inicio` via service role, documentado no cabeçalho do script),
  para as pendências aparecerem de forma determinística;
- 4 status distribuídos por PRNG de semente fixa (reprodutível); Iracema
  recusa com frequência à noite, como na observação do cadastro;
- 4 doses SOS em 3 residentes e 3 dias (uma às 22:10, cruzando a fronteira
  UTC de propósito);
- **mudança de posologia no meio do período pelo caminho oficial**
  (DEC-026): Sinvastatina da Alzira 1×/dia (20:00) até D-3; em D-2,
  `atualizar_horario` versiona 20:00 → 19:00 (linha antiga desativada) e
  `criar_horario` adiciona 08:00 — 2×/dia dali em diante;
- estoques iniciais do seed aguentam os 7 dias sem reforço (conferido med a
  med); a Sinvastatina termina com saldo ~2 e **alerta de reposição ativo**
  — de propósito, para a tela de estoque também ter o que mostrar.

Execução de referência: 185 doses de ronda (145 no horário, 18 atrasadas,
7 recusadas, 15 não tomadas) + 4 SOS. `npm run seed -- --reset` continua
gerando o banco limpo de sempre.

### App (React/PWA)

```
src/
├── App.jsx            # terceira aba "Adesão" (operação, sem PIN — DEC-031)
├── lib/erros.js       # + periodo_invalido
├── index.css          # seção "adesão": atalhos, barras, aviso-alerta
└── pages/Adesao.jsx   # NOVO — atalhos + calendário livre + seletor de
                       #   residente; só apresenta o jsonb da RPC
```

- Atalhos Hoje/Ontem/Últimos 7 dias/Este mês apenas pré-calculam as duas
  datas e alimentam o mesmo caminho do calendário livre — sem query nova.
- Rótulos legíveis (padrão DEC-027): "No horário", "Atrasadas",
  "Recusadas", "Não tomadas"; contexto "27 de 28 doses devidas até agora já
  têm tratativa"; aviso âmbar para pendentes ("fora dos percentuais até ser
  registrada"); SOS com a explicação de por que não tem percentual.
- Residente desativado aparece na lista com "— inativo" (DEC-032).
- Nenhum percentual calculado no JavaScript.

## 4. Verificações executadas

| Critério | Resultado |
|---|---|
| Smoke test da migration em transação com ROLLBACK antes do apply (5 asserções: banco limpo zera tudo com % nulo, período invertido recusado, residente inexistente recusado, grants authenticated/anon) | OK |
| Bloco 1 — "Hoje" × contagem manual (status a status, pendentes, SOS) | OK — 27 doses, 23/2/1/1, bate |
| Bloco 2 — versionamento: doses/dia da Sinvastatina | OK — 1/dia (12–15/07), 2/dia (16–18/07) |
| Bloco 3 — macro = Σ micros (total e SOS, 11 residentes) | OK — 185 = 185, 4 = 4 |
| Bloco 4 — fronteira de fuso: SOS 22:10 local (01:10 UTC do dia seguinte) | OK — conta no dia 15 local, zero no dia 16 |
| Bloco 5 (rollback) — vencida sem tratativa vira pendente FORA do denominador; dose futura fora de tudo | OK |
| Bloco 6 (rollback) — residente desativado: macro inalterada, micro funciona | OK |
| Bloco 7 (rollback) — authenticated lê os mesmos números; anon negado (`insufficient_privilege`) | OK |
| Conferência tela × SQL no navegador (viewport 375px): Hoje (27; 85,2/7,4/3,7/3,7), Últimos 7 dias (185; 78,4/9,7/3,8/8,1; SOS 4), micro Alzira (24 doses — mudança de posologia somando certo), dia único 15/07 da Cecília (1 não tomada = 100%; SOS 1), caso pendente (banner "27 de 28… 1 dose sem tratativa") | OK — console sem erros |
| `npm run build` | OK |
| Security advisors | Nenhum aviso novo (a RPC nova é SECURITY INVOKER e não entra na lista de SECURITY DEFINER; demais avisos já documentados nas sessões anteriores) |
| Reset final do seed | OK — banco limpo |

**Ajustes feitos durante a verificação:** concordância de plural em dois
textos da tela ("1 dose planejada", "até ser registrada") — detectados na
conferência do navegador e reverificados.

## 5. Pendência antiga encerrada (Sessão #2)

**Leaked Password Protection:** o recurso é **indisponível no plano Free**
do Supabase (exige plano pago). Mitigação adotada e suficiente para o
contexto: o usuário único da casa (`casa@namicare.app`) usa senha aleatória
forte gerada por script (não é senha humana reutilizada — checagem contra
vazamentos não agrega), e `Minimum password length` = 12 no Auth. O aviso
do advisor permanece visível e está aceito/documentado. **Pendência
encerrada.**

## 6. Pendências e riscos para a Sessão #6 (deploy e go-live)

1. **Deploy + dados reais** (escopo da #6): Railway, URLs no Supabase Auth,
   PWA no celular da casa, bootstrap da Thais como admin, última contagem
   manual como estoque inicial. Termo LGPD **antes** dos dados reais.
2. **Ícones PNG do PWA** (192/512) antes do teste de instalação.
3. **Lacuna de cobertura de turnos** (limite documentado na DEC-030): slot
   que vence sem nenhum turno aberto não entra em turno algum — não vira
   pendente nem "não tomada"; some do denominador. Hoje a ronda tem o mesmo
   comportamento (herdado da Sessão #2). No piloto a cobertura é contínua;
   observar na primeira semana e, se houver lacunas reais, tratar em sessão
   futura (ex.: slots órfãos entrarem no próximo turno aberto).
4. **Ideias registradas, não construídas:** motivo de recusa agregado por
   medicamento (futuro); extrato de movimentações de estoque por período
   ("acuracidade de estoque") — candidata a sessão própria no ROADMAP;
   desempenho por cuidador — decidido NÃO construir (mudaria a natureza da
   ferramenta).
5. O seed `--com-historico` deixa um turno **aberto** de propósito; para
   voltar ao estado limpo, `npm run seed -- --reset`.

## 7. Como rodar / testar

```bash
npm install
npm run dev                        # http://localhost:5173
# login: casa@namicare.app / senha em .env.local (CASA_SENHA)
# PINs de teste: Ana 1111 (ADMIN), Beatriz 2222, Carlos 3333, Débora 4444

npm run seed -- --com-historico    # ~7 dias de histórico p/ testar a adesão
                                   # (deixa o turno de hoje aberto — Débora)
# Aba "Adesão": atalhos Hoje/Ontem/7 dias/Este mês, calendário livre,
# seletor de residente ("Toda a casa" = visão macro)

npm run seed -- --reset            # volta ao banco limpo de sempre
```
