# DECISIONS — Nami Care

> Registro de decisões arquiteturais e de produto (ADR simplificado).
> Formato: DEC-XXX | Data | Decisão | Racional | Alternativas descartadas | Status

---

## DEC-001 — Interface: PWA web, não WhatsApp
**Data:** 2026-07-15 | **Status:** aprovada

**Decisão:** O produto será um web app (PWA), não um bot de WhatsApp como a Nami Life.

**Racional:** A premissa da Nami (1 número = 1 usuário) quebra na casa de repouso:
4 cuidadores compartilham a gestão de 11 idosos (N:N), é preciso trilha de auditoria
por turno, e visões consolidadas (rodada do horário, relatórios de estoque) são
inviáveis em conversa de texto. PWA elimina o custo por mensagem da Z-API.

**Alternativas descartadas:** WhatsApp como interface principal; app nativo
(complexidade de publicação desnecessária para piloto).

---

## DEC-002 — Dispositivo: celular compartilhado da casa
**Data:** 2026-07-15 | **Status:** aprovada (confirmado com a realidade da cliente)

**Decisão:** O app será desenhado para um único celular compartilhado, com troca de
operador via "assumir turno" (PIN).

**Racional:** A casa da Thais possui celular próprio. Um dispositivo único simplifica
autenticação (PIN curto em vez de e-mail/senha por pessoa), suporte e treinamento.

**Implicações:** sessão do turno deve expirar/perguntar "quem está no turno?" após
inatividade prolongada; UI mobile-first para uma única tela de celular.

---

## DEC-003 — Rodada de medicação como unidade central (não lembretes individuais)
**Data:** 2026-07-15 | **Status:** aprovada

**Decisão:** Em vez de disparar N lembretes por medicamento (modelo Nami), o sistema
consolida todos os medicamentos devidos num horário em uma única fila operacional
("rodada"), que o cuidador percorre confirmando item a item.

**Racional:** Resolve a colisão de horários entre idosos (problema técnico) e espelha
a rotina real do cuidador, que faz a ronda — não atende 15 alarmes (problema de UX).

---

## DEC-004 — Estoque como livro-razão de movimentações
**Data:** 2026-07-15 | **Status:** aprovada

**Decisão:** O saldo de estoque é derivado da soma de movimentações
(entrada_compra, saida_administracao, ajuste_contagem, perda), nunca um campo
sobrescrito.

**Racional:** Auditoria completa, relatório de divergência físico vs. sistema (a dor
número 1 da cliente), previsão de ruptura e histórico de consumo — padrão consolidado
de gestão de estoque no varejo farmacêutico (know-how RaiaDrogasil).

---

## DEC-005 — Stack: Supabase sem backend próprio
**Data:** 2026-07-15 | **Status:** aprovada

**Decisão:** Supabase (Postgres + Auth + RLS) como backend completo; React PWA como
frontend. Sem servidor Node/cron no MVP.

**Racional:** Reaproveita domínio existente de Supabase (Nami Life). A "agenda" do
sistema é consulta em tempo real, dispensando cron. Custo de infra ~zero no piloto.
Notificações push (que exigiriam mais infra) ficam para v2.

**Alternativas descartadas:** replicar stack completa da Nami (Node + Railway +
node-cron) — complexidade sem benefício para este caso.

---

## DEC-006 — Soft delete para medicamentos e horários
**Data:** 2026-07-15 | **Status:** aprovada

**Decisão:** Remoções são desativações (`ativo = false`); nunca DELETE físico.

**Racional:** Preserva histórico de adesão e trilha de auditoria — requisito
implícito de um sistema que registra atos de cuidado com idosos.

---

## DEC-007 — Hospedagem do frontend: Railway
**Data:** 2026-07-15 | **Status:** aprovada

**Decisão:** Frontend hospedado no Railway.

**Racional:** Consolidação de plataformas — Guilherme já usa Railway na Nami Life
(conta, billing e familiaridade existentes). Adicionar Vercel criaria mais um
cadastro/login/painel para um benefício marginal (free tier), enquanto o custo de
um site estático no Railway é irrisório.

**Alternativas descartadas:** Vercel (free tier, mas plataforma adicional).

---

## DEC-015 — Linguagem única: JavaScript em todo o projeto
**Data:** 2026-07-15 | **Status:** aprovada (revisada no mesmo dia)

**Decisão:** Todo o projeto em JavaScript — app (React/PWA) e scripts auxiliares
(seed, utilidades em Node).

**Racional:** O frontend só pode ser JS (o navegador não executa Python), e manter
uma linguagem única simplifica o repositório e o setup. Guilherme já tem noção de
JS pelo projeto Nami Life, e a base de Python facilita a leitura. Python foi
considerado para scripts auxiliares, mas a consolidação venceu; pode ser adotado
pontualmente no futuro para análises de dados do piloto, se fizer sentido.

---

## DEC-008 — Baixa automática de estoque: trigger no banco
**Data:** 2026-07-16 | **Status:** aprovada (implementada na Sessão #1)

**Decisão:** A baixa automática é um trigger AFTER INSERT em `administracoes`
(`trg_baixa_automatica_estoque`): status `tomado_*` gera movimentação
`saida_administracao`; `recusado` gera `perda`; `nao_tomado` não gera nada.
UNIQUE em `movimentacoes_estoque.administracao_id` impede dupla baixa.
A movimentação herda `registrado_em` da administração como `criado_em` — em
registro tardio (DEC-010), a baixa fica datada no momento real da dose.

**Racional:** consistência independente do cliente (app, seed, SQL direto):
nenhum caminho de escrita esquece a baixa. Testado na Sessão #1: os três
status, a dupla baixa (rejeitada) e o saldo derivado.

**Alternativas descartadas:** lógica na aplicação (mais fácil de depurar, mas
permite administração sem baixa se algum cliente esquecer a regra).

---

## DEC-009 — Dose recusada = perda, com baixa de estoque
**Data:** 2026-07-15 | **Status:** aprovada

**Decisão:** Recusa do idoso sempre baixa estoque, registrada como perda.

**Racional:** Na prática, a dose já saiu do blister/frasco. Regra única simplifica
a UI e mantém o ledger fiel à realidade física. Sem cenário de devolução.

---

## DEC-010 — Janela de 30 min + fechamento de turno obrigatório
**Data:** 2026-07-15 | **Status:** aprovada, com a **tolerância revisada pela
DEC-039** (Sessão #10, 2026-07-21): a janela antes de a dose virar "atrasada"
passou de **30 para 60 min**. Todo o resto desta decisão — inclusive o
fechamento de turno obrigatório, que independe da tolerância — segue valendo
sem alteração.

**Decisão:** Dose pode ser confirmada até 30 min (hoje 60 — DEC-039) após o
horário agendado. Depois
vira "atrasada" e permanece em destaque na tela. O turno só pode ser encerrado
quando todas as doses do período receberem tratativa: tomou no horário (registro
tardio), tomou atrasado, ou não tomou.

**Racional:** Garante 100% de acurácia do ledger de estoque e do relatório de
adesão — nenhuma dose fica sem resposta. Disciplina operacional análoga ao
fechamento de caixa no varejo.

**Implicações de UX:** seção fixa de "doses pendentes de tratativa" na tela
principal; botão "encerrar turno" bloqueado enquanto houver pendências.

---

## DEC-011 — Sem perfil admin no MVP
**Data:** 2026-07-15 | **Status:** parcialmente substituída pela DEC-024
(Sessão #3) e parcialmente restaurada pela DEC-038 (Sessão #8): vale para a
**operação** (ronda, tratativas, estoque) e, de novo, para os cadastros de
**residentes, medicamentos e horários** — agora com a trava do turno aberto,
não mais livre. Só a gestão de **equipe** segue exigindo administradora.

**Decisão:** Todos os cuidadores podem cadastrar e editar idosos, medicamentos e
horários.

**Racional:** Equipe de 4 pessoas com confiança mútua; a trilha de auditoria
(toda ação vinculada ao cuidador do turno) cobre a rastreabilidade. Perfis de
permissão ficam para v2 se o produto escalar para casas maiores.

---

## DEC-012 — Ponto de reposição: cobertura < 5 dias
**Data:** 2026-07-15 | **Status:** aprovada

**Decisão:** O relatório de estoque alerta quando o saldo atual dividido pelo
consumo médio diário indicar cobertura inferior a 5 dias.

**Racional:** Definido pela realidade operacional da cliente (prazo suficiente
para compra na farmácia local). Parametrizável por medicamento em v2 se necessário.

---

## DEC-013 — Doses fracionadas (0,5)
**Data:** 2026-07-15 | **Status:** aprovada

**Decisão:** suportar qtd_dose em frações de 0,5 com baixa exata no ledger;
descarte de metade não utilizada registrado como movimentação manual de perda.

---

## DEC-014 — Dose avulsa (SOS/PRN) no MVP
**Data:** 2026-07-15 | **Status:** aprovada (confirmado: existem medicamentos SOS na casa)

**Decisão:** o MVP inclui registro de "dose avulsa" — medicamento sem horário
fixo, dado conforme necessidade (ex.: analgésico). Fluxo: selecionar idoso +
medicamento + confirmar, com baixa de estoque.

**Racional:** sem isso, doses avulsas não registradas quebram a acurácia do
ledger — a proposta de valor central do produto.

**Implicações no schema:**
- `medicamentos.tipo`: `continuo` (com horários) | `sos` (sem horários)
- `administracoes.medicamento_id` (FK obrigatória) + `administracoes.horario_id`
  passa a ser opcional (NULL = dose avulsa)
- Medicamentos `sos` não entram em rodadas nem no fechamento de turno; aparecem
  apenas no fluxo de dose avulsa e nos relatórios de estoque/consumo

---

## DEC-016 — Ledger com quantidade sinalizada (entradas > 0, saídas < 0)
**Data:** 2026-07-16 | **Status:** aprovada (tomada na Sessão #1)

**Decisão:** `movimentacoes_estoque.quantidade` carrega o sinal: entradas
positivas, saídas/perdas negativas, ajuste de contagem qualquer valor ≠ 0.
Saldo = `SUM(quantidade)` puro, sem CASE por tipo. Constraint no banco
(`movimentacoes_sinal_por_tipo`) garante o sinal correto para cada tipo.

**Racional:** simplifica todas as consultas de saldo/cobertura e elimina a
classe de bug "esqueceu de negar a saída". O tipo continua registrando a
natureza da movimentação para auditoria e relatórios.

**Alternativas descartadas:** quantidade sempre positiva com sinal derivado do
tipo em cada consulta (repetição de lógica e risco de divergência).

---

## DEC-017 — Registros de auditoria imutáveis (administracoes e ledger)
**Data:** 2026-07-16 | **Status:** aprovada (tomada na Sessão #1)

**Decisão:** `administracoes` e `movimentacoes_estoque` não recebem UPDATE nem
DELETE pelo app: as políticas de RLS dão apenas SELECT + INSERT ao papel
autenticado, e um trigger (`trg_administracao_imutavel`) bloqueia alteração dos
campos com efeito no ledger mesmo por outros caminhos. Erro de registro se
corrige com novo registro + movimentação manual de ajuste/perda. Nas tabelas de
cadastro não há política de DELETE — remoção é soft delete (DEC-006).

**Racional:** a trilha de auditoria é requisito do produto (atos de cuidado com
idosos); ledger editável destruiria a confiança no relatório de divergência,
que é a dor nº 1 da cliente.

---

## DEC-018 — Hash de PIN provisório no seed: SHA-256
**Data:** 2026-07-16 | **Status:** SUBSTITUÍDA pela DEC-020 (Sessão #2, 2026-07-16)

**Decisão:** o seed grava `cuidadores.pin_hash` como SHA-256 hex do PIN, sem
salt. É um formato de dados de teste; o mecanismo definitivo de autenticação
por PIN (algoritmo de hash, salt, verificação no cliente vs. RPC) é escopo da
Sessão #2 e deve substituir/ratificar este formato.

**Racional:** destrava o seed sem antecipar o design de autenticação. PIN de 4
dígitos é força-bruta trivial em qualquer hash rápido — a segurança real virá
do desenho da Sessão #2 (ex.: rate limit, verificação server-side), não do
algoritmo usado no seed.

## DEC-019 — Autenticação: usuário único Supabase + PIN por cuidador

**Data:** 2026-07-16 | **Status:** decidida

**Decisão:** A casa de repouso opera com um único usuário Supabase autenticado
no dispositivo compartilhado, satisfazendo as políticas de RLS. A identificação
individual dos cuidadores é feita na camada de aplicação via PIN, que determina
quem detém o turno ativo.

**Contexto:** A casa usa um celular compartilhado entre 4 cuidadores.
Login/logout individual no Supabase adicionaria fricção operacional sem ganho
de segurança proporcional ao contexto.

**Alternativas consideradas:**
- Um usuário Supabase por cuidador — descartado pela fricção de troca de
  sessão no dispositivo compartilhado.

**Implicações:**
- Toda ação registrada (dose, tratamento, fechamento de turno) grava o
  cuidador identificado pelo PIN do turno ativo, não o usuário Supabase.
- O fechamento obrigatório de turno passa a ser o mecanismo que troca o
  detentor do PIN ativo.
- O mecanismo definitivo de PIN (hash com salt, rate limit, verificação
  server-side via RPC) é escopo da Sessão #2 e substitui/ratifica o formato
  provisório do seed registrado na **DEC-018**.

---

## DEC-020 — PIN definitivo: bcrypt no banco, verificação exclusivamente server-side
**Data:** 2026-07-16 | **Status:** aprovada (implementada na Sessão #2; substitui a DEC-018)

**Decisão:** `cuidadores.pin_hash` guarda bcrypt (pgcrypto: `crypt` +
`gen_salt('bf', 10)`), com salt por cuidador embutido no próprio hash. O hash
é gerado apenas no banco (`fn_hash_pin`, exposta só ao `service_role`; troca
de PIN pelo app via RPC `definir_pin`) e verificado apenas no banco (RPC
`abrir_turno`, SECURITY DEFINER). Os papéis de API perdem o acesso à coluna:
grants por coluna deixam `authenticated` ler somente `id, nome, ativo,
criado_em` e alterar somente `nome, ativo`. PIN aceito: 4 a 6 dígitos.

**Racional:** PIN de 4 dígitos é força-bruta trivial offline — a defesa real
é o hash nunca sair do banco (nem para comparação) combinado com o rate limit
da DEC-021. bcrypt custa ~0,1 s por verificação, irrelevante no login e caro
o suficiente para varredura.

**Alternativas descartadas:** hash no cliente (expõe o hash e permite replay);
SHA-256 com salt (rápido demais para PIN curto); Argon2 (não disponível no
pgcrypto do Supabase sem extensão adicional).

---

## DEC-021 — Rate limit de PIN: 5 falhas / 15 minutos por cuidador
**Data:** 2026-07-16 | **Status:** aprovada (tomada na Sessão #2)

**Decisão:** toda tentativa (sucesso ou falha) é registrada em
`tentativas_pin` — tabela sem nenhum acesso dos papéis de API (RLS habilitado
sem políticas + grants revogados). Quando as 5 falhas mais recentes do
cuidador cabem numa janela móvel de 15 minutos, `abrir_turno` recusa novas
tentativas e informa o horário de desbloqueio (a falha mais antiga das 5 + 15
min). A resposta de falha informa quantas tentativas restam.

**Racional:** no pior caso o atacante testa 480 PINs/dia por cuidador (~21
dias para varrer 10.000 combinações), em um dispositivo que fica dentro da
casa — risco aceitável para o piloto. A tabela serve também de trilha de
auditoria de acesso.

---

## DEC-022 — Turno único aberto; abertura e fechamento apenas por RPC
**Data:** 2026-07-16 | **Status:** aprovada (tomada na Sessão #2)

**Decisão:** índice único parcial garante no máximo UM turno aberto (`fim IS
NULL`) — coerente com o dispositivo único da casa (DEC-002). O cliente perde
INSERT/UPDATE em `turnos`: abrir passa obrigatoriamente por `abrir_turno`
(PIN + rate limit; reabrir com o mesmo cuidador retoma o turno existente) e
fechar por `fechar_turno`, que recusa o fechamento enquanto existir dose
devida sem tratativa (DEC-010) — inclusive dose ainda dentro da janela de
tolerância de 30 min. Um trigger em `administracoes` exige turno aberto do
cuidador informado: nenhuma ação é gravada em nome de quem não detém o turno
(DEC-019). A constraint `turnos_fim_apos_inicio` passou a aceitar `fim =
inicio` (turno aberto e fechado no mesmo instante — `now()` é fixo por
transação).

**Racional:** se o fechamento obrigatório pudesse ser contornado com um
UPDATE direto, a garantia de acurácia do ledger (proposta de valor central)
seria decorativa. As RPCs são o único caminho de escrita.

---

## DEC-023 — Dose de ronda ancorada em `prevista_em`; fuso fixo da casa
**Data:** 2026-07-16 | **Status:** aprovada (tomada na Sessão #2)

**Decisão:** `administracoes.prevista_em` (timestamptz) registra o instante
agendado do slot tratado (dia + `horarios.hora` no fuso da casa). UNIQUE
`(horario_id, prevista_em)` impede dupla tratativa do mesmo slot; NULL em
ambos identifica dose avulsa (DEC-014); o campo é imutável como os demais da
auditoria (DEC-017). A agenda do turno tem fonte única no banco — RPC
`doses_do_turno` (slots devidos × tratativas, com situação
tratada/pendente/atrasada calculada com a tolerância de 30 min) — usada pela
tela da ronda e pelo `fechar_turno`. O fuso é fixo em `America/Sao_Paulo`
(`fn_fuso_casa`), suficiente para o piloto de casa única.

**Racional:** casar administração com slot por data de registro quebraria em
registro tardio e turno cruzando meia-noite; a âncora explícita torna
"dose sem tratativa" uma consulta exata e dá a unicidade que falta contra
duplo registro. Em registro tardio de dose tomada no horário, o app envia
`registrado_em = prevista_em`, mantendo a baixa datada no momento real
(DEC-008).

---

## DEC-024 — Acesso à gestão: administradora com PIN verificado a cada RPC
**Data:** 2026-07-16 | **Status:** substituída parcialmente pela DEC-038 —
continua valendo INTEGRALMENTE para a gestão de **equipe**; para residentes,
medicamentos e prescrições a autorização passou a ser o turno aberto
(Sessão #8). Antes disso: aprovada na Sessão #3, substituindo parcialmente a
DEC-011.

**Decisão:** `cuidadores.eh_admin` marca quem é administradora. A área de
gestão (cadastro/edição de cuidadoras, residentes, medicamentos e
prescrições) só funciona com credencial de administradora: **cada RPC de
gestão recebe `p_admin_id + p_admin_pin`** e valida no banco
(`fn_autorizar_admin`: bcrypt da DEC-020 + rate limit da DEC-021 + trilha em
`tentativas_pin`). Não há sessão de gestão no servidor — o app pede o PIN ao
entrar na área de gestão, guarda-o apenas em memória e o reenvia a cada
chamada. A **operação** do turno (assumir turno, tratativas da ronda, futuras
dose SOS e movimentações de estoque) continua aberta a toda cuidadora — a
DEC-011 permanece válida para operação e deixa de valer para cadastros.

**Racional / prós:** enforcement real no servidor (esconder botão no cliente
seria furável pelo console do navegador); toda ação de gestão fica auditada
em `tentativas_pin`; reusa o PIN existente (nenhuma credencial nova);
múltiplas administradoras possíveis (flag por cadastro). Mexer em prescrição
é ato clínico-administrativo — o erro mais grave possível do sistema — e a
cliente (Thais) é a gestora natural desses cadastros.

**Contras aceitos:** digitar o PIN ao entrar na gestão (1× por sessão de
tela); um cadastro urgente fora do expediente da administradora depende de
outra admin ou espera (mitigável criando uma segunda admin).

**Alternativas descartadas:** gate apenas no cliente (sem segurança real);
token de sessão de gestão no servidor (complexidade sem ganho no dispositivo
único); manter DEC-011 também para cadastros (proposta original — descartada
pelo peso clínico de prescrição e pelo risco de troca/desativação de
cuidadora por qualquer pessoa com o celular na mão).

**Bootstrap:** o seed marca Ana Souza como administradora; a criação da
administradora real (Thais) entra no cadastro de dados reais da Sessão #5.

---

## DEC-025 — Troca de PIN: com PIN atual (self-service) ou por administradora
**Data:** 2026-07-16 | **Status:** aprovada (Sessão #3)

**Decisão:** dois caminhos, ambos server-side: **`trocar_pin(cuidador, pin_atual,
pin_novo)`** — a própria cuidadora, validando o PIN atual (com o rate limit da
DEC-021, para não virar oráculo de força bruta); e **`redefinir_pin(admin,
pin_admin, cuidador, pin_novo)`** — reset por administradora para caso de
esquecimento (DEC-024). A RPC `definir_pin` da Sessão #2, que trocava PIN
**sem verificação nenhuma**, foi removida (qualquer authenticated podia trocar
o PIN de qualquer cuidadora — registrado como BUG-001).

**Racional:** troca de PIN sem prova de posse permitiria a qualquer pessoa com
o celular assumir a identidade de outra cuidadora — quebraria a trilha de
auditoria, que é a razão de existir do PIN (DEC-019).

---

## DEC-026 — Prescrição versionada: campos clínicos imutáveis após uso
**Data:** 2026-07-16 | **Status:** aprovada (Sessão #3)

**Decisão:** depois que um medicamento/horário tem administração registrada,
os campos que dão significado clínico ao histórico ficam **imutáveis**:
em `medicamentos`, `nome`, `dosagem` e `forma_farmaceutica`; em `horarios`,
`hora` e `qtd_dose`. Alterar prescrição = **desativar a linha antiga e criar
uma nova** (versão): a RPC `atualizar_horario` faz isso automaticamente quando
há histórico (e edita in-place quando ainda não há — janela para corrigir erro
de digitação); mudança de dose/dosagem de medicamento vira novo medicamento
pela UI. Triggers no banco (`fn_medicamento_imutavel_apos_uso`,
`fn_horario_imutavel_apos_uso`) garantem a regra por qualquer caminho de
escrita, não só pelas RPCs. `posologia` (texto de orientação) permanece sempre
editável. Índice único parcial `(medicamento_id, hora) where ativo` impede
horários duplicados ativos.

**Racional:** `administracoes` copia `qtd` e ancora `prevista_em`, mas nome e
dosagem do medicamento são lidos por join — reescrevê-los reescreveria a
leitura de todo o histórico de administrações (violaria DEC-017). A linha
antiga desativada preserva a leitura fiel; a nova linha passa a gerar os slots
da ronda dali em diante.

**Alternativas descartadas:** tabela de versões de prescrição separada
(complexidade de schema sem ganho — a linha desativada JÁ é a versão);
copiar nome/dosagem para dentro de `administracoes` (desnormalização que
incharia a tabela de maior volume do sistema).
---

## DEC-027 — Alerta de reposição: dois métodos por natureza do medicamento
**Data:** 2026-07-17 | **Status:** aprovada (implementada na Sessão #4)

**Decisão:** O gatilho de reposição usa métodos distintos conforme o tipo:
- **Contínuo/planejado:** cobertura determinística pela prescrição —
  `cobertura_dias = saldo_atual ÷ doses_planejadas_por_dia`. Alerta quando a
  cobertura projetada cai abaixo de 5 dias (DEC-012).
- **SOS/PRN:** estoque mínimo de segurança por medicamento
  (`medicamentos.estoque_minimo`, numeric com fração 0,5, definido pelo
  cuidador no cadastro) — alerta quando `saldo_atual < estoque_minimo`.
  Sem mínimo definido, o alerta fica desligado (a tela avisa).

**Racional:** O consumo de um contínuo já está escrito na prescrição;
derivá-lo de uma média móvel de histórico seria estimar o que já é conhecido,
e introduz defasagem (a média demora a "perceber" uma troca de dose) e o
risco de divisão por zero em itens sem consumo recente. A cobertura pela
prescrição absorve mudanças de posologia na hora e não divide por zero,
porque o denominador vem de um medicamento que tem horários cadastrados. Já o
SOS não tem consumo planejável por natureza; projetar cobertura em dias
inventaria previsibilidade inexistente. O mínimo de segurança é uma regra
binária simples, e deixá-lo por medicamento (não global) respeita forma
farmacêutica e frequência de uso — o cuidador, que opera, calibra melhor que
um palpite de projeto.

**Confirmado na implementação:** a modelagem da Sessão #3 só suporta
posologia diária (`horarios.hora` é `time` — um disparo por dia por linha),
então `doses_planejadas_por_dia = SUM(qtd_dose)` dos horários ativos, sem
normalização semanal. Se um dia a posologia ganhar padrões não diários
(dias alternados, X vezes por semana), o denominador precisará normalizar
para base diária. Contínuo ativo sem horário ativo fica com cobertura NULL
(fora das rondas) e sem alerta. O cálculo vive na view `cobertura_estoque`
(redefinida; a versão de média móvel de 14 dias da Sessão #1 foi descartada).

**Alternativa descartada:** média móvel única (ex.: 14 dias) para todos os
medicamentos. Rejeitada por fragilidade (escolha arbitrária de janela,
tratamento de divisão por zero, defasagem frente a mudanças de prescrição) e
por baixa legibilidade para a cuidadora.

---

## DEC-028 — Sugestão de compra: repor para 30 dias de cobertura
**Data:** 2026-07-17 | **Status:** aprovada (tomada na Sessão #4)

**Decisão:** para contínuos em alerta, a visão de estoque sugere a quantidade
que devolve ~30 dias de cobertura: `sugestao_compra =
ceil(doses_por_dia × 30 − saldo)`. Sem sugestão para SOS (sem consumo
planejável, a quantidade é decisão de quem opera).

**Racional:** 30 dias casa com a caixa típica de 30 unidades da farmácia
brasileira e com ciclo mensal de compra — um patamar que evita tanto compra
semanal (fricção) quanto estoque parado. O rótulo na tela é operacional
("comprar 26"), não estatístico.

---

## DEC-029 — Tela de estoque: organizada por residente, alertas no topo
**Data:** 2026-07-17 | **Status:** aprovada (tomada na Sessão #4)

**Decisão:** a lista de estoque agrupa por residente (não consolida por
medicamento), com uma seção "Repor" fixa no topo reunindo todos os itens em
alerta (contínuos abaixo de 5 dias e SOS abaixo do mínimo). Estoque de
medicamento ou residente desativado permanece visível com selo "Inativo",
mas **não** dispara alerta de reposição.

**Racional:** o agrupamento espelha a realidade física — cada residente tem
a própria caixa de medicamentos, e o mesmo remédio de dois residentes são
dois estoques separados no armário (consolidar esconderia qual caixa está
acabando). A seção "Repor" é a lista de compras em uma olhada — o destino
da contagem semanal que o sistema substitui. Item desativado não pede compra,
mas o físico continua existindo e auditável (resolve a pendência #6 do
relatório da Sessão #3).

**Alternativa descartada:** visão consolidada por nome de medicamento —
útil para negociar compra em volume, mas ilegível para a operação diária;
pode virar relatório em versão futura.

---

## DEC-030 — Relatório de adesão: denominador = doses materializadas; classificação pelo status
**Data:** 2026-07-18 | **Status:** aprovada (decidida com o Guilherme antes da
sessão; implementada na Sessão #5)

**Decisão:** o relatório de adesão (RPC `relatorio_adesao`) NÃO reconstrói a
grade histórica de horários. O denominador são as doses já **materializadas**:
linhas de `administracoes` de ronda (`horario_id` não nulo) com `prevista_em`
dentro do período, no fuso da casa (`fn_fuso_casa`, DEC-023). Quatro categorias
mutuamente exclusivas, classificadas exclusivamente pelo **status gravado** —
`tomado_no_horario` (no horário), `tomado_atrasado` (atrasada), `recusado`
(recusada — decisão do residente) e `nao_tomado` (não tomada — falha
operacional). "Recusada" e "não tomada" nunca se somam: juntá-las esconderia o
sinal mais grave dos dois. Percentuais calculados na RPC, nunca no cliente.
SOS (`horario_id IS NULL`, instante em `registrado_em`) fica **fora** dos
percentuais: contagem absoluta, sem denominador natural — não se inventa taxa.
No dia corrente, dose futura fica fora do denominador; dose vencida sem
tratativa entra como **pendente**, categoria à parte, obtida de
`doses_do_turno` do turno aberto (fonte única da lógica de slots — nenhuma
segunda implementação); só vira "não tomada" quando registrada como tal.

**Racional:** (1) comparar `registrado_em` com `prevista_em` NÃO classifica:
o registro tardio de dose tomada no horário grava `registrado_em =
prevista_em` (DEC-023) — a classificação tem que sair do status. (2) O
fechamento obrigatório de turno (DEC-010/022) garante que cada dia já fechado
carrega, em linhas próprias, exatamente as doses devidas daquele dia — o
denominador materializado é completo por construção, e a prescrição
versionada (DEC-026) é absorvida naturalmente (a mudança de posologia no meio
do período soma certo sem lógica extra).

**Dependência explícita:** a completude do denominador se apoia no fechamento
obrigatório de turno. Se essa garantia mudar (turno puder fechar com dose sem
tratativa, ou operação com lacunas de cobertura entre turnos), doses nunca
materializadas sumiriam do denominador silenciosamente e o relatório
superestimaria a adesão. **Limite conhecido hoje:** um slot que vence num
intervalo em que nenhum turno está aberto não entra em turno nenhum — não é
materializado, não aparece como pendente (nem na ronda, comportamento herdado
da Sessão #2). No piloto a cobertura de turnos é contínua; risco registrado
para o go-live. **[Atualização 2026-07-20: o limite virou o BUG-002 e foi
corrigido na Sessão #5.5 — DEC-033/034: fila "Pendências entre turnos" com
teto de 5 dias, e `fechar_turno` passou a exigir as duas filas. Este
racional permanece válido para a `relatorio_adesao` em si.]**

**Alternativas descartadas:** reconstruir a grade histórica a partir de
`horarios` (quebraria com o versionamento da DEC-026, exigiria "grade vigente
em cada dia passado" e duplicaria a lógica de slots — o custo da duplicação já
está registrado na MH-001).

---

## DEC-031 — Relatório de adesão: aba de operação, sem PIN de gestão
**Data:** 2026-07-18 | **Status:** aprovada (tomada na Sessão #5)

**Decisão:** o relatório fica numa aba própria ("Adesão") ao lado de
Ronda | Estoque, disponível a qualquer cuidadora com turno aberto, sem o PIN
de administradora da DEC-024. A RPC é SECURITY INVOKER com EXECUTE para
`authenticated` (anon negado) — mesma superfície de leitura que a cuidadora já
tem sobre `administracoes`.

**Consequência explícita (escolha, não detalhe):** os indicadores de adesão
da casa ficam visíveis para toda a equipe, não só para a administração. Numa
equipe de 4 pessoas isso é transparência operacional desejada — quem executa a
ronda enxerga o resultado do próprio trabalho.

**Alternativa descartada:** exigir autorização de gestão (DEC-024) — o
relatório não altera nada e não é ato clínico-administrativo; o atrito do PIN
só reduziria o uso.

---

## DEC-032 — Residente desativado no relatório de adesão
**Data:** 2026-07-18 | **Status:** aprovada (tomada na Sessão #5)

**Decisão:** o histórico do período em que o residente esteve ativo continua
contando — o fato aconteceu — e ele segue incluído na visão macro do período.
Na lista de seleção da visão micro, aparece com o selo "— inativo", e a micro
dele funciona normalmente. Mesmo tratamento que a DEC-029 deu ao estoque de
item desativado (visível, sem alerta).

**Racional de consistência:** desativar um residente muda o futuro (sai da
ronda e das agregações novas via `doses_do_turno`), nunca o passado — apagar
o histórico da macro faria os totais de períodos fechados mudarem
retroativamente, violando o princípio de auditoria (DEC-017).

---

## DEC-033 — Pendências entre turnos: fila própria com teto de 5 dias
**Data:** 2026-07-20 | **Status:** aprovada (Sessão #5.5; corrige o BUG-002)

**Contexto (BUG-002):** `doses_do_turno` delimita a busca por
`[turno.inicio, agora]`. Uma dose que vence num período em que NENHUM turno
está aberto (madrugada sem plantão registrado no app, cuidadora esqueceu de
abrir) não entra na consulta de turno algum: não aparece como pendente nem
atrasada — invisível por construção — e some do denominador do relatório de
adesão. O limite já estava documentado na DEC-030; virou correção porque uma
dose real pode ter sido dada ou não sem que ninguém seja avisado de revisar.

**Decisão:** essas doses NÃO entram na ronda — `doses_do_turno` permanece
intocada, bounded por `turno.inicio` (misturar juntaria "meu trabalho deste
turno" com "problema de um turno que não existiu"). Elas vão para uma fila
própria, a tela **"Pendências entre turnos"**, alimentada pela consulta
independente `fn_pendencias_entre_turnos` / RPC `listar_pendencias_entre_turnos`:
dose vencida (`prevista_em <= agora`) de medicamento contínuo com
horário/medicamento/residente ativos, sem `administracao`, cujo instante não
foi coberto por nenhum intervalo `[inicio, fim ou agora]` de turno. Limites:
a partir do primeiro turno da casa (antes disso o app não operava) e a partir
do `criado_em` do horário (linha versionada pela DEC-026 não gera pendência
retroativa). SOS fica fora: sem grade planejada, não há pendência (DEC-014).

**Teto de 5 dias:** a fila só materializa pendências dos últimos 5 dias
(janela móvel de 120 h). Dos dias mais antigos o app apenas CONTA quantos
dias têm pendência não coberta, para um aviso permanente de dado perdido.
**Racional:** evitar reconstruir um histórico ilimitado (custo e ilegibilidade
crescentes de uma lista de centenas de doses antigas que ninguém consegue mais
apurar com honestidade). **Consequência assumida:** dado com mais de 5 dias
não é mais tratável pelo app — nem individualmente, nem em lote; fica fora do
relatório de adesão para sempre, e eventual divergência de estoque desses dias
se resolve só por ajuste manual de contagem.

**UX:** aba junto de Ronda | Estoque | Adesão, visível com turno aberto; a aba
INTEIRA fica vermelha (cor de alerta, não só um selo) com a contagem de doses
entre parênteses enquanto houver pendência, e neutra sem contagem quando não
há — decisão nova desta sessão, não desenhada antes. Lista agrupada por dia
(mais antigo primeiro) e, dentro do dia, por residente. Tratativa individual
reutiliza o MESMO modal da ronda (mesmas quatro opções, mesmo insert).
`fechar_turno` passa a exigir as DUAS filas resolvidas (dentro do teto), com
mensagem distinguindo a origem do bloqueio.

---

## DEC-034 — Resolução em lote com status `pendente` (PIN + alerta de criticidade)
**Data:** 2026-07-20 | **Status:** aprovada (Sessão #5.5)

**Decisão:** a tela de pendências tem um botão único — "Resolver pendências
em lote" — que encerra de uma vez tudo o que ainda está sem tratativa na
lista (dentro do teto da DEC-033), gravando administrações com o novo status
**`pendente`**.

**Semântica do status (não confundir nunca):** `nao_tomado` é a CONFIRMAÇÃO
de que a dose não foi dada; `pendente` é "não sabemos o que aconteceu, e
decidimos conscientemente não apurar". Por isso: (1) no relatório de adesão é
categoria própria — "Pendente (não apurado)" — que entra no denominador mas
nunca se soma a "não tomada" (mentiria confirmando a falta) nem às tomadas
(mentiria confirmando a ocorrência); (2) não gera NENHUMA movimentação de
estoque (mesmo comportamento de `nao_tomado` no trigger de baixa) — a
reconciliação é manual, via `registrar_ajuste_estoque` (Sessão #4), exatamente
como o alerta avisa; (3) o status só nasce da RPC de lote
(`resolver_pendencias_em_lote`) — um trigger de guarda bloqueia INSERT direto
com `pendente`, e o modal individual NÃO oferece a opção: quem trata dose a
dose está confirmando o que aconteceu.

**Autorização:** antes de gravar, um alerta de criticidade cheio de tela
(difícil de ignorar, não um toast) explicita os dois impactos — no espírito
de: "Você está prestes a encerrar N dose(s) sem tratativa individual. Isso
vai impactar diretamente a taxa de adesão dos residentes no relatório e pode
gerar divergência na contagem de estoque — ajustes de estoque relacionados a
essas doses precisarão ser feitos manualmente depois, pela tela de Estoque."
A confirmação exige o **PIN do próprio cuidador do turno aberto**, verificado
no banco (`fn_verificar_pin`, com o rate limit da DEC-021) — reafirmação de
identidade para autorizar uma ação de impacto, mesmo padrão de reverificação
do `trocar_pin` (DEC-025), não troca de credencial. O lote cobre apenas o que
restar sem tratativa no momento do clique: o que já foi tratado
individualmente fica de fora (UNIQUE de slot + NOT EXISTS da fila).

**Alternativas descartadas:** reusar `nao_tomado` no lote (destruiria a
distinção falta confirmada × não apurado); quinta opção "pendente" no modal
individual (a tratativa individual é justamente o caminho de apuração);
lote sem PIN (ação de maior impacto agregado do sistema ficaria a um toque).

---

## DEC-035 — Catálogo de medicamentos da casa: elo por seleção humana, nunca por texto
**Data:** 2026-07-20 | **Status:** aprovada (implementada na Sessão #6)

**Contexto:** `medicamentos.idoso_id` é obrigatório — cada residente tem o
próprio registro de medicamento, mesmo quando o remédio físico é o mesmo de
outro residente (ex.: dois tomando Losartana 50 mg). Não existe elo entre os
dois registros. Para a tela nova (DEC-036) agrupar "mesmo remédio, N
residentes", comparar por texto (nome + dosagem + forma) foi descartado
deliberadamente: divergência de digitação cria falso negativo, e qualquer
normalização que tente compensar arrisca falso positivo (juntar remédios
diferentes). O estoque em si (saldo, ledger) permanece SEMPRE separado por
residente — custo e consumo são cobrados individualmente; isso não muda.

**Decisão:** nova entidade `catalogo_medicamentos` (nome, dosagem,
forma_farmaceutica, criado_em) — da CASA, sem `idoso_id`. `medicamentos.catalogo_id`
(FK NOT NULL) dá o elo de identidade. O catálogo é construído ORGANICAMENTE, sem
fonte externa (bulário/CMED): o primeiro cadastro de um remédio cria o item; os
seguintes reaproveitam por SELEÇÃO HUMANA (busca por nome no cadastro), nunca por
comparação de string. Sem restrição de unicidade no catálogo — travar por texto
seria a própria normalização descartada, e uma quase-duplicata criada por engano
é escolha humana, não erro de integridade (a busca torna isso raro).

**medicamentos mantém a cópia de nome/dosagem/forma:** o histórico
(`administracoes`) as lê por join, e a imutabilidade clínica (DEC-026) depende
dessa cópia estável. Ao criar/vincular, a cópia vem do catálogo; a DEC-026 é
estendida — `catalogo_id` também fica imutável após a primeira administração
(trocar o item mudaria nome/dosagem/forma de quem tem histórico, reescrevendo a
leitura do passado). Garantido por trigger, por qualquer caminho de escrita.

**Cadastro (DEC-024 continua regendo a autorização):** `criar_medicamento` e
`atualizar_medicamento` passam a operar pelo catálogo — ou selecionam um item
existente (herança de nome/dosagem/forma, sem digitar de novo), ou criam um item
novo do catálogo JUNTO com o medicamento (atômico, na mesma RPC). Na tela do
residente, nome/dosagem/forma deixam de ser texto livre editável — trocar o
remédio exige a mesma busca/seleção. posologia/tipo/estoque_minimo continuam por
residente e sempre editáveis; a prescrição versionada (DEC-026) segue regendo
mudança de posologia. Duplicata passa a ser por `catalogo_id` (mesmo remédio para
o mesmo residente), não mais por texto.

**Backfill:** um item de catálogo por combinação exata (nome, dosagem, forma)
presente no seed — seguro porque só há dado de seed até aqui (dados reais entram
na Sessão #7, já com o catálogo pronto). Gerou **23 itens** para 24 medicamentos
(só Losartana 50 mg comprimido é compartilhada — Alzira e Lourdes).

**Alternativas descartadas:** comparação/normalização de texto para agrupar
(frágil nos dois sentidos — o motivo de existir do catálogo); importar bulário
externo (peso sem valor para o piloto; o vocabulário real da casa é pequeno e
emerge do uso); duas RPCs sequenciais para "criar item + medicamento" (não
atômico, deixaria item de catálogo órfão se a segunda falhasse); unicidade de
texto no catálogo (reintroduziria a comparação de string descartada).

---

## DEC-036 — Extrato de movimentação: leitura consolidada por catálogo, dentro da aba Estoque
**Data:** 2026-07-20 | **Status:** aprovada (implementada na Sessão #6)

**Decisão:** o acompanhamento de movimentação de estoque é uma tela SOMENTE
LEITURA dentro da aba Estoque existente (não aba nova), alternada por um seletor
no topo (segmented control) entre **"Estoque atual"** (a visão da Sessão #4, por
residente, com as ações de compra/ajuste/perda — inalterada, e padrão ao abrir) e
**"Extrato de movimentações"**. Os rótulos comunicam diferença de FUNÇÃO (não
"por residente"/"por medicamento", que sugeriria a mesma ação agrupada diferente):
nenhuma ação de estoque vive no extrato.

**Visão consolidada (por catálogo, DEC-035):** duas sub-abas Contínuo | SOS;
calendário de período no padrão da aba Adesão. Uma linha por item de catálogo,
agregando os N residentes que o compartilham, ordenada do PIOR caso pro melhor —
contínuo por `cobertura_dias` (view `cobertura_estoque`), SOS pela distância
`saldo − estoque_minimo`. Com 2+ residentes, o PIOR valor do grupo decide a
posição (badge "N residentes"; clicar expande o detalhe por residente com o valor
individual). Item de residente/medicamento inativo aparece com selo, sem alerta e
fora do cálculo de urgência (ordena por último — DEC-029/032). Clicar num item
(ou num residente do detalhe) abre o extrato daquele `medicamento_id` no período.

**Extrato por medicamento:** as `movimentacoes_estoque` do medicamento no período
(fuso da casa), mais recente primeiro. **Cor por DIREÇÃO (sinal da quantidade),
não por tipo:** verde para entrada (quantidade > 0), vermelho para saída (< 0).
Crucial: `ajuste_contagem` é entrada OU saída conforme o sinal daquela linha — o
subtipo (`ajuste_mais`/`ajuste_menos`) e a cor vêm do sinal, nunca só do campo
tipo. Rótulos legíveis (Compra, Dose administrada, Ajuste de contagem a mais/a
menos, Perda). Filtro por subtipo, combinável com o período. Sem PIN de gestão
(aberta a toda cuidadora, como a Adesão — DEC-031).

**Fonte de dados:** `cobertura_estoque`/`saldo_estoque` (Sessões #1/#4)
reaproveitadas — saldo/cobertura nunca recalculados na tela. Duas RPCs novas,
SECURITY INVOKER: `extrato_consolidado_estoque(p_tipo)` (agrega o pior caso do
grupo no banco) e `extrato_medicamento(p_medicamento_id, p_inicio, p_fim,
p_subtipos)` (extrato filtrado; deriva o subtipo pelo sinal no banco). As RPCs de
compra/ajuste/perda, o trigger de baixa e `movimentacoes_estoque` ficam
INTOCADOS — esta tela só lê e organiza.

**Alternativas descartadas:** aba nova separada (esconderia que é a mesma aba
Estoque, com outra função); consolidar por nome de medicamento via texto
(descartado pela DEC-035 — o agrupamento é por `catalogo_id`); recalcular
cobertura/saldo no cliente (duplicaria regra de negócio que já vive na view);
cor por tipo em vez de sinal (classificaria errado o `ajuste_contagem`, que é
bidirecional).

---

## DEC-037 — Produção: build estático do Vite servido por processo Node no Railway
**Data:** 2026-07-21 | **Status:** aprovada (preparada na Sessão #7)

**Decisão:** em produção o Railway roda **dois comandos distintos** — build
(`npm run build`, que gera `dist/`) e serve (`npm run start`, que serve `dist/`
com o pacote `serve` em modo SPA, na porta de `$PORT`). O dev server do Vite
NUNCA roda em produção. A configuração fica versionada em `railway.json`
(builder NIXPACKS, `buildCommand`, `startCommand`, restart em falha) e a versão
do Node em `.node-version`, para que o deploy seja reprodutível a partir do
repositório e não de cliques no painel.

**Fronteira de segredos:** o serviço de frontend recebe **apenas**
`VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY` — tudo que tem prefixo `VITE_` é
embutido no bundle e é público por construção. `SUPABASE_SERVICE_ROLE_KEY` e as
credenciais `CASA_*` são de script local (seed, bootstrap) e nunca entram em
variável do serviço público.

**Racional:** o app é 100% estático depois do build (a regra de negócio vive no
Supabase — não há backend próprio, DEC-007/BRIEFING §4). `serve -s` dá o
fallback de SPA e é JavaScript, coerente com a linguagem única (DEC-015), sem
introduzir Caddy/nginx nem uma segunda plataforma. Deixar build e serve
separados evita o erro clássico de subir o dev server do Vite em produção
(lento, sem cache, sem os arquivos do PWA gerados).

**Sobre o Supabase Auth:** verificado nesta sessão que o app usa apenas
`signInWithPassword` — sem magic link, OAuth ou recuperação de senha. O endpoint
de Auth responde a qualquer origem (`access-control-allow-origin` ecoa a origem
enviada), então **Site URL e Redirect URLs não bloqueiam o login** a partir da
URL do Railway. Cadastrar a URL de produção no Auth continua recomendado como
higiene (vale para qualquer fluxo por e-mail que venha a ser usado), mas não é
pré-requisito do go-live.

**Alternativas descartadas:** `vite preview` como comando de produção (é
ferramenta de conferência local, sem garantias de produção); servidor estático
em Caddy/nginx (mais uma stack para manter, sem ganho no piloto); host estático
separado, ex. Vercel (descartado na DEC-007).

---

## DEC-038 — Gestão de residentes e prescrições autorizada por turno, não por PIN de admin
**Data:** 2026-07-21 | **Status:** aprovada (Sessão #8; inverte parcialmente a DEC-024)

**Decisão:** a autorização das RPCs de **residentes, medicamentos e
prescrições** deixa de ser `p_admin_id + p_admin_pin` / `fn_autorizar_admin` e
passa a ser **`fn_cuidador_do_turno()` — exige turno aberto**, o mesmo padrão
que as RPCs de estoque já usavam desde a Sessão #4. São nove: `criar_residente`,
`atualizar_residente`, `definir_ativo_residente`, `criar_medicamento`,
`atualizar_medicamento`, `definir_ativo_medicamento`, `criar_horario`,
`atualizar_horario`, `definir_ativo_horario`. Sem turno aberto elas retornam
`sem_turno_aberto` e não executam. Nenhuma outra regra dessas RPCs mudou.

A **gestão de equipe permanece sob a DEC-024, sem alteração alguma**:
`criar_cuidador`, `atualizar_cuidador`, `definir_ativo_cuidador`,
`redefinir_pin` e `autorizar_gestao` continuam exigindo PIN de administradora
validado no banco a cada chamada.

**Racional:** a trava de admin não protegia o histórico clínico — corrompia-o.
Uma residente volta da consulta com prescrição nova; a cuidadora do turno é
profissional de saúde habilitada e vai aplicar a mudança de qualquer forma, mas
não conseguia registrá-la sem a administradora presente (a admin não fica na
casa 24/7). Resultado: a mudança acontecia no mundo real e o app ficava com o
dado velho — a trilha de auditoria que a DEC-024 queria proteger sumia, porque
a ação real acontecia fora do sistema. O sistema não pode ser a trava que impede
o **registro** de uma decisão que a profissional está habilitada a tomar; manter
a trava não impedia a mudança, só a documentação dela.

**O que torna isso seguro é a DEC-026, que permanece intacta:** mudar
dose/horário de medicamento já administrado NÃO sobrescreve — versiona (desativa
a linha antiga, cria a nova). Abrir a edição de prescrição à cuidadora do turno
portanto não corrompe histórico nenhum; e como a ação passa a ser atribuída à
cuidadora do turno dentro do app, a auditoria **melhora** em relação ao estado
anterior. A separação de escopos também é conceitual: administrar *quem tem
acesso ao sistema* (equipe) é ato administrativo e segue sob admin; alterar o
cuidado de uma residente é ato clínico de quem está de plantão.

**No cliente:** a gestão de residentes deixa de ter tela de PIN; a de equipe
mantém a sua. O `eh_admin` da cuidadora do turno é carregado junto com o turno
apenas para decidir se o botão "Gestão equipe" aparece — **esconder botão nunca
é segurança**: quem barra é a RPC, que continua validando o PIN de admin no
banco.

**Alternativas descartadas:** manter tudo sob PIN de admin (o problema que
originou a decisão); criar um terceiro nível de permissão por cuidadora
(complexidade de administração que a casa não tem quem opere, para um piloto de
quatro pessoas); permitir a edição sem exigir turno aberto (perderia a
atribuição da autoria, que é justamente o que se queria ganhar).

---

## DEC-039 — Janela de "atrasada": 30 → 60 minutos (revisa a DEC-010)
**Data:** 2026-07-21 | **Status:** aprovada (Sessão #10; revisa a tolerância
fixada pela DEC-010)

**Contexto:** a demonstração do piloto à Thais (Sessão #9) validou o produto e
levantou ajustes de uso real. Um deles: com 30 min de tolerância, a dose salta
para "atrasada" (destaque vermelho) cedo demais para o ritmo da casa — uma ronda
que escorrega meia hora é rotina, não exceção, e o vermelho precoce vira ruído.
Alarme que soa o tempo todo deixa de ser sinal.

**Decisão:** a tolerância entre o horário previsto e a dose devida sem tratativa
ser marcada **"atrasada"** passa de **30 para 60 minutos**. Só esse número muda.

**Consequência consciente e aceita:** a dose fica "na hora"/pendente por mais
tempo antes de saltar como atrasada — menos alarme precoce, em troca de um
atraso real demorar um pouco mais a chamar atenção visual. Escolha do Guilherme,
a partir do uso observado.

**O que NÃO muda (importante):**
- `fechar_turno` continua exigindo tratativa de **toda** dose devida do turno,
  inclusive a que ainda está dentro da tolerância (DEC-010/DEC-022). A janela
  governa a COR/urgência na ronda, nunca a exigência de resposta: nenhuma dose
  deixa de ser respondida por causa deste ajuste, e o ledger e o relatório de
  adesão seguem com a mesma completude.
- A classificação de adesão (DEC-030) não depende da tolerância: ela vem do
  **status gravado** (`tomado_no_horario` × `tomado_atrasado`), que é escolha da
  cuidadora no modal, não do relógio.
- A janela de 15 min da "próxima ronda" e o rate limit de PIN de 15 min
  (DEC-021) são outras coisas e ficam intactos.
- A fila de pendências entre turnos (DEC-033) não usa tolerância — pendência é
  dose vencida em período sem turno aberto, sem meio-termo.

**Implementação:** a expressão vive num lugar só — `doses_do_turno`, fonte única
da lógica de slots (DEC-023), consumida tanto pela tela da ronda quanto pelo
`fechar_turno`. A migration `20260721000200_janela_atraso_60min` substitui a
versão vigente da função; os dois pontos históricos do schema (migrations
20260716000700 e 20260716001000, que redefinia a mesma função) convergem por
construção. Conferido no banco após aplicar: nenhuma função do schema `public`
ainda contém `30 minutes`.

**Alternativa descartada:** tornar a tolerância parametrizável (por casa, por
medicamento ou por horário). Um número configurável exigiria tela, decisão de
quem configura e um valor-padrão que continuaria sendo esta mesma escolha —
complexidade sem ganho num piloto de casa única. Se a parametrização virar
necessidade real no uso, ela nasce de dado observado, não de suposição.

## DEC-040 — Rastreamento de estoque por lote e validade: modelo de duas verdades
**Data:** 2026-07-22 | **Status:** aprovada (Sessão #11)

**Contexto:** até aqui o estoque era um saldo numérico por medicamento — o ledger
(`movimentacoes_estoque`) somava entradas/saídas e a view `saldo_estoque` derivava
um número. O sistema sabia *quanto* tinha, não *quais* unidades, de que lote, com
que validade. A Thais controla isso em Excel (data de entrada, lote, validade,
quantidade) e opera FEFO na bancada — sempre abre a caixa de validade mais
próxima. O objetivo é o app refletir essa operação para aposentar a planilha.

**Decisão — o saldo passa a ter duas verdades sincronizadas na mesma transação:**
- **`lotes_estoque`** = verdade do **saldo físico** na prateleira, por validade.
  Um lote físico de um medicamento: `medicamento_id`, `lote` (código impresso na
  caixa; NULL = "não identificado"), `validade` (obrigatória — chave do FEFO),
  `quantidade_inicial`, `saldo_atual` (≥ 0, meio-em-meio), `data_entrada`,
  `origem` (compra | remanescente), `criado_em`. **Não há agrupamento:** duas
  entradas do mesmo medicamento com o mesmo lote/validade são linhas separadas se
  registradas separadamente (cada entrada é um lote).
- **`movimentacoes_estoque` (ledger)** = verdade do **histórico e da cobertura**.
  Continua **intocado em forma**: uma linha por administração/entrada/ajuste/perda,
  com a UNIQUE em `administracao_id` preservada (DEC-008). Extrato (DEC-036),
  cobertura (DEC-027) e adesão (DEC-030) seguem lendo dele.
- **Vínculo `movimentacao_lote`** (movimentacao_id, lote_id, quantidade): como uma
  saída pode varrer vários lotes (FEFO, DEC-042), a relação movimentação↔lote é
  1-para-N. Tabela de ligação, e **não** uma linha de ledger por lote: mantém o
  ledger com uma linha por movimentação (extrato legível, UNIQUE de baixa intacta)
  e registra a distribuição por lote ao lado. `quantidade` com o **sinal do
  ledger** (entrada > 0, saída < 0).

**`saldo_estoque` passa a derivar da soma dos lotes** (`sum(saldo_atual)`), não
mais do ledger. **Invariante** (testado): `sum(lotes.saldo_atual) == soma do
ledger` por medicamento, em toda operação bem abastecida. A única divergência
possível é a anomalia **pré-existente** de super-administração (dose além do
físico): o ledger já tolerava saldo negativo; a prateleira física não pode ser
negativa, então os lotes piso em zero e o ledger guarda o registro completo para
auditoria/consumo. Não é um caso novo introduzido aqui — é o mesmo sinal de
anomalia que o saldo negativo já era.

**Atomicidade é o requisito nº 1:** lote e ledger são sempre escritos na mesma
transação, por dois helpers internos (SECURITY DEFINER, execute revogado de
`authenticated`): `fn_registrar_lote_entrada` (cria lote + vínculo +) e
`fn_consumir_fefo` (abate por FEFO + vínculos −). Nenhum caminho grava num e não
no outro. Migration `20260722000100_lotes_estoque_modelo`.

**Alternativa descartada:** uma linha de `movimentacoes_estoque` por lote afetado
numa saída. Quebraria a UNIQUE de `administracao_id` (uma dose → N linhas),
poluiria o extrato (N linhas por dose) e violaria a DEC-008. O vínculo separado
mantém o ledger estável.

## DEC-041 — Entradas capturam lote + validade nos três caminhos
**Data:** 2026-07-22 | **Status:** aprovada (Sessão #11)

**Contexto:** há três caminhos de ENTRADA de estoque, e todos precisam capturar
lote e validade para alimentar os lotes físicos (DEC-040).

**Decisão:** toda entrada exige **validade** (obrigatória) + **quantidade**, com
**lote** opcional (código da caixa; em branco = "não identificado") e data de
entrada (default hoje). Cria a linha em `lotes_estoque` **junto** com a
movimentação, na mesma transação:
- **`registrar_entrada_estoque`** (recompra e estoque inicial de origem *compra*)
  ganha `p_validade` e `p_lote`; origem do lote = `compra`, tipo da movimentação
  segue `entrada_compra` (DEC-016).
- **Estoque inicial no cadastro** ("+ Medicamento" e Residentes) passa por essas
  RPCs via `src/lib/estoqueInicial.js` — sem RPC nova. Compra →
  `registrar_entrada_estoque`; remanescente → `registrar_ajuste_estoque` (subida).
- **Ajuste de recontagem PARA CIMA** (`registrar_ajuste_estoque`, contagem > saldo
  dos lotes) exige validade: a unidade "a mais" pertence a algum lote físico que a
  casa tem em mãos. Se ela não souber o código, aceita **lote nulo** ("não
  identificado") com validade informada. Cria um lote de origem `remanescente`.

**Decisão menor documentada:** validade **no passado** é aceita (um remanescente
pode entrar já perto/na validade; sem alerta de vencimento nesta sessão, o ajuste
é manual). Bloquear seria inventar regra que o roteiro não pediu.

Migrations `20260722000200_entradas_com_lote` e `20260722000300_saidas_fefo`
(a subida do ajuste). Erro novo: `validade_obrigatoria`.

## DEC-042 — Saídas por FEFO automático (estende a DEC-008)
**Data:** 2026-07-22 | **Status:** aprovada (Sessão #11)

**Contexto:** três caminhos de SAÍDA — dose administrada (baixa automática, DEC-008),
ajuste de recontagem para baixo, e perda. Todos precisam abater dos lotes na ordem
que a casa já pratica na bancada.

**Decisão:** **todos abatem por FEFO** — sempre do lote de validade mais próxima
primeiro (`fn_consumir_fefo`), varrendo múltiplos lotes quando a quantidade excede
o saldo do lote da frente. Cada lote tocado gera um vínculo `movimentacao_lote` (−).
- **A ronda NÃO muda.** A cuidadora segue marcando tomado / recusado / não-tomado;
  a baixa por lote é **automática e silenciosa** — nenhuma escolha de lote, nenhum
  menu de inventário na ronda. Preserva a DEC-008 (baixa é consequência da
  administração) e o princípio de que a ronda é sobre cuidado, não estoque. A
  trigger `fn_baixa_automatica_estoque` grava a movimentação como antes e chama o
  FEFO em seguida.
- **O caso "0,5 restante" resolve-se sozinho:** o FEFO tira 0,5 do lote velho
  (zera) e 0,5 do próximo para completar 1 — sem menu, sem órfão.
- **Empate de validade:** desempata por `data_entrada` mais antiga (FIFO
  secundário), depois `criado_em`. Documentado e testado.
- **Ajuste para baixo** e **perda** seguem o mesmo FEFO; nunca excedem o físico
  (a quantidade sai do próprio saldo contado/existente), então cobrem sempre por
  completo.

**Best-effort e super-administração (edge documentado):** `fn_consumir_fefo` abate
o que houver e retorna quanto conseguiu. Se a dose excede o físico (medicamento
cadastrado sem estoque, ou super-administração), a movimentação de saída é gravada
**cheia** no ledger — a ronda nunca falha — e os lotes piso em zero. Nesse caso, e
só nele, `sum(lotes)` fica abaixo do ledger: é a mesma anomalia que o saldo
negativo já sinalizava (DEC-040), agora exibida como saldo zero (a prateleira não
tem unidade negativa). Escolha do Guilherme: sem alerta de vencimento automático
nesta sessão; ajuste manual da casa basta.

**Sobras / lotes residuais:** um lote com saldo residual (ex.: 0,5) fica visível
no estoque com seu lote e validade (DEC-043). Descarte/ajuste é ação **manual de
gestão**, fora da ronda — como a Thais já faz. Migration
`20260722000300_saidas_fefo`.

## DEC-043 — Lote e validade visíveis no estoque atual e no extrato
**Data:** 2026-07-22 | **Status:** aprovada (Sessão #11)

**Decisão:**
- No **estoque atual por residente**, junto de cada medicamento aparecem os lotes
  vivos (saldo > 0), **por validade crescente**, com validade e saldo — o próximo a
  vencer em destaque. Na lista, uma linha compacta de chips; na ficha do
  medicamento, um bloco "Lotes na prateleira" com uma linha por lote e o selo
  "Próximo a vencer" no primeiro. Fonte: view `lotes_estoque_vivo` (security
  invoker). Rótulo legível, sem jargão.
- O **extrato de movimentações** indica, em cada linha, o(s) lote(s) da
  movimentação — entrada mostra o lote/validade que criou; saída, de qual(is)
  lote(s) saiu, com a quantidade de cada. Reaproveita o vínculo `movimentacao_lote`:
  no extrato consolidado (DEC-036) via `extrato_medicamento` (campo `lotes`); na
  ficha da aba Estoque via embed direto de `movimentacao_lote → lotes_estoque`.

Migration `20260722000400_lotes_visiveis`. Tema Sereníssima, 375px, sem overflow
horizontal.

## DEC-044 — Estoque da casa por residente-sentinela "Da Casa"
**Data:** 2026-07-22 | **Status:** aprovada (Sessão #12)

**Contexto:** a casa tem SOS que não pertencem a ninguém em particular — dipirona
para dor de cabeça, antitérmico, antiemético; a caixa comum da bancada. O app
exigia dono para todo medicamento (`medicamentos.idoso_id` NOT NULL).

**Princípio que governa a decisão (e a Sessão #12 inteira):** o **estoque** pode
ser da casa; o **consumo tem sempre um dono**. "Saiu uma dipirona da casa, não sei
pra quem" é o rastro opaco que o Nami Care existe para eliminar.

**Decisão (Modelo B):** um **residente reservado** carrega o estoque
compartilhado.
- `medicamentos.idoso_id` **permanece NOT NULL** — o schema de medicamentos não
  muda, e os ~16 pontos do banco que fazem `join idosos` continuam intactos. Um
  medicamento da casa é um medicamento normal pendurado nesse residente.
- Identificação por **`idosos.eh_sentinela`** (booleano, com índice único parcial:
  no máximo um sentinela), nunca por id hardcodado — nada no código nem no seed
  depende de um uuid fixo. Rótulo inicial: "Da Casa", renomeável na gestão.
- **Sem flag `eh_da_casa` em medicamentos** — avaliada e descartada: um
  medicamento é da casa porque pertence AO residente da casa, e pronto. O único
  lugar que precisa excluir o sentinela (o seletor de "quem tomou", DEC-047)
  simplesmente não o inclui.
- A linha nasce de **bootstrap idempotente** (`fn_bootstrap_residente_da_casa`),
  chamado pela migration uma vez e pelo seed a cada `--reset` — não é migration de
  dados: um banco recriado do zero chega ao mesmo estado sozinho.
- **Medicamento da casa é sempre `tipo = 'sos'`**, garantido por trigger (pega
  também o seed, que escreve com service role por fora das RPCs): contínuo tem
  horário de ronda, e horário é de um residente. Contínuo compartilhado não
  existe; se um dia a casa precisar, é decisão nova.
- **O sentinela não é desativável** (`residente_da_casa_fixo`): desativá-lo tiraria
  o estoque da casa da cobertura e do fluxo SOS sem que nada tivesse mudado no
  mundo físico — a caixa comum continua na prateleira. Renomear/editar segue livre.

**Onde aparece, tela a tela:** gestão de residentes **aparece destacado em
vermelho** (é identificação visual, não alerta de erro) e fora da contagem de
"ativos"; "+ Medicamento" **aparece** (é assim que uma compra entra no estoque da
casa — escondê-lo tornaria o medicamento da casa incadastrável); estoque atual
aparece em **seção própria "Medicamentos da casa"**; adesão **não** aparece
(DEC-046); seletor de quem toma **não** aparece (DEC-047); ronda não aparece por
construção (é SOS, não tem grade).

Estoque/lote/validade/FEFO da Sessão #11 valem sem exceção — nada de estoque foi
reimplementado. Migration `20260722000500_residente_da_casa` (que também acrescenta
`idoso_da_casa` à view `cobertura_estoque`, o único dado novo que as telas pedem).

## DEC-045 — Dono real da dose: `administracoes.idoso_id`
**Data:** 2026-07-22 | **Status:** aprovada (Sessão #12)

**Contexto:** `administracoes` não tinha "quem tomou" — o residente sempre foi
derivado por `administracoes.medicamento_id → medicamentos.idoso_id`. Para um
medicamento da casa essa corrente aponta para o sentinela, não para a pessoa.

**Decisão:** coluna **`idoso_id` (nullable, FK para `idosos`)** em
`administracoes` = o residente que efetivamente tomou. É a **única mudança de
schema** do Modelo B.

**Preenchimento — três casos, um só caminho preenche:**
| dose | `administracoes.idoso_id` |
|---|---|
| agendada (contínua, `horario_id` não nulo) | **nulo** |
| SOS de medicamento **de um residente** | **nulo** (o dono vem do medicamento) |
| SOS de medicamento **da casa** | **preenchido** com quem tomou |

**Resolução do dono (uma regra, vale para todos):**
`coalesce(administracoes.idoso_id, medicamentos.idoso_id)` — o residente-que-tomou
se preenchido, senão o dono do medicamento. Aplica-se na adesão (DEC-046) e em
qualquer lugar que derive o residente de uma dose.

**Integridade por trigger, não por CHECK** (`fn_administracao_dono_valido`): a
regra depende de uma linha de `idosos` (o medicamento é da casa?), fora do alcance
de um CHECK. Os dois lados são fechados — SOS da casa **sem** dono é rejeitado, e
dose de medicamento de residente **com** dono também é: divergência entre dois
donos é pior que a ausência de um, porque parece informação. O trigger recusa
ainda o sentinela como "quem tomou" e horário agendado em medicamento da casa.

**A dose agendada não muda em nada** — mesmo insert, mesma tela da ronda, coluna
nula. A imutabilidade (DEC-008) foi estendida à coluna nova. Migration
`20260722000600_dono_da_dose`.

## DEC-046 — Adesão conta pelo dono resolvido (estende a DEC-030)
**Data:** 2026-07-22 | **Status:** aprovada (Sessão #12)

**Contexto:** `relatorio_adesao` atribuía toda dose a `medicamentos.idoso_id`. A
dipirona que a dona Maria tomou da caixa comum cairia na adesão do "Da Casa" — um
residente que não existe, cobrindo justamente o que o relatório deve mostrar.

**Decisão:** o residente de uma dose passa a ser o **dono resolvido** da DEC-045,
`coalesce(a.idoso_id, m.idoso_id)`, **no trecho de SOS e no de doses agendadas** —
nas agendadas é literalmente o mesmo valor de antes (a coluna é sempre nula ali);
escrever o coalesce nos dois lugares deixa UMA regra na cabeça de quem lê, não
duas. O filtro `p_idoso_id` segue o mesmo dono resolvido: a Maria vê, na adesão
dela, também o que tomou da casa.

**Consequência desejada:** o "Da Casa" **não gera linha de adesão** — como ninguém
"é" a casa em consumo, nenhuma dose resolve para ele. A tela ainda o remove do
seletor de residente, para não oferecer um filtro que sempre voltaria zero.

O resto do relatório não muda: denominador materializado, as cinco categorias
(DEC-030/034), pendentes do turno aberto, fronteira de dia no fuso da casa.
Diferença linha a linha em relação à versão da Sessão #9: só o coalesce.
Migration `20260722000700_adesao_dono_real`.

## DEC-047 — Dose SOS reestruturada: quem toma → qual medicamento (revisa a DEC-014)
**Data:** 2026-07-22 | **Status:** aprovada (Sessão #12)

**Contexto:** a tela de dose avulsa montava a lista a partir do estoque SOS **por
residente**: só aparecia quem já tinha um SOS próprio, e o medicamento vinha preso
ao residente. Não havia como dar um SOS da casa a um residente qualquer.

**Decisão — inverter a ordem:**
1. **Quem toma:** todos os residentes ativos, **exceto o "Da Casa"**. É aqui, e só
   aqui, que o sentinela é escondido — por não entrar na lista. A lista independe
   de haver estoque: é justamente o ponto.
2. **Qual medicamento:** os SOS ativos **daquele residente** + os SOS **da casa**,
   numa lista só, com o saldo de cada. Os dois coexistem — a Maria pode ter o SOS
   particular dela e também tomar da caixa comum; o da casa leva o selo "Da casa".
3. **Quantidade** (meio-em-meio preservado) e registro com o **horário real** do
   momento (`registrado_em` = agora; `horario_id` nulo, como sempre).
4. **Dono da dose** gravado conforme a DEC-045.
5. **Baixa de estoque:** trigger da DEC-008 + FEFO da DEC-042, sem nada novo.

**Nota de implementação (decidida aqui): a dose SOS virou RPC.** Antes era INSERT
direto do cliente. Como agora há regra a garantir, deixá-la no cliente seria pôr
regra de negócio fora do banco. `registrar_dose_sos` valida e **normaliza**:
recebe sempre quem tomou (é o passo 1 da tela — o cliente não precisa conhecer a
regra) e decide se grava ou descarta o dono. Recusa medicamento não-SOS, inativo,
da caixa de **outro** residente (`medicamento_de_outro_residente`) e o sentinela
como quem toma. Para fechar a porta, a política de INSERT de `administracoes`
passou a exigir `horario_id` não nulo: **INSERT direto do cliente = dose agendada**
(o que a ronda sempre fez), SOS só pela RPC. Caminhos SECURITY DEFINER (a própria
RPC, a resolução em lote de pendências) rodam como owner e não passam por RLS.

**A ronda não muda.** Migration `20260722000800_dose_sos_reestruturada`.

## DEC-048 — Fonte única da adesão e extrato por categoria (estende a DEC-030 e a DEC-046)
**Data:** 2026-07-23 | **Status:** aprovada (Sessão #13)

**Contexto:** o relatório de adesão entrega só o agregado. Depois da Sessão #12, o
Guilherme registrou uma dose SOS de dipirona **da casa** para a Alzira: o dado foi
gravado certo — a adesão dela somou +1 SOS, o extrato da dipirona registrou a
baixa —, mas **nenhuma tela mostrava que foi a Alzira quem tomou**. Dava para
saber que houve 3 não tomadas no período, nunca *quais*. Sem o "quais", não há
como agir sobre uma não adesão, que é justamente o motivo de existir do relatório.

**O risco real não era a listagem — era a segunda implementação.** `relatorio_adesao`
contava as categorias com um `where` escrito dentro dela. Se o detalhe nascesse
como RPC separada com `where` próprio, passariam a existir **duas implementações
da mesma pergunta**. No dia em que divergissem, a tela diria "4 não tomadas" e
listaria 3 — e o relatório inteiro perderia a confiança da cuidadora. O projeto já
resolveu esse padrão uma vez: a ronda consome `doses_do_turno` e não recalcula
slots.

**Decisão — uma fonte, dois consumidores:**
1. Nasce **`fn_doses_adesao(p_inicio, p_fim, p_idoso_id)`** como fonte única das
   doses que compõem a adesão: uma linha por `administracoes` no período.
   `relatorio_adesao` é reescrita para **contar em cima dela**
   (`count(*) filter (where categoria = ...)`); o detalhe é a **mesma função
   filtrada**. Por construção, o que se lista é o que se conta.
2. A **regra de período assimétrica** mora nela e só nela: dose agendada filtra por
   `prevista_em`, dose SOS por `registrado_em` (SOS não tem `prevista_em` —
   DEC-014/023). Antes estava espalhada em dois `select`.
3. O **dono resolvido** `coalesce(a.idoso_id, m.idoso_id)` (DEC-045/046) e o
   mapeamento status → categoria passam a viver no mesmo lugar. As chaves são
   exatamente as que o JSON já devolvia e que a tela já usava
   (`no_horario`, `atrasada`, `recusada`, `nao_tomada`, `nao_apurada`, `sos`) —
   **sem camada de tradução entre banco e tela**.
4. `relatorio_adesao` manteve **assinatura e JSON idênticos, campo por campo**.
   A parte 1 desta sessão é refactor puro; provado comparando o jsonb inteiro
   antes × depois, para a casa e cada residente, em três períodos: **39
   comparações, 0 divergências**.

**Fora da função, de propósito:** `pendentes` (doses vencidas sem tratativa no
turno aberto). São doses que **ainda não têm linha em `administracoes`** — fonte
estruturalmente diferente, que continua vindo de `doses_do_turno`. A faixa amarela
delas no rodapé do card não é categoria e não ganha clique.

**Decisão — o extrato (`detalhe_adesao`):**
- **Só na visão por residente.** A RPC exige `p_idoso_id` (`residente_obrigatorio`);
  na visão "Toda a casa" as barras não são clicáveis, com uma dica curta no lugar.
  Uma lista de centenas de doses de onze pessoas não ajuda a agir sobre nenhuma.
- **As cinco categorias existentes** ganham clique — inclusive "Pendente (não
  apurado)" — mais a linha de **SOS**. **Nenhuma categoria nova é criada**, e o
  cálculo da adesão não muda em nada.
- Abrem **mesmo com zero**: a lista vazia é resposta ("nenhuma dose nesta
  categoria"), não um beco.
- **Teto de 200 linhas**, mais recentes primeiro, ordenadas pelo **instante de
  referência** (`prevista_em` na agendada, `registrado_em` no SOS — a mesma
  assimetria do período governando a ordem). `total` devolve a contagem **real**
  antes do corte e `truncado` diz que houve corte: a tela avisa sempre. Uma lista
  que mente sobre o próprio tamanho é pior que lista nenhuma.
- A categoria decide o que a linha diz: **atrasada mostra previsto × registrado**
  ("previsto 21/07, 08:00, registrado 10:03") porque o buraco entre os dois é a
  informação; "pendente" marca que veio da resolução em lote (DEC-034); SOS leva
  o chip **"Da casa"** quando o medicamento é da caixa comum. `observacao`, quando
  existe, vira linha secundária — quando não existe, a linha não é renderizada,
  sem placeholder.
- O sentinela "Da Casa" não precisou de caso especial: nenhuma dose resolve para
  ele (DEC-046), então a lista vem naturalmente vazia.

**Nada de schema.** Todo o dado já estava gravado desde a DEC-045. Migrations
`20260723000100_adesao_fonte_unica` e `20260723000200_detalhe_adesao`.

## DEC-049 — Dono da dose visível no extrato e leitura unificada do ledger (estende a DEC-036/043/045)
**Data:** 2026-07-23 | **Status:** aprovada (Sessão #13)

**Contexto — duas coisas ligadas pela mesma causa.**

**(a)** No extrato de um medicamento **da casa**, a baixa aparecia com data, hora,
cuidadora, lote e validade — mas não com **quem tomou**, que é justamente o que a
DEC-045 passou a gravar. O estoque compartilhado não criou o problema; tornou-o
visível.

**(b)** O extrato de movimentação existia em **duas telas que liam o ledger por
caminhos diferentes**: `FichaEstoque` lia `movimentacoes_estoque` direto pelo
PostgREST (últimas 50, sem período, rotulando por **`tipo`**) e
`ExtratoMovimentacoes` lia pela RPC `extrato_medicamento` (com período e filtro de
subtipo, rotulando por **`subtipo`**). Isso já produzia divergência: um ajuste de
contagem para baixo lia "Ajuste de contagem" numa tela e "Ajuste de contagem (a
menos)" na outra. E impedia (a): pelo caminho direto, resolver o `coalesce` do
dono e o teste de sentinela exigiria a regra **em JavaScript**, contra a convenção
de manter regra de negócio no banco.

**Decisão — unificar (Opção A).** A ficha passa a consumir `extrato_medicamento`.
Uma leitura só do ledger; a inconsistência de rótulo morre junto, e
`ROTULO_MOVIMENTACAO` foi removido do `formato.js` por ficar sem uso.

Para a RPC atender a ficha, ganhou **período opcional**:
- ambos nulos → **sem recorte de data, últimas 50** (o comportamento que a ficha
  sempre teve);
- ambos preenchidos → como antes;
- **um só nulo → `periodo_invalido`** (meio período é engano de chamada, não
  intenção).

A assinatura antiga, de quatro parâmetros obrigatórios, foi **removida com
`drop function`** antes do replace — duas sobrecargas com os mesmos tipos e
defaults diferentes deixariam o schema ambíguo.

**Campo novo `residente`**, preenchido **só** quando a movimentação é baixa por
dose tomada (`subtipo = 'dose'`, com `administracao_id`) **e** o medicamento é da
casa, pelo dono resolvido `coalesce(a.idoso_id, m.idoso_id)`. Em medicamento já
vinculado a um residente seria redundante — o cabeçalho da tela já diz de quem é.
Compra, ajuste, perda e perda por recusa **nunca** mostram residente. Rótulos
exatos, para não haver dois nomes soltos na mesma linha: **`Cuidadora: Ana`** e
**`Residente: Alzira`**.

Tudo o mais preservado: subtipo derivado pelo **sinal** da quantidade, filtro
combinável, `lotes` por movimentação (DEC-043), bloco `medicamento`. Somente
leitura — nenhuma escrita no ledger, nenhuma mudança de schema. Migration
`20260723000300_extrato_dono_da_dose`.
