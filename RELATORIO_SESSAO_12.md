# RELATÓRIO — Sessão #12 (2026-07-22)
## Medicamento da casa (SOS compartilhado) e dose SOS reestruturada

> Entrada: `SESSAO_12.md`. Anterior: `RELATORIO_SESSAO_11.md`.
> Decisões novas: **DEC-044, DEC-045, DEC-046, DEC-047**.
> Migrations: `20260722000500..000900` (5).

---

## 1. O que a sessão resolveu

A Thais tem medicamentos que não pertencem a ninguém em particular: os SOS da
casa — dipirona para dor de cabeça, antitérmico para febre, antiemético para
enjoo. É a caixa comum da bancada. O app exigia dono para todo medicamento
(`medicamentos.idoso_id` NOT NULL), então esse estoque simplesmente não cabia.

O que **não** se aceitou como solução foi afrouxar o dono e deixar o consumo
anônimo. O princípio que governou a sessão inteira:

> O **estoque** pode ser da casa; o **consumo tem sempre um dono.**

"Saiu uma dipirona da casa, não sei pra quem" é exatamente o rastro opaco que o
Nami Care existe para eliminar. Toda dose administrada aponta para o residente
que a tomou — e é na adesão **dele** que ela aparece.

## 2. O desenho (Modelo B)

Três peças, e nada além delas:

**(a) Um residente-sentinela "Da Casa" carrega o estoque compartilhado.**
`medicamentos.idoso_id` **permanece NOT NULL** — o schema de medicamentos não
mudou, e os ~16 pontos do banco que fazem `join idosos` continuam intactos. Um
medicamento da casa é um medicamento normal pendurado nesse residente. Ele herda
lote, validade e FEFO da Sessão #11 sem exceção: nada de estoque foi
reimplementado.

**(b) Sem flag `eh_da_casa` em medicamentos.** Foi avaliada e descartada. Um
medicamento é da casa porque pertence AO residente da casa. O sentinela é
identificado por `idosos.eh_sentinela` (booleano com índice único parcial — no
máximo um), nunca por id hardcodado: nem o código nem o seed dependem de um uuid
fixo. O único lugar que precisa excluí-lo — o seletor de "quem tomou" — apenas
não o inclui na lista.

**(c) Uma coluna nova em `administracoes`: o dono real da dose.** A única mudança
de schema do Modelo B. Sem ela, o consumo do SOS da casa cairia na adesão de um
residente que não existe.

A linha do "Da Casa" nasce de **bootstrap idempotente**
(`fn_bootstrap_residente_da_casa`), não de migration de dados: a migration chama
uma vez, o seed chama a cada `--reset`, e um banco recriado do zero chega ao
mesmo estado sozinho.

## 3. As decisões

### DEC-044 — Residente-sentinela "Da Casa"
Medicamento da casa é **sempre SOS**, garantido por trigger (que pega também o
seed, escrevendo com service role por fora das RPCs): contínuo tem horário de
ronda, e horário é de um residente. O sentinela **não é desativável**
(`residente_da_casa_fixo`) — desativá-lo tiraria o estoque da casa da cobertura e
do fluxo SOS sem que nada tivesse mudado no mundo físico; a caixa comum continua
na prateleira.

Onde ele aparece, tela a tela — exatamente como combinado:

| tela | comportamento |
|---|---|
| Gestão de residentes | **aparece, em vermelho** — é identificação visual, não alerta de erro; fora da contagem de "ativos" |
| "+ Medicamento" (seletor) | **aparece**, destacado e no topo — é assim que uma compra entra no estoque da casa; escondê-lo tornaria o medicamento da casa incadastrável |
| Estoque atual | **seção própria "Medicamentos da casa"**, separada dos residentes |
| Relatório de adesão | **não aparece** (nem como linha, nem no filtro) |
| Seletor de "quem toma" no SOS | **não aparece** |
| Ronda | não aparece por construção — é SOS, não tem grade de horários |

### DEC-045 — `administracoes.idoso_id`, o dono real da dose
Três casos, e **um só caminho preenche**:

| dose | `idoso_id` |
|---|---|
| agendada (contínua) | nulo |
| SOS de medicamento de um residente | nulo — o dono vem do medicamento |
| SOS de medicamento da casa | **preenchido** com quem tomou |

Uma regra de leitura para tudo: `coalesce(administracoes.idoso_id,
medicamentos.idoso_id)`.

Integridade por **trigger**, não por CHECK — a regra depende de uma linha de
`idosos` (o medicamento é da casa?), fora do alcance de um CHECK. Os dois lados
são fechados: SOS da casa **sem** dono é rejeitado, e dose de medicamento de
residente **com** dono também é. Divergência entre dois donos é pior que a
ausência de um, porque parece informação. A imutabilidade da DEC-008 foi
estendida à coluna nova.

### DEC-046 — Adesão pelo dono resolvido
O `coalesce` entrou no trecho de SOS **e** no de doses agendadas. Nas agendadas é
literalmente o mesmo valor de antes (a coluna é sempre nula ali) — escrevê-lo nos
dois lugares deixa **uma** regra na cabeça de quem lê, não duas. O filtro por
residente segue o mesmo dono resolvido.

Consequência desejada: o "Da Casa" **não gera linha de adesão**. Como ninguém "é"
a casa em consumo, nenhuma dose resolve para ele. O resto do relatório —
denominador materializado, as cinco categorias, pendentes do turno aberto,
fronteira de dia no fuso — não mudou.

### DEC-047 — Dose SOS reestruturada (revisa a DEC-014)
A ordem foi invertida: primeiro **quem toma**, depois **qual medicamento**.

1. Residente: todos os ativos, **exceto o "Da Casa"**. A lista independe de haver
   estoque — é justamente o ponto.
2. Medicamento: os SOS **dela** + os SOS **da casa**, numa lista só, com o saldo
   de cada; o da casa leva o selo "Da casa". Os dois coexistem.
3. Quantidade (meio-em-meio) e registro com o **horário real** do momento.
4. Dono da dose gravado conforme a DEC-045.
5. Baixa de estoque: trigger da DEC-008 + FEFO da DEC-042, sem nada novo.

**A dose SOS virou RPC** (`registrar_dose_sos`). Antes era INSERT direto do
cliente; com uma regra a garantir, deixá-la na tela seria pôr regra de negócio
fora do banco. A RPC valida e **normaliza**: recebe sempre quem tomou — é o passo
1 da tela, o cliente não precisa conhecer a regra — e decide se grava ou descarta
o dono. Para fechar a porta, a política de INSERT de `administracoes` passou a
exigir `horario_id` não nulo: **INSERT direto do cliente = dose agendada** (o que
a ronda sempre fez), SOS só pela RPC.

## 4. Migrations

| arquivo | conteúdo |
|---|---|
| `20260722000500_residente_da_casa` | `idosos.eh_sentinela` + único parcial; `fn_idoso_da_casa`; `fn_bootstrap_residente_da_casa` (idempotente) + chamada; trigger "da casa é sempre SOS"; `definir_ativo_residente` recusa desativar o sentinela; `cobertura_estoque` ganha `idoso_da_casa` |
| `20260722000600_dono_da_dose` | `administracoes.idoso_id` + índice parcial; `fn_administracao_dono_valido`; imutabilidade estendida |
| `20260722000700_adesao_dono_real` | `relatorio_adesao` com `coalesce` |
| `20260722000800_dose_sos_reestruturada` | política de INSERT passa a exigir `horario_id`; RPC `registrar_dose_sos` |
| `20260722000900_hardening_sessao_12` | `execute` dos dois helpers internos revogado de `authenticated` (padrão da Sessão #11) |

Cada uma passou por **smoke test em transação com rollback** antes do apply.

## 5. Cliente

- **`DoseSos.jsx`** — reescrito para o fluxo residente → medicamento → quantidade;
  chama a RPC.
- **`Estoque.jsx`** — bloco "Medicamentos da casa" separado; selo na ficha.
- **`GestaoResidentes.jsx`** — "Da Casa" em vermelho, fora da contagem de ativos,
  sem botão de desativar, com explicação na ficha.
- **`NovoMedicamento.jsx`** — "Da Casa" no topo do seletor, destacado.
- **`FormMedicamento.jsx`** — prop `daCasa`: o seletor de tipo dá lugar a uma nota
  ("da casa é sempre SOS"); o banco recusaria de todo jeito, a tela só não oferece.
- **`Adesao.jsx`** — sentinela fora do filtro de residente.
- **`erros.js`** — mensagens dos códigos novos.
- **`index.css`** — vermelho de identificação do "Da Casa".
- **Seed** — bootstrap do sentinela + 3 SOS da casa (dipirona, paracetamol,
  metoclopramida) com lote e validade; `seed-historico`/`seed-demo` ganharam duas
  doses SOS **da casa** atribuídas a residentes, para o cenário de adesão existir
  pronto.

## 6. Verificação

**Bateria SQL em rollback, contra o banco já semeado** — 10 casos, todos passando:

1. FEFO do medicamento da casa cruzando dois lotes (zera o de validade mais
   próxima, completa no seguinte);
2. adesão do residente que tomou **+1** após o SOS da casa;
3. "Da Casa" com **0** doses de adesão no período;
4. SOS próprio do residente inalterado, `idoso_id` nulo;
5. SOS da casa **sem** dono → rejeitado;
6. SOS de residente **com** dono → rejeitado;
7. SOS da caixa de outro residente → `medicamento_de_outro_residente`;
8. sentinela como "quem toma" → recusado;
9. medicamento contínuo na dose SOS → `medicamento_nao_sos`;
10. sentinela não desativável → `residente_da_casa_fixo`;

mais **dose agendada da ronda inalterada** (mesmo insert, `idoso_id` nulo) e o
**invariante de estoque da Sessão #11** (`sum(lotes) == ledger`) verificado nos 27
medicamentos: **0 divergências**.

`npm run build` sem erro. Seed resetado com `--com-historico`: 11 idosos + "Da
Casa", 27 medicamentos (6 SOS, 3 deles da casa), 6 doses SOS.

**Advisors:** as duas funções novas aparecem na mesma classe WARN pré-existente de
todas as RPCs do projeto (`authenticated_security_definer_function_executable` —
uma casa, um usuário Supabase, DEC-011/019). Os dois **helpers internos** desta
sessão saíram da lista pela migration de hardening. Nada novo em espécie.

**Conferência no navegador a 375px — feita, ponta a ponta**, com o Guilherme
logado na casa. Percurso e resultado:

1. **Cadastro de SOS da casa pelo "+ Medicamento"** — "Da Casa" no topo do
   seletor, destacado; o seletor de tipo dá lugar à nota "sempre SOS"; sem bloco
   de horários; com estoque mínimo, lote e validade. Buscopan 10 mg gravou como
   `sos`, dono "Da Casa", lote `CASA-BSC-01`, validade 30/11/2027, 15 un,
   `lotes == ledger`. **(critério 1)**
2. **Gestão de residentes** — "Da Casa" em vermelho com selo e explicação, e
   **fora da contagem** ("Residentes (11 ativos)"); a ficha dele não tem botão de
   desativar. **Estoque atual** abre "Medicamentos da casa" em seção própria
   (borda vermelha) **antes** de "Estoque por residente", que começa direto na
   Alzira. **(critério 2)**
3. **SOS da casa** — Cecília Prado → lista trouxe o **Paracetamol 750 dela
   primeiro**, depois os três da casa com selo "Da casa" **(critério 4,
   coexistência)**; escolhido o Paracetamol 500 da casa, a tela avisa "sai do
   estoque da casa; a dose entra na ficha da Cecília Prado". Gravou `horario_id`
   nulo, `idoso_id` = Cecília, dono do medicamento "Da Casa", estoque 20 → 19,
   `lotes == ledger`. Na aba Adesão da Cecília: **"Doses SOS no período: 1"**.
   **(critério 3)**
4. **SOS próprio** — Paracetamol 750 da Cecília: `idoso_id` **nulo**, estoque
   18 → 17. Sem a frase do estoque da casa, corretamente. **(critério 4)**
5. **"Da Casa" ausente** do seletor de "quem toma" (11 residentes) e do filtro de
   residente da Adesão. **(critério 5)**
6. **Ronda inalterada** — a dose agendada pendente (Alzira, Sinvastatina 19:00)
   registrou normalmente (18 → 19 tratadas), com `idoso_id` nulo. Isto era o
   ponto de risco da sessão: a política de INSERT nova poderia ter quebrado o
   caminho da ronda, e não quebrou. **(critério 6)**

Um ajuste saiu da conferência: a ficha do "Da Casa" exibia "(DEC-044)" na tela da
cuidadora — jargão interno, contra o padrão de linguagem do app. Removido.

Ao fim, `npm run build` e **reset do seed**, apagando o Buscopan e as doses de
teste: base de volta a 11 residentes + "Da Casa", 27 medicamentos, **0
divergências** de estoque.

### Observação para uma sessão futura (fora do escopo desta)
A Cecília Prado tem "Alergia a dipirona" nas observações, e a **Dipirona da casa
aparece na lista de SOS dela** — como aparece para todo mundo, por construção. O
app nunca teve checagem de alergia (a observação do residente é texto livre), e o
estoque compartilhado não criou o problema: só o tornou mais visível, porque agora
um mesmo medicamento é oferecido a todos. Vale conversar com a Thais se a
observação do residente deve virar um alerta no passo de escolha do medicamento.

## 7. Fora de escopo (inalterado)

- Categoria "agudo" (contínuo/agudo ≠ contínuo/SOS).
- Início de tratamento / abertura de caixa.
- Alerta de vencimento próximo.
- Medicamento da casa do tipo **contínuo/agendado** — não existe por decisão
  (DEC-044); se um dia a casa precisar, é decisão nova.
- Múltiplas "casas"/setores — o sentinela é único, por índice.
- Escolha manual de lote na perda.

**Nada do runbook de go-live foi tocado.**
