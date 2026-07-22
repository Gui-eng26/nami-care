# SESSÃO 12 — Medicamento da casa (SOS compartilhado) e SOS reestruturado

> Roteiro de entrada. Último ajuste do backlog levantado com a Thais, adiado três
> vezes de propósito por ser o mais estrutural: medicamentos SOS que pertencem à
> casa (não a um residente), com o consumo sempre atribuído a quem tomou.
> Anterior: SESSAO_11.md / RELATORIO_SESSAO_11.md

---

## Antes de começar

1. Fonte da verdade: BRIEFING.md, DECISIONS.md (até DEC-043 na abertura),
   CONTEXT.md, ROADMAP.md, RELATORIO_SESSAO_11.md. Em conflito com a sua memória,
   os arquivos prevalecem.
2. Banco: exclusivamente o projeto nami-care (ref uvkmvaheupziexlunnno), via
   .mcp.json.
3. Há decisões de produto novas → registrar como **DEC-044+** (confira a
   numeração real; a última é DEC-043). Crie SESSAO_12.md e
   RELATORIO_SESSAO_12.md no padrão das anteriores.
4. Não tocar no runbook de go-live. Banco segue com seed de teste; `npm run seed
   --reset` recompõe a base. **A Thais ainda não usa o app** — sem dados reais em
   risco. Ver "Sequenciamento" no fim: esta feature deve entrar ANTES do go-live.

## Contexto e objetivo

A Thais tem medicamentos que não pertencem a um residente específico — os SOS da
casa (dipirona para dor de cabeça, antitérmico para febre, antiemético para
enjoo). Hoje o app exige que todo medicamento pertença a um residente
(`medicamentos.idoso_id` é NOT NULL). O objetivo é permitir esse estoque
compartilhado da casa, **mantendo o rastro clínico**: quando alguém toma um SOS
da casa, o consumo é registrado no nome de quem tomou (entra na adesão dela),
mesmo o estoque sendo da casa.

### Princípio que guia toda a sessão (Modelo B)
O **estoque** pode ser da casa; o **consumo tem sempre um dono**. "Saiu uma
dipirona da casa, não sei pra quem" é exatamente o rastro opaco que o Nami Care
existe para eliminar. Toda dose administrada aponta para o residente que a tomou.

### Arquitetura escolhida (decidida com o Guilherme — implemente assim, sem variar)
Depois de avaliar as alternativas, ficou definido:
- **Um residente-sentinela "Da Casa"** carrega os medicamentos compartilhados.
  `medicamentos.idoso_id` permanece **NOT NULL** — o schema de medicamentos NÃO
  muda, e os ~16 pontos do banco que fazem `join idosos` continuam intactos. O
  "Da Casa" é um registro real em `idosos`, marcado de forma reconhecível.
- **Sem flag `eh_da_casa`** — foi avaliada e descartada. O "Da Casa" é
  identificado por ser aquele residente específico; o único lugar que precisa
  excluí-lo (o seletor de "quem tomou") simplesmente não o inclui.
- **Uma coluna nova em `administracoes`** para o residente que efetivamente tomou
  — é a única mudança de schema inevitável do Modelo B (detalhes na Parte 2).

## Parte 1 — O residente-sentinela "Da Casa" (DEC-044)

### Decisão de produto (já tomada — documente como DEC-044)
- Criar (via seed/bootstrap, não migration de dados) um residente reservado
  representando a casa. Nome reconhecível ("Da Casa" / "Medicamentos da casa" —
  escolha o rótulo que ficar claro na UI) e um jeito estável de identificá-lo no
  código (ex.: um campo booleano `eh_sentinela` em `idosos`, OU um id conhecido
  documentado). Um booleano em `idosos` é mais limpo que hardcodar id —
  decida e documente. **Este booleano é em `idosos`, não em `medicamentos`** —
  não confundir com a flag `eh_da_casa` descartada.
- Medicamentos da casa são medicamentos normais pendurados nesse residente, com
  `tipo = 'sos'` obrigatoriamente (Parte 4). Herdam TODO o comportamento da
  Sessão 11: lote, validade, FEFO — sem nada novo no estoque.

### Onde o "Da Casa" aparece e onde é escondido (as telas)
Confirmado com o Guilherme, tela a tela:
1. **Gestão de residentes:** APARECE, destacado em vermelho — vira identificação
   visual da casa. Operacionalmente ok; não esconder.
2. **Cadastro de medicamento / "+ Medicamento" (seletor de residente):** APARECE
   — é crucial, é assim que uma compra/entrada é associada ao estoque da casa.
3. **Relatório de adesão:** NÃO aparece como linha própria — resolvido pela Parte
   3 (a adesão passa a contar pelo residente que tomou, não pelo dono do
   medicamento; como ninguém "é" o Da Casa em consumo, ele não gera linha).
4. **Estoque atual:** aparece como **seção separada "Medicamentos da casa"**, não
   no meio dos residentes.
5. **Ronda:** não tem doses agendadas (medicamentos da casa são SOS, sem
   horário) — confirmar que não surge como residente vazio/estranho. Não é
   bloqueante.
6. **Seletor de "quem tomou" no SOS:** NÃO aparece (ninguém toma "como a casa") —
   ver Parte 4.

## Parte 2 — Dono real da dose em `administracoes` (DEC-045)

### O problema (a razão da única mudança de schema)
Hoje `administracoes` não tem "quem tomou": o residente é derivado via
`administracoes.medicamento_id → medicamentos.idoso_id`. Para um medicamento da
casa, essa corrente aponta para o "Da Casa", não para quem tomou. Sem um dono
direto na dose, o consumo do SOS da casa cairia na adesão do "Da Casa" — o rastro
clínico se perderia.

### Decisão de produto (já tomada — documente como DEC-045)
- Adicionar coluna **`idoso_id` (nullable)** em `administracoes` = o residente que
  efetivamente tomou a dose. FK para `idosos`.
- **Preenchimento (regra clara):**
  - Dose agendada (contínua) → coluna **nula**. Nada muda no fluxo da ronda.
  - Dose SOS de medicamento **de um residente** → coluna **nula** (o dono já vem
    do medicamento).
  - Dose SOS de medicamento **da casa** → coluna **preenchida** com quem tomou.
    É o único caminho que preenche.
- A coluna existe para todas as linhas (uma coluna é única na tabela), mas só é
  usada no caso do medicamento da casa; nos demais fica nula e é ignorada. **O
  fluxo da dose agendada não muda em nada** — nem o insert, nem a tela da ronda.
- **Resolução do dono (uma regra, vale para todos):** o dono de uma dose é
  `coalesce(administracoes.idoso_id, medicamentos.idoso_id)` — o residente-que-
  tomou se preenchido, senão o dono do medicamento. Aplica-se na adesão (Parte 3)
  e em qualquer lugar que hoje deriva o residente de uma administração.

### Integridade
- Constraint recomendada: se o medicamento da dose é do "Da Casa", então
  `administracoes.idoso_id` é obrigatório (não pode ficar órfão); se não é do "Da
  Casa", `administracoes.idoso_id` deve ser nulo (evita divergência entre os dois
  donos). Implementar como CHECK/trigger conforme couber — documentar.
- `administracoes` continua imutável após gravada (DEC-008/imutabilidade) — a
  coluna nova entra no insert, não em update posterior.

## Parte 3 — Adesão conta pelo dono real (DEC-046)

### O problema
`relatorio_adesao` hoje, no trecho de SOS (`where a.horario_id is null`), atribui
o consumo pelo `medicamento.idoso_id`. Para o SOS da casa, isso apontaria para o
"Da Casa".

### Decisão de produto (já tomada — documente como DEC-046)
- No cálculo das SOS do relatório, o residente da dose passa a ser resolvido por
  `coalesce(administracoes.idoso_id, medicamentos.idoso_id)` (DEC-045). Assim a
  dipirona da casa que a dona Maria tomou entra na adesão **da Maria**, e o "Da
  Casa" não gera linha de adesão própria.
- O restante do relatório (doses agendadas, denominador, categorias — DEC-030)
  **não muda**. Só o trecho de SOS muda a forma de achar o dono.
- O filtro por residente (`p_idoso_id`) passa a considerar o dono resolvido, para
  a Maria ver na adesão dela também o que tomou da casa.

## Parte 4 — SOS reestruturado (DEC-047)

### O problema
Hoje `DoseSos.jsx` monta a lista a partir do estoque SOS **por residente**: só
aparece quem já tem um medicamento SOS próprio cadastrado, e o medicamento vem
preso ao residente. Não há como dar um SOS da casa a um residente qualquer.

### Decisão de produto (já tomada — implemente o fluxo assim)
Inverter a ordem: primeiro **quem toma**, depois **qual medicamento**. Fluxo novo:
1. **Escolher o residente** — lista de **todos os residentes ativos**, EXCETO o
   "Da Casa" (ninguém toma "como a casa"). É aqui que o "Da Casa" é escondido —
   por simplesmente não entrar na lista, sem precisar de flag.
2. **Escolher o medicamento** — os SOS ativos **daquele residente** MAIS os SOS
   **da casa** (do "Da Casa"), numa lista só. Os dois coexistem (confirmado): a
   Maria pode ter um SOS particular dela e também tomar da caixa comum. Mostrar o
   saldo/estoque de cada, como hoje.
3. **Confirmar a quantidade** (1 cp, 30 gts, meio-em-meio preservado).
4. **Registrar automaticamente com o horário real** do momento (a dose SOS já é
   `horario_id` nulo; registrar com `now()` no fuso da casa).
5. **Gravar o dono da dose:** se o medicamento escolhido é da casa, preencher
   `administracoes.idoso_id` com o residente do passo 1; se é medicamento próprio
   do residente, deixar nulo (o dono vem do medicamento). (DEC-045)
6. **Baixa de estoque:** fluxo atual do medicamento escolhido — trigger de baixa
   + FEFO (Sessão 11), sem nada novo.
7. A dose entra na **adesão do residente do passo 1** (Parte 3).

### Nota de implementação (não é decisão do Guilherme)
Hoje a dose SOS é um INSERT direto do cliente em `administracoes`. Como agora há
uma regra a garantir (medicamento da casa exige o dono da dose; medicamento de
residente exige que fique nulo), avaliar mover este fluxo específico para uma
**RPC** (validação no banco), em vez de insert direto. A dose agendada da ronda
pode continuar como está. Decida pelo que mantiver a integridade da DEC-045 sem
retrabalho; documente.

## Restrições
- JavaScript apenas; toda mudança de schema/regra via migration, nunca SQL
  avulso. Regra no banco; cliente só apresenta.
- **`medicamentos.idoso_id` permanece NOT NULL** — o schema de medicamentos não
  muda. A única mudança de schema é a coluna nova em `administracoes` (DEC-045).
- **A ronda e a dose agendada não mudam** em comportamento nenhum. Toda a
  novidade fica contida no residente-sentinela, na coluna nova (usada só no SOS
  da casa) e no fluxo SOS reestruturado.
- Estoque/lote/validade/FEFO da Sessão 11 valem para o medicamento da casa sem
  exceção — não reimplementar nada de estoque.
- Catálogo (DEC-035): o medicamento da casa também nasce do catálogo, como
  qualquer outro.
- Tema Sereníssima; 375px.

## Fora do escopo (não começar)
- Categoria "agudo" (contínuo/agudo ≠ contínuo/SOS) — segue fora.
- Início de tratamento / abertura de caixa — segue fora.
- Alerta de vencimento — segue fora.
- Medicamento da casa do tipo **contínuo/agendado** — não existe: medicamento da
  casa é sempre SOS (Parte 4). Se algum dia a casa precisar de um contínuo
  compartilhado, é decisão nova.
- Múltiplas "casas"/setores — o sentinela é único.

## Critério de pronto
1. Existe o residente "Da Casa"; cadastrar um medicamento SOS nele pelo "+
   Medicamento" (com lote/validade, Sessão 11) funciona.
2. Gestão de residentes mostra o "Da Casa" destacado em vermelho; o estoque atual
   mostra "Medicamentos da casa" em seção separada.
3. Dar um SOS da casa para a dona Maria: fluxo residente→medicamento→qtd,
   registra com horário atual, baixa FEFO do estoque da casa, e a dose aparece na
   **adesão da Maria** (não do "Da Casa").
4. Dar um SOS **próprio** da Maria continua funcionando e coexiste na mesma lista
   do passo de medicamento.
5. O "Da Casa" **não** aparece no seletor de "quem toma" nem gera linha no
   relatório de adesão.
6. Dose agendada (contínua) na ronda **inalterada** — mesmo insert, mesma tela,
   `administracoes.idoso_id` nulo.
7. Constraint: SOS da casa sem residente-que-tomou é rejeitado; dose de
   medicamento de residente com `idoso_id` preenchido é rejeitada (ou
   normalizada) — sem divergência de dono.
8. Invariante de estoque da Sessão 11 (soma dos lotes == ledger) preservado para
   os medicamentos da casa.
9. `npm run build` sem erro; sem regressão em ronda, turno, adesão (agendadas),
   estoque, catálogo, gestão, pendências entre turnos.

## Encerramento
- Smoke test de cada migration em transação com rollback antes do apply.
- Bateria SQL cobrindo: coluna nova e constraint de dono (os três casos:
  agendada nula, SOS de residente nula, SOS da casa preenchida); adesão contando
  SOS da casa no dono real via coalesce; SOS de residente inalterada; baixa
  FEFO do medicamento da casa; invariante de estoque.
- Conferência no navegador (375px): cadastro de SOS da casa, fluxo SOS
  reestruturado (as duas origens de medicamento), adesão da Maria refletindo o
  consumo da casa, ronda agendada inalterada, seção "Medicamentos da casa" no
  estoque, "Da Casa" vermelho na gestão.
- npm run build; revisão dos advisors; reset final do seed (o seed passa a criar
  o residente "Da Casa" + ao menos um SOS da casa, para o cenário existir).
- Gerar RELATORIO_SESSAO_12.md: o desenho (sentinela + coluna de dono, sem flag,
  schema de medicamentos intocado), as DEC-044..047, e o que seguiu fora de
  escopo.
- Atualizar DECISIONS.md (DEC-044..047; anotar que a DEC-014/dose SOS foi
  reestruturada e a DEC-030/adesão passou a resolver o dono por coalesce),
  CONTEXT.md e ROADMAP.md.
