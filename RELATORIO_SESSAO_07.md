# RELATÓRIO — Sessão Claude Code #7

> Deploy e go-live: produção no ar, PWA instalável e ferramental de
> bootstrap dos dados reais.
> Data: 2026-07-21 | Modelo: Claude Opus 4.8 | Roteiro: `SESSAO_07.md`

**URL de produção: https://nami-care-production.up.railway.app**

---

## 1. Resumo executivo

Sessão de infraestrutura, sem nenhuma mudança de produto. **O app está no ar** e
o PWA está instalável; o que falta é o que depende de dado que só a casa tem
(nomes, prescrições, contagem de estoque, PIN da Thais), **preparado e
documentado como runbook**.

**Concluído nesta sessão:**

- **Produção no ar (DEC-037):** serviço no Railway servindo o build estático,
  reprodutível a partir do repositório — `railway.json` (build + start),
  `.node-version`, `npm run start` servindo `dist/` em modo SPA. O dev server do
  Vite não roda em produção. Verificado na URL pública (§3).
- **PWA instalável:** ícones PNG 192/512 (any e maskable) + apple-touch-icon e
  favicon, gerados do logo real da casa por script reprodutível
  (`npm run icones`). Manifest atualizado e conferido no build servido.
- **Ferramental do go-live:** `npm run limpar-banco` (apaga o seed de teste sem
  repopular) e `npm run criar-admin` (bootstrap da primeira administradora, PIN
  digitado por ela, sem eco na tela, hash gerado no banco).
- **Verificação empírica do Auth:** o app usa só `signInWithPassword` — Site URL
  e Redirect URLs **não bloqueiam** o login pela URL do Railway (detalhe em §5).
- Advisors revisados: sem novidade não intencional.

**Aberto (depende do Guilherme/Thais — runbook em §6):** limpar o banco de teste
e cadastrar os dados reais; instalar o app no celular da casa.

**Estado do MVP:** produto e infraestrutura prontos e publicados; **piloto ainda
não iniciado** — falta o banco de produção receber os dados reais.

## 2. O que foi construído

### Arquivos novos

| Arquivo | Conteúdo |
|---|---|
| `railway.json` | Builder NIXPACKS, `buildCommand: npm run build`, `startCommand: npm run start`, restart em falha. O deploy passa a ser reprodutível pelo repositório, não por cliques no painel. |
| `.node-version` | Node 22 fixado para o build do Railway. |
| `scripts/gerar-icones.js` | Recorta o **símbolo** do logo (bounding box detectada por varredura de tinta dentro do círculo branco: 147×147 em 250,443), redimensiona com lanczos3 e compõe sobre o creme `#faf6ee` com blend `multiply` — o branco do recorte vira creme sem emenda e o traço dourado é preservado. Gera 6 arquivos. |
| `scripts/limpar-banco.js` | Apaga todo o schema `public` na ordem inversa das FKs, **sem repopular** — o `seed --reset` reinsere dados fictícios, o que não pode acontecer em produção. Mostra as contagens e exige digitar `APAGAR`. Não toca em `auth.users` (o login da casa continua válido). |
| `scripts/criar-admin.js` | Bootstrap da PRIMEIRA administradora (DEC-024). Nome perguntado no terminal; PIN digitado pela própria pessoa **sem eco na tela**, com confirmação; hash gerado no banco por `fn_hash_pin` (bcrypt, DEC-020). Recusa-se a rodar se já houver qualquer cuidadora — se for o seed de teste, manda rodar `limpar-banco` antes. |

### Arquivos alterados

| Arquivo | Mudança |
|---|---|
| `vite.config.js` | Manifest com 4 ícones PNG (192/512 × any/maskable); `scope: "/"`; `includeAssets` com apple-touch-icon e favicon; `workbox.globIgnores` excluindo `logo-serenissima.png` do precache (915 KB que nenhuma tela usa). `name`, `short_name`, cores, `display` e `orientation` inalterados. |
| `index.html` | `favicon.png` e `apple-touch-icon` no lugar do SVG. |
| `package.json` | Scripts `start`, `icones`, `criar-admin`, `limpar-banco`; `serve` em dependencies; `sharp` em devDependencies. |
| `.claude/launch.json` | Configuração `nami-care-prod` (roda o mesmo `npm run start` da produção, porta 4173) para conferir o build servido, não só o dev server. |

### Arquivos removidos

`public/icons/icon.svg` e `icon-maskable.svg` — eram os placeholders teal
`#0f766e` da Sessão #1, fora da identidade Sereníssima e sem uso após os PNGs.

### Ícones gerados (`public/icons/`)

| Arquivo | Tamanho | Símbolo | Peso |
|---|---|---|---|
| `icon-192.png` | 192×192 | 78% | 17 KB |
| `icon-512.png` | 512×512 | 78% | 79 KB |
| `icon-maskable-192.png` | 192×192 | 55% | 10 KB |
| `icon-maskable-512.png` | 512×512 | 55% | 48 KB |
| `apple-touch-icon.png` | 180×180 | 78% | 15 KB |
| `favicon.png` | 64×64 | 78% | 3 KB |

Os 55% da variante maskable deixam o símbolo folgado dentro da zona segura (80%
central) de qualquer máscara do Android. A compressão em paleta de 256 cores
cortou os arquivos em ~20× sem diferença visível — importante porque os ícones
entram no precache do service worker.

## 3. Verificações executadas

### Na URL de produção (https://nami-care-production.up.railway.app, 375px)

| Verificação | Resultado |
|---|---|
| Tela de login | Renderiza no tema Sereníssima; console sem erros |
| HTTPS + service worker | Registrado, escopo `/` — requisito de instalabilidade atendido |
| `manifest.webmanifest` | 200 `application/manifest+json`, com os 4 ícones PNG |
| Os 6 PNGs (`/icons/*.png`) | 200 `image/png`, bytes idênticos aos gerados localmente |
| Bundle servido | URL e anon key corretas do projeto embutidas no build |
| Vazamento de segredo no bundle | Nenhum — `SUPABASE_SERVICE_ROLE_KEY` e `CASA_SENHA` ausentes |
| Supabase a partir da origem de produção | 401 do REST sem chave (não erro de CORS) — RLS intacta |

### Build local e PWA (build de produção servido por `npm run start`, viewport 375px)

| Verificação | Resultado |
|---|---|
| `npm run build` | OK — 86 módulos, precache de 11 entradas, `sw.js` + `workbox-*.js` gerados |
| `manifest.webmanifest` servido | 200; `name`, `short_name: Sereníssima`, `display: standalone`, `theme_color: #8f7038` preservados |
| Os 4 ícones do manifest | 200 `image/png` cada |
| `sw.js` | 200 `application/javascript`; service worker registrado (1 registration) |
| Precache | Os 6 PNGs + JS/CSS/HTML/manifest; `logo-serenissima.png` fora, como previsto |
| Tela de login servida pelo estático | Renderiza no tema Sereníssima, sem erro nenhum no console |
| Bundle de produção | Contém a URL e a anon key corretas do projeto `uvkmvaheupziexlunnno` |
| Alcance do Supabase a partir da página servida | 401 do REST sem chave (não erro de CORS) — origem e chave corretos, RLS intacta |

### Scripts do go-live (contra o banco real, sem escrever nada)

| Verificação | Resultado |
|---|---|
| `npm run criar-admin` com banco populado | Recusa corretamente, lista as 5 cuidadoras existentes e aponta o `limpar-banco` |
| `npm run limpar-banco` com resposta ≠ `APAGAR` | Mostra as contagens (139 linhas) e cancela sem apagar nada |

### Estado do banco ao final da sessão

Inalterado, ainda com o seed de teste e os resíduos das conferências da Sessão
#6 no navegador: 5 cuidadoras, 12 residentes, 23 itens de catálogo, 25
medicamentos, 26 horários, 26 movimentações, 6 turnos, 0 administrações.
**Nada foi apagado nem inserido nesta sessão** — a limpeza é o primeiro passo do
runbook do go-live, para não deixar o Guilherme sem base de teste antes da hora.

## 4. Security advisors

Revisados antes do go-live. **Sem novidade não intencional** — exatamente o
mesmo conjunto já aceito e documentado nas sessões anteriores:

- 20 avisos `authenticated_security_definer_function_executable`: as RPCs de
  gestão, turno e estoque, que são SECURITY DEFINER de propósito (validam PIN no
  banco — DEC-020/024). Categoria aceita desde a Sessão #3.
- `rls_policy_always_true` em `administracoes` INSERT e `rls_enabled_no_policy`
  em `tentativas_pin`: idem, já documentados.
- `auth_leaked_password_protection`: **encerrado na Sessão #5** — indisponível no
  plano Free, mitigado com senha aleatória forte da casa e comprimento mínimo 12.

## 5. Achado: o Supabase Auth não bloqueia a URL de produção

O roteiro previa que, sem cadastrar a URL do Railway no Auth, o login falharia
por redirect/origin não permitido. **Verificado que não é o caso neste app:**

- O app usa exclusivamente `supabase.auth.signInWithPassword`
  (`src/pages/LoginCasa.jsx:16`) — não há magic link, OAuth nem recuperação de
  senha, que são os fluxos governados por Site URL / Redirect URLs.
- Requisição ao endpoint de Auth com uma origem `*.up.railway.app` fabricada
  respondeu `access-control-allow-origin` ecoando essa mesma origem e `400`
  (credencial inválida, como esperado) — não erro de CORS.

**Conclusão:** cadastrar a URL de produção em Site URL continua **recomendado
como higiene** (passa a valer no dia em que algum fluxo por e-mail for usado),
mas **não é pré-requisito do go-live**. Registrado na DEC-037.

## 6. Runbook do go-live (Guilherme)

Executar nesta ordem. Cada passo depende do anterior.

> **Passos 1 a 3 concluídos** (2026-07-21): repositório publicado, serviço no ar
> em https://nami-care-production.up.railway.app e URLs do Auth configuradas.
> Ficam registrados para referência e para o caso de precisar recriar o
> ambiente. O go-live continua no passo 4.

### Passo 1 — Publicar o repositório ✅

```bash
git add -A && git commit -m "feat: preparacao de deploy, PWA instalavel e bootstrap do go-live"
git push
```

### Passo 2 — Criar o serviço no Railway ✅

1. Railway → New Project → **Deploy from GitHub repo** → `Gui-eng26/nami-care`.
2. O `railway.json` do repositório já define build e start — não é preciso
   digitar comando nenhum no painel.
3. Variáveis do serviço (Settings → Variables) — **só estas duas**:
   - `VITE_SUPABASE_URL` = `https://uvkmvaheupziexlunnno.supabase.co`
   - `VITE_SUPABASE_ANON_KEY` = a anon key do projeto (a mesma do `.env.local`)

   **Nunca** colocar `SUPABASE_SERVICE_ROLE_KEY`, `CASA_EMAIL` ou `CASA_SENHA`
   aqui: tudo que o serviço de frontend vê pode acabar no bundle público.
4. Settings → Networking → **Generate Domain**. Anote a URL
   (`https://<algo>.up.railway.app`).
5. Abra a URL: deve aparecer a tela de login "Residencial Senior Sereníssima".
   Faça login com `casa@namicare.app` (senha no `.env.local`) para confirmar.

> Se em algum momento o deploy subir mas a página ficar em branco, é sinal de
> que as variáveis `VITE_*` não estavam presentes **no momento do build** — o
> Vite embute essas variáveis no bundle. Basta redeployar depois de definí-las.

### Passo 3 — Supabase Auth (higiene, não bloqueia) ✅

Dashboard → Authentication → URL Configuration, como ficou configurado:

- **Site URL:** `https://nami-care-production.up.railway.app` — **com o
  `https://`**; o campo espera a URL completa, não só o host.
- **Redirect URLs (2):** `https://nami-care-production.up.railway.app/**` e
  `http://localhost:5173/**`, mantendo o desenvolvimento funcionando.

Nenhum dos dois bloqueia o login deste app (§5) — valem para o dia em que algum
fluxo por e-mail (recuperação de senha, magic link) for usado.

> O botão "Save changes" aparecer apagado é o estado normal de "nada pendente":
> o Supabase só o habilita quando o campo difere do valor gravado. As Redirect
> URLs, por sua vez, gravam no ato do "Add URL" — a lista renderizada já é o
> estado do servidor.

### Passo 4 — Instalar no celular da casa

Abrir **https://nami-care-production.up.railway.app** no celular.

No **Chrome do Android** (não em outro navegador), abrir a URL do Railway e:
menu ⋮ → **Instalar aplicativo** (ou "Adicionar à tela inicial"). O ícone da
casinha dourada sobre creme aparece na tela inicial e o app abre em tela cheia,
sem barra de endereço.

No iPhone: Safari → Compartilhar → **Adicionar à Tela de Início**.

Faça o login da casa **uma única vez** no aparelho — a partir daí a troca de
cuidadora é só pelo PIN do turno (DEC-019).

### Passo 5 — Limpar o banco de teste

⚠️ Ponto sem volta. Depois daqui não há mais base de teste — faça os testes
funcionais que quiser **antes**.

```bash
npm run limpar-banco     # mostra as contagens e pede APAGAR
```

### Passo 6 — Bootstrap da Thais

Com a Thais junto, no seu computador:

```bash
npm run criar-admin      # nome dela; PIN digitado por ela, sem aparecer na tela
```

O PIN não é gravado em arquivo nenhum: vai direto para o hash bcrypt no banco.
Se ela esquecer, o caminho é `redefinir_pin` por outra admin — por isso vale
criar a segunda admin cedo.

### Passo 7 — Cadastro real pelo app

Tudo daqui em diante é **pela tela de gestão**, logada como a Thais. Sem SQL.

1. **Cuidadoras** (Gestão → Cuidadoras): as outras 3. Cada uma escolhe o próprio
   PIN — não invente um provisório. Marque ao menos mais uma como admin.
2. **Residentes** (Gestão → Residentes): os 11.
3. **Prescrições**: para cada residente, medicamento → horários.
   **Sempre pelo catálogo (DEC-035):** o primeiro cadastro de cada remédio cria
   o item do catálogo; do segundo residente em diante, **busque e selecione** o
   item já existente — nunca redigite o nome. Nome, dosagem e forma são herdados
   e ficam read-only, o que é a confirmação visual de que reaproveitou.
4. **Estoque inicial** (aba Estoque → medicamento → registrar): lance a última
   contagem manual como movimentação, **com a data real da contagem**.
   - Se a Thais souber que aquilo foi uma compra, use **entrada de compra**.
   - Se for simplesmente "isto é o que tem na prateleira hoje", use **ajuste por
     contagem** — é o registro honesto para um saldo de origem desconhecida.

### Passo 8 — Conferir no navegador (não só no banco)

- [ ] Thais loga com o PIN dela e a gestão abre.
- [ ] Um remédio que dois residentes tomam aparece **uma vez** no extrato
      consolidado, com o badge "2 residentes".
- [ ] O estoque inicial de cada medicamento aparece no extrato de movimentações,
      na data da contagem.
- [ ] A ronda mostra as doses do horário corrente para os residentes certos.

## 7. Pendências

| # | Pendência | Dono |
|---|---|---|
| 1 | Executar os passos 4–8 do runbook §6 (instalação no celular, limpeza do banco, bootstrap da Thais, dados reais). Passos 1–3 já feitos. | Guilherme + Thais |
| 2 | Logo definitivo refinado do PWA — os ícones atuais vêm de um print do Instagram, upscalado de 147px. Legível e on-brand, mas um vetor original daria traço mais limpo. Trocar o arquivo e rodar `npm run icones` (recalcular a bounding box em `scripts/gerar-icones.js` se o enquadramento mudar). | Guilherme |
| 3 | Usar o logo horizontal completo no cabeçalho / tela de login — não foi feito porque esta sessão não podia mexer em tela (restrição do roteiro). | sessão futura |
| 4 | Bloqueio por inatividade (repedir PIN — DEC-002): reavaliar depois do piloto começar. | pós-piloto |
| 5 | Revisar este relatório, salvar no Drive, commit + push. | Guilherme |

## 8. Acompanhamento assistido da 1ª semana

Proposta a alinhar com o Guilherme (ROADMAP: piloto assistido):

- **Dia 1, presencial ou por vídeo, com as 4 cuidadoras:** abrir turno com PIN,
  ronda, tratativa de dose atrasada, dose SOS, fechar turno. O ponto que mais
  gera dúvida é o fechamento obrigatório — explicar que ele existe para o
  estoque não mentir.
- **Treinar a distinção da Sessão 5.5:** "não tomada" (sabemos que o residente
  não tomou) × "pendente / não apurado" (ninguém registrou e decidimos não
  apurar). A segunda **não** baixa estoque e aparece à parte no relatório de
  adesão. Se a equipe usar as duas como sinônimo, o relatório perde sentido.
- **Observar a aba vermelha "Pendências entre turnos":** se ela aparecer muito
  na primeira semana, é sinal de lacuna de cobertura de turno, não de bug.
- **Conferência de estoque no fim da 1ª semana:** contagem física de 3 ou 4
  medicamentos contra o saldo do app. Divergência esperada < 5% (BRIEFING §10).
  É a evidência que convence a Thais a abandonar a contagem semanal completa.
- **Métrica de sucesso do piloto:** Thais abandona a contagem semanal completa em
  ≤ 4 semanas.
