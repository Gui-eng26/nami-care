# SESSÃO 10 — Ajustes rápidos do pós-demo

> Roteiro de entrada. Três ajustes de baixo/médio risco levantados na demonstração
> com a Thais, para melhorar o piloto antes do go-live. Sem mudança estrutural.
> Anterior: SESSAO_09.md / RELATORIO_SESSAO_09.md

---

## Antes de começar

1. Fonte da verdade: BRIEFING.md, DECISIONS.md (até DEC-038 na abertura),
   CONTEXT.md, ROADMAP.md, RELATORIO_SESSAO_08.md e RELATORIO_SESSAO_09.md. Em
   conflito com a sua memória, os arquivos prevalecem.
2. Banco: exclusivamente o projeto nami-care (ref uvkmvaheupziexlunnno), via
   .mcp.json.
3. Há uma decisão de produto nova (janela de atraso) → registrar como **DEC-039**
   (confira a numeração real antes de gravar; a última é DEC-038). Crie
   SESSAO_10.md e RELATORIO_SESSAO_10.md no padrão das anteriores.
4. **Não tocar no runbook de go-live nem em `limpar-banco`.** O banco segue com o
   seed de teste. Se o seed-demo da Sessão #9 ainda estiver no ar, `npm run seed
   --reset` recompõe a base limpa para o trabalho.

## Contexto e objetivo

A demonstração com a Thais (versão de piloto) validou o produto e levantou
ajustes. Três deles são de baixo/médio risco e independentes entre si; esta
sessão os entrega juntos. Dois ajustes maiores levantados na mesma conversa
(rastreamento por lote/validade e "medicamento da casa") ficam para sessões
próprias — ver "Fora do escopo".

## Parte 1 — Botão "Encerrar turno" no cabeçalho

### O problema
"Encerrar turno" vive hoje dentro da aba Ronda. Navegando por Estoque ou Adesão,
a cuidadora tenta encerrar e precisa voltar à Ronda primeiro — atrito
desnecessário observado no uso real.

### Decisão de design (já tomada — implemente assim)
- Mover "Encerrar turno" para o **canto superior direito do cabeçalho**, visível
  em qualquer aba (Ronda, Adesão, Estoque).
- Ele passa a dividir o cabeçalho com os botões de gestão da Sessão #8 ("Gestão
  residentes" e, para admin, "Gestão equipe"). Compor o layout para caber
  confortavelmente a 375px — "Encerrar turno" é ação de saída, visualmente
  distinta dos botões de gestão (que abrem áreas), não competindo com eles.
- **Comportamento ao tocar (a lógica de fechamento NÃO muda — é a mesma
  `fechar_turno`):**
  - Se houver dose pendente de tratativa (ou pendência entre turnos não
    resolvida), o fechamento é recusado como hoje. A mensagem deve deixar claro
    que há doses a tratar na Ronda **e levar a cuidadora de volta à aba Ronda**,
    para ela não ficar presa em Estoque/Adesão sem entender o que resolver.
  - Se estiver tudo tratado, o turno **encerra normalmente, de qualquer aba** —
    sem exigir voltar à Ronda.

### Escopo
- Mudança em App.jsx (cabeçalho) e no componente da Ronda (o botão sai de lá) +
  CSS do tema. Nenhuma mudança de RPC. A validação de `fechar_turno` permanece no
  banco, intacta.

## Parte 2 — Janela de "atrasado" de 30 → 60 min (DEC-039)

### O problema
A dose vira "atrasada" (destaque vermelho) 30 min após o horário previsto
(DEC-010). No uso real, 30 min é curto para o ritmo da casa — gera sensação de
atraso cedo demais.

### Decisão de produto (já tomada — documente como DEC-039)
- A tolerância antes de uma dose devida ser marcada "atrasada" passa de **30 para
  60 minutos**. DEC-039 revisa a DEC-010 (que fixara os 30 min).
- Efeito consciente e aceito: a dose fica "na hora"/pendente por mais tempo antes
  de saltar como atrasada. Menos alarme precoce; em contrapartida, um atraso real
  demora um pouco mais a chamar atenção visual. Foi a escolha do Guilherme.

### Escopo — atenção: o valor aparece em DOIS lugares no banco
O `interval '30 minutes'` que define "atrasada" está em:
- `doses_do_turno` (migration de turno/ronda, 20260716000700);
- um espelho da mesma expressão dentro da migration de gestão de residentes
  (20260716001000, ~linha 231).
Ambos precisam ir para `'60 minutes'`, via **migration nova** (nunca SQL avulso),
para não ficarem inconsistentes. Conferir se não há um terceiro ponto (buscar
`30 minutes` em todo o schema antes de aplicar). A janela de 15 min de "próxima"
(c_janela) NÃO muda — é outra coisa.
- A DEC-010 e os comentários que citam "30 min" nas migrations passam a referir
  60 (ou nota de que a DEC-039 revisou).

## Parte 3 — Horários no cadastro "+ Medicamento" (cadastro incompleto)

### O problema
O formulário compartilhado de medicamento (FormMedicamento, Sessão #8) tem o campo
"posologia" (texto livre) e o tipo (contínuo/SOS), mas **não cria horários**. A
tabela `horarios` e a RPC `criar_horario` existem e funcionam (é o que a tela
antiga de gestão — residente → medicamento → horários — usa, com o versionamento
da DEC-026), mas o atalho "+ Medicamento" nunca os preenche. Resultado: um
medicamento **contínuo** cadastrado pelo atalho não gera doses na ronda — o
cadastro fica incompleto na prática.

### Decisão de produto (já tomada — implemente assim)
- No cadastro de medicamento **contínuo**, incluir a definição de **horários**
  (um ou mais pares hora + quantidade de dose), reaproveitando a RPC
  `criar_horario` e o mesmo padrão de UI que a tela antiga de gestão já usa.
  Não criar caminho novo de escrita — usar `criar_horario` como ela é.
- Para **SOS**, mantém-se sem horários (dose avulsa) — como já é hoje. A UI de
  horários só aparece para o tipo contínuo.
- Vale para as duas portas que usam o FormMedicamento (o atalho "+ Medicamento"
  da aba Estoque e o cadastro pelo caminho de Residentes), já que compartilham o
  componente — assim o cadastro fica completo pelos dois caminhos.
- A "posologia" em texto livre pode continuar como campo descritivo, mas os
  horários estruturados passam a ser o que efetivamente gera as doses. (Se ficar
  redundante ao ponto de confundir, avaliar tornar a posologia opcional — decisão
  menor, documente o que fizer.)

### Escopo
- Mudança em FormMedicamento.jsx (e onde ele é consumido) + CSS. Reusa
  `criar_horario`/`atualizar_horario` existentes. Sem mudança de schema, sem RPC
  nova. Versionamento da DEC-026 permanece regendo alterações posteriores de
  horário.

## Restrições
- JavaScript apenas; toda mudança de schema/regra via migration (só a Parte 2 tem
  migration); regra no banco, cliente só apresenta.
- Nenhuma mudança na lógica de `fechar_turno`, no ledger, na baixa automática, no
  catálogo (DEC-035) ou na autorização por turno (DEC-038).
- Tema Sereníssima; alvos de toque confortáveis a 375px.

## Fora do escopo desta sessão (sessões próprias)
- **Rastreamento por lote e validade** (levantado na demo): cada entrada de
  estoque com seu próprio lote/validade, sem agrupamento, exibidos também no
  estoque atual por residente. Isso é rastreio por lote — muda o núcleo do ledger
  (a baixa deixa de ser só um número e passa a escolher lote/validade, provável
  FEFO) e tem decisões de produto pendentes. **Sessão própria.** Não começar aqui.
- **"Medicamento da casa"** (SOS sem residente): `idoso_id` NOT NULL, mexe em
  ronda e adesão. Em decisão pelo Guilherme. **Sessão própria.**
- Validade/lote NÃO entram no "+ Medicamento" nesta sessão — a Parte 3 adiciona
  só os horários. Lote/validade vêm com o rastreamento por lote.

## Critério de pronto
1. "Encerrar turno" aparece no cabeçalho em todas as abas. Com dose pendente de
   tratativa, tocar recusa com mensagem clara e leva à Ronda; com tudo tratado,
   encerra de qualquer aba.
2. Uma dose devida sem tratativa só vira "atrasada" após **60 min** do previsto
   (antes, 30) — conferido na ronda com a nova migration aplicada; os dois pontos
   do banco consistentes.
3. Cadastrar um medicamento **contínuo** pelo "+ Medicamento" com horários gera
   doses na ronda no(s) horário(s) definido(s). Um **SOS** continua sem horários.
   O mesmo vale pelo caminho de Residentes.
4. Alterar um horário de medicamento com histórico continua versionando (DEC-026).
5. `npm run build` sem erro; sem regressão em ronda, turno, estoque, adesão,
   catálogo, gestão.

## Encerramento
- Smoke test da migration (Parte 2) em transação com rollback antes do apply;
  bateria SQL cobrindo a fronteira dos 60 min (dose a 45 min = pendente; a 75 min
  = atrasada) e a criação de horários pelo cadastro.
- Conferência no navegador (375px) dos itens do critério de pronto, com turno
  aberto.
- `npm run build`; revisão dos advisors; reset final do seed.
- Gerar RELATORIO_SESSAO_10.md: as três partes, a DEC-039 (revisa a DEC-010), e a
  confirmação de que lote/validade e medicamento-da-casa seguem fora de escopo,
  aguardando sessão própria.
- Atualizar DECISIONS.md (DEC-039; DEC-010 → revisada pela DEC-039), CONTEXT.md e
  ROADMAP.md.
