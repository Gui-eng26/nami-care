# Sessão 6 — Nami Care

## Antes de começar
1. Leia BRIEFING.md, DECISIONS.md (DEC-001 a DEC-034), CONTEXT.md,
   ROADMAP.md e RELATORIO_SESSAO_05_5.md. Eles são a fonte da verdade —
   em caso de conflito com sua memória, os arquivos prevalecem.
2. Banco: TODA operação Supabase usa exclusivamente o projeto nami-care
   (ref uvkmvaheupziexlunnno), conforme o .mcp.json na raiz.
3. Reordenação deliberada: o ROADMAP previa deploy nesta sessão — foi
   movido para a Sessão 7. Esta sessão entrega catálogo de medicamentos
   + extrato de movimentação de estoque. As decisões novas são DEC-035 e
   DEC-036.

## Contexto e objetivo

Antes do deploy, precisamos de uma visão consolidada de movimentação de
estoque — quem consome o quê, quanto sobra, o que precisa de reposição
prioritária. Duas entregas nesta ordem (a segunda depende da primeira):
1. Catálogo de medicamentos (correção estrutural de dados)
2. Extrato de movimentação de estoque (a tela que motivou a sessão)

## Parte 1 — Catálogo de medicamentos (DEC-035)

### O problema
Hoje medicamentos.idoso_id é obrigatório: cada residente tem seu próprio
registro de medicamento, mesmo quando o remédio é fisicamente o mesmo de
outro residente (ex.: dois residentes tomando Losartana 50mg). Não existe
elo entre os dois registros. Para agrupar "mesmo medicamento, N
residentes" na tela nova, comparar por texto (nome + dosagem + forma
farmacêutica) foi descartado deliberadamente: frágil por natureza
(divergência de digitação cria falso negativo; qualquer normalização que
tente compensar arrisca falso positivo — juntar remédios diferentes). O
estoque em si (saldo, ledger) permanece sempre separado por residente —
isso é intencional e não muda: custo e consumo são cobrados
individualmente por residente.

### Decisão de produto (já tomada — implemente assim)
Catálogo construído organicamente, sem fonte externa (sem importar
bulário/CMED). Primeiro cadastro de um remédio cria o item do catálogo;
cadastros seguintes reaproveitam por seleção humana, nunca por
comparação de texto.

### Escopo
- Tabela nova catalogo_medicamentos (nome, dosagem, forma_farmaceutica,
  criado_em). Sem idoso_id — é da casa, não do residente.
- medicamentos.catalogo_id (FK, NOT NULL ao final da migration).
- Backfill dos medicamentos já existentes no seed: um catálogo por
  combinação exata de (nome, dosagem, forma_farmaceutica) hoje presente
  no seed, com os medicamentos correspondentes apontando pra ele.
- Cadastro de medicamento (Gestão > Residentes > medicamentos) —
  SEM regressão. Campo de busca no catálogo por nome ao criar; selecionou
  item existente, nome/dosagem/forma vêm do catálogo; não achou, "criar
  novo item do catálogo" cria catálogo e medicamento juntos. posologia,
  tipo, estoque_minimo e ativo continuam por residente. Editar medicamento
  já vinculado: nome/dosagem/forma não editáveis por texto livre; trocar
  exige a mesma busca/seleção. Prescrição versionada (DEC-026) intocada.

## Parte 2 — Extrato de movimentação de estoque (DEC-036)

### Decisão de produto (já tomada — implemente assim)
Fica DENTRO da aba Estoque existente, não em aba nova. Seletor no topo
(segmented control) alterna entre "Estoque atual" (visão da Sessão #4,
padrão ao abrir, inalterada) e "Extrato de movimentações" (nova, somente
leitura). Os rótulos comunicam diferença de FUNÇÃO.

### Escopo — visão consolidada (por catálogo)
- Duas sub-abas: Contínuo e SOS. Calendário no padrão da aba Adesão.
- Lista agrupada por catalogo_id, ordenada do pior caso pro melhor:
  contínuo por cobertura_dias; SOS por distância entre saldo e
  estoque_minimo. Com 2+ residentes, ordenar pelo pior valor do grupo;
  badge "N residentes"; clicar expande o detalhe por residente.
- Item com residente/medicamento inativo aparece com selo, sem alerta.
- Clicar num item (ou num residente do detalhe) abre o extrato daquele
  medicamento_id no período.

### Escopo — extrato por medicamento
- Lista de movimentacoes_estoque no período, mais recente primeiro.
- Cor por DIREÇÃO (sinal da quantidade), não por tipo: verde entrada,
  vermelho saída. ajuste_contagem pode ser os dois — depende do SINAL.
- Rótulo de subtipo por linha; filtro por tipo/subtipo combinável com o
  período. Tela só de leitura.

### Fonte de dados
- Reaproveitar cobertura_estoque e saldo_estoque. RPC/view nova para a
  lista consolidada por catálogo e para o extrato filtrado por
  medicamento+período; agregação no banco, cliente só apresenta.

## Restrições
- JavaScript apenas (Vite + PWA); Supabase; toda mudança de schema via
  migration. Regra de negócio no banco (RPCs/views); cliente só apresenta.
- movimentacoes_estoque, triggers de baixa e as RPCs de compra/ajuste/
  perda da Sessão 4 INTOCADOS. Ronda, turno, Pendências entre turnos e
  Adesão intocados.
- Sem PIN de gestão nesta tela. Sem normalização de texto — agrupamento
  sempre por catalogo_id. Tema Sereníssima nas telas novas.

## Critério de pronto
1. Cadastrar medicamento selecionando item existente do catálogo —
   herança sem digitação; editar depois não muda esses três campos por
   texto livre.
2. Cadastrar medicamento cujo remédio não existe — cria catálogo e
   medicamento juntos.
3. Aba Estoque abre em "Estoque atual"; alternar e voltar não perde nada.
4. Extrato consolidado ordenado pelo pior caso; 2+ residentes com badge e
   detalhe expandível.
5. Clicar num medicamento abre o extrato com cores por direção.
6. Filtro por tipo/subtipo combinado com o calendário.
7. Residente/medicamento inativo com selo, sem alerta.
8. Nenhuma ação de estoque na tela de extrato.
9. npm run build sem erro; nenhuma regressão em Ronda, turno, Pendências,
   Adesão ou nas ações de "Estoque atual".

## Encerramento
- Smoke test de cada migration em transação com rollback antes do apply.
- Bateria SQL (backfill, criação com item novo/existente, bloqueio de
  edição por texto após vínculo, ordenação pelo pior caso do grupo, sinal
  do ajuste_contagem, filtro de subtipo).
- Conferência no navegador (375px). npm run build e revisão dos advisors.
- Reset final do seed. Gerar RELATORIO_SESSAO_06.md. Atualizar CONTEXT.md
  e ROADMAP.md (próxima sessão = 7, deploy/go-live).
