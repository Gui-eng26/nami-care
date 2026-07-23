# Sessão #14 — Ajustes visuais de go-live (BUG-004 a BUG-007, DEC-050)

**Fase 4 — go-live.** App no ar, piloto não iniciado, banco ainda com o cenário
de demonstração da Sessão #9 (`npm run limpar-banco` continua obrigatório antes
de qualquer dado real).

Sessão **inteiramente de CSS e apresentação**. Nenhuma migration, nenhuma RPC,
nenhuma consulta, nenhuma escrita, nenhuma mudança de schema. Nada de dados
muda — o seed **não** precisa ser resetado.

Numeração: última decisão registrada era a **DEC-049**; último bug, o
**BUG-003**. Esta sessão cria a **DEC-050** e os **BUG-004 a BUG-007**.

---

## Parte 1 — Campos de data e atalhos de período (BUG-004, BUG-005)

**BUG-004** — `input[type="date"]` do WebKit tem largura intrínseca própria e
não encolhe abaixo dela mesmo com `width: 100%`. O `min-width: 0` existente vive
só no `<label>`; o input por dentro transborda. Visível na Adesão a 375px;
latente no Extrato de movimentações, nos modais de validade do Estoque e nas
datas do `FormMedicamento`.

**BUG-005** — `.atalhos` é `flex-wrap: wrap` com pills de largura intrínseca. A
375px "Este mês" sobra sozinho na segunda linha, parecendo item solto.

**Achado de passagem:** em `ExtratoMovimentacoes.jsx` o `.formulario-linha` de
De/Até está **fora** de um `.formulario`, então aqueles inputs não recebem
padding nem borda. A tela "não estourava" por acidente, não por desenho.

### Execução

`src/index.css`
1. Endurecimento global de `input[type="date"]`: `appearance: none`,
   `-webkit-appearance: none`, `min-width: 0`, `width: 100%`.
2. Nova `.periodo-datas` — grade de uma coluna: De e Até **empilhados sempre**,
   sem breakpoint. Resolve a classe do bug e não volta a apertar com fonte
   ampliada.
3. Nova `.atalhos-periodo` — grade 2×2. Filhos continuam `.atalho` /
   `.atalho-ativo`.
4. **`.atalhos` e `.subabas` não são tocadas** — a alternância "Contínuo | SOS"
   reaproveita `.atalhos` e precisa ficar como está.

`src/pages/Adesao.jsx` — `"atalhos"` → `"atalhos-periodo"`; o
`div.formulario-linha` de De/Até → `"periodo-datas"`.

`src/pages/ExtratoMovimentacoes.jsx` — `"atalhos"` → `"atalhos-periodo"`; o
`div.formulario-linha` de De/Até → `"periodo-datas"` **envolvido por um
`div.formulario`**, para as duas telas pararem de divergir; o
`"atalhos subabas"` fica como está.

**Mudança visual esperada e desejada:** os campos de data do Extrato passam a
ter a mesma moldura da Adesão. É uniformização, não regressão.

**Fora do escopo:** alterar `.atalhos`/`.subabas`; mexer nos rótulos; mudar a
lógica de período ou qualquer consulta; tocar em outros formulários.

---

## Parte 2 — Bloco de doses SOS no relatório de adesão (BUG-006)

A linha de SOS ganhou clique na Sessão #13 mas continuou parecendo rodapé: vem
depois da prosa do "Pendente (não apurado)", tem o `›` no meio de uma frase e usa
tamanho/cor de texto explicativo. O efeito observado é o registro mais útil da
sessão: **o próprio autor do recurso quase concluiu que ele não havia sido
entregue.**

O SOS não pode virar categoria (não tem denominador, logo não tem percentual nem
barra — DEC-030), mas pode ter o **ritmo** das categorias.

### Execução

`src/pages/Adesao.jsx`, em `ResultadoAdesao` — ordem final do card:
1. contexto;
2. as 5 categorias com barras;
3. legenda do "Pendente (não apurado)", quando houver;
4. **divisor**;
5. **bloco SOS** — estrutura de `.adesao-linha` (rótulo à esquerda, número à
   direita, `.adesao-seta` na mesma coluna das outras cinco), dentro de
   `button.adesao-categoria` quando há residente; sem residente, `<div>`
   estático, sem seta (DEC-048), mas **o divisor e o bloco continuam
   aparecendo**;
6. legenda do SOS — `<p className="adesao-legenda">` **fora** do botão;
7. aviso amarelo de pendentes do turno aberto, que **desce para o fim**: um
   alerta acionável fecha o card.

`src/index.css` — `.adesao-sos-bloco` com o divisor; `.adesao-sos` e
`.adesao-sos-nota` removidas, sem deixar regra órfã.

**As setas das outras cinco categorias NÃO mudam** — o problema é o SOS, não a
afordância geral da tela.

**Fora do escopo:** categoria nova; barra ou percentual no SOS; mudar o cálculo,
a RPC `detalhe_adesao` ou a tela de detalhe; tornar clicável a faixa de
pendentes.

---

## Parte 3 — Concordância de número da forma farmacêutica (BUG-007, DEC-050)

"29 comprimido". As telas concatenam `quantidade + forma_farmaceutica` cru.
`forma_farmaceutica` é **texto livre** — não há lista fechada para consultar, e
a força bruta produziria `soluçãos`, `gels`, `gotass`.

**Princípio (DEC-050): errar para o lado de não flexionar.** Terminação não
coberta com segurança → devolve como foi digitada. "3 gel" é levemente errado;
"3 gels" mina a confiança no app inteiro.

**Regra numérica:** singular quando `0 < n ≤ 1`; plural nos demais casos —
inclusive no zero. A dosagem aceita meio comprimido, então `0,5 comprimido` não
é hipotético.

### Execução

`src/lib/formato.js` — novo `fmtForma(qtd, forma)`, devolvendo **apenas a forma
flexionada**, para cada tela manter controle do espaçamento e da marcação:
- `forma` vazia/nula → base `'unidade'` (flexionável) — **isto elimina o
  `'unidade(s)'` de todas as telas**;
- singular → como está;
- plural, nesta ordem: invariáveis (`ml mg mcg g kg l ui un un.`) → como está;
  exceções (`gel → géis`); mais de uma palavra → como está; `s`/`x` → como está;
  `ão → ões`; `m → ns`; `r`/`z` → `+es`; vogal (com ou sem acento) ou `y` →
  `+s`; **qualquer outra terminação → como está**.

Aplicar nos **nove** pontos que concatenam quantidade + forma: `Estoque.jsx`
(×3), `ExtratoMovimentacoes.jsx`, `Ronda.jsx` (×2), `DoseSos.jsx`,
`PendenciasEntreTurnos.jsx`, `GestaoResidentes.jsx`.

**NÃO tocar** onde a forma aparece **sem quantidade** — ali o singular é o
correto: `FormMedicamento.jsx` ~13, `ExtratoMovimentacoes.jsx` ~228 e ~332,
`GestaoResidentes.jsx` ~296, `Estoque.jsx` ~324.

Ao final, `'unidade(s)'` não deve mais existir no `src/`.

**Fora do escopo:** transformar `forma_farmaceutica` em lista fechada; coluna de
plural no banco; qualquer migration; mexer no cadastro de medicamento.

---

## Parte 4 — Documentação

- `DECISIONS.md` — **DEC-050**, "Flexão de número da forma farmacêutica".
- `ROADMAP.md` / `CONTEXT.md` — BUG-004 a BUG-007 como achados e corrigidos,
  com o efeito observado do BUG-006 registrado.
- `CONTEXT.md` — bloco da Sessão #14, mantendo intactas as pendências reais de
  go-live (`limpar-banco`; passos 4–8 do runbook).

---

## Critério de pronto

1. Adesão: quatro atalhos em 2×2 sem órfão; De/Até empilhados, dentro da borda.
2. Extrato: mesmo grupo 2×2; De/Até empilhados **com a mesma moldura da
   Adesão**; "Contínuo | SOS" inalterada.
3. Modais de validade (compra e ajuste) e datas do `FormMedicamento` dentro do
   modal, sem rolagem horizontal.
4. Bloco SOS lê como linha clicável no ritmo das cinco categorias; seta na mesma
   coluna; explicação fora da área clicável; clique abre o detalhe. Sem
   residente: sem seta, sem clique.
5. Ordem do card conferida, com o aviso de pendentes por último.
6. Estoque mostra "29 comprimidos"; dose de 0,5 mostra "0,5 comprimido"; saldo
   zerado mostra "0 comprimidos". Nenhum "unidade(s)" em tela.
7. Bateria do helper em Node: `comprimido, cápsula, gotas, solução, sachê,
   ampola, gel, ml, spray, comprimido revestido` × `0 / 0,5 / 1 / 2 / 29`.
8. Nenhum arquivo em `supabase/migrations/` criado ou alterado (`git status`).
9. `npm run build` OK. Seed **não** resetado.

**Observação a conferir, sem virar tarefa:** nos prints a barra de status do
iPhone aparece sobre as abas. As `.abas` não são `sticky`, então é provável que
seja artefato da moldura do print sobre uma captura já rolada. Se reproduzir no
aparelho, **não corrigir aqui** — registrar como achado para uma sessão de
`safe-area`.
