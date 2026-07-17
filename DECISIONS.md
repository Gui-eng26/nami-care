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
**Data:** 2026-07-15 | **Status:** aprovada

**Decisão:** Dose pode ser confirmada até 30 min após o horário agendado. Depois
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
(Sessão #3): permanece válida para a **operação** (ronda, tratativas, estoque);
os **cadastros** (cuidadoras, residentes, medicamentos, horários) passaram a
exigir administradora.

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
**Data:** 2026-07-16 | **Status:** aprovada (Sessão #3; substitui parcialmente a DEC-011)

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