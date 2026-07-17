# RELATÓRIO — Sessão Claude Code #3

> Gestão de cadastros (equipe, residentes, prescrições) e identidade
> visual Sereníssima.
> Data: 2026-07-16 | Modelo: Claude Fable 5 | Roteiro: `SESSAO_03.md`

---

## 1. Resumo executivo

A Sessão #3 foi concluída integralmente. O sistema deixou de ser "demo com
dados do seed": a administradora agora cadastra cuidadoras (com PIN gerado e
hasheado só no banco), residentes e prescrições completas (medicamento, dose
com fração 0,5, horários das rondas, flag SOS) pelas telas — o critério de
pronto ("cadastrar as 4 cuidadoras e os 11 residentes reais sem tocar no
banco na mão") está atendido. O app inteiro ganhou a identidade do
Residencial Senior Sereníssima (dourado sobre creme), sem alterar o
comportamento da ronda/turno da Sessão #2.

**Decisões novas:** DEC-024 (acesso à gestão: flag `eh_admin` + PIN de
administradora validado no banco em CADA RPC de gestão; substitui
parcialmente a DEC-011), DEC-025 (troca de PIN: self-service com PIN atual ou
reset por administradora) e DEC-026 (prescrição versionada: campos clínicos
imutáveis após uso; alteração = desativa + cria versão nova).

**Bug corrigido:** BUG-001 — a RPC `definir_pin` da Sessão #2 trocava o PIN
de qualquer cuidadora sem verificação nenhuma. Removida e substituída por
`trocar_pin`/`redefinir_pin`.

**Banco ao final da sessão:** resetado para o estado limpo do seed
(4 cuidadoras — Ana Souza como administradora —, 11 residentes, 850 unidades
de estoque, 0 turnos/administrações/tentativas de PIN).

## 2. O que foi construído

### Migrations novas (aplicadas no projeto `nami-care` e espelhadas no repo)

| Arquivo | Conteúdo |
|---|---|
| `20260716000900_gestao_cuidadores.sql` | `cuidadores.eh_admin`; `fn_verificar_pin` e `fn_autorizar_admin` (internas — PIN + rate limit + trilha); RPCs `criar_cuidador`, `atualizar_cuidador`, `definir_ativo_cuidador`, `trocar_pin`, `redefinir_pin`; drop de `definir_pin` (BUG-001); escrita direta em `cuidadores` totalmente revogada; Ana Souza promovida a admin no seed existente |
| `20260716001000_gestao_residentes.sql` | `idosos.ativo` (soft delete); RPCs `criar_residente`, `atualizar_residente`, `definir_ativo_residente`; INSERT/UPDATE revogados; `doses_do_turno` passa a ignorar residentes desativados |
| `20260716001100_gestao_prescricoes.sql` | Triggers de imutabilidade clínica (DEC-026) em `medicamentos` (nome/dosagem/forma) e `horarios` (hora/qtd_dose); índice único parcial `(medicamento_id, hora) where ativo`; RPCs `criar/atualizar/definir_ativo_medicamento` e `criar/atualizar/definir_ativo_horario` (com versionamento automático); INSERT/UPDATE revogados |
| `20260716001200_rpc_autorizar_gestao.sql` | RPC `autorizar_gestao` — porta de entrada da área de gestão (valida a credencial antes de abrir as telas) |

### Modelo de autorização da gestão (DEC-024)

- Cada RPC de gestão recebe `p_admin_id + p_admin_pin` e valida no banco:
  cuidadora ativa + flag admin + bcrypt + rate limit (5 falhas/15 min,
  DEC-021). **Não existe estado de sessão de gestão no servidor** — o app
  guarda o PIN só em memória e reenvia a cada chamada.
- Efeito colateral desejado: toda ação de gestão fica auditada em
  `tentativas_pin` (no teste do ciclo completo, 13 verificações registradas).
- Erros de negócio voltam como `{ok:false, erro:...}` (mesmo contrato da
  Sessão #2); o mapa de mensagens amigáveis está em `src/lib/erros.js`.

### Guardas de integridade implementadas no banco

- **Última administradora**: não pode ser desativada nem rebaixada.
- **Turno aberto**: cuidadora com turno aberto não pode ser desativada.
- **Duplicidades**: nome ativo repetido (cuidadora/residente), medicamento
  ativo repetido (nome+dosagem por residente), horário ativo repetido
  (índice único parcial).
- **Imutabilidade clínica (DEC-026)**: por trigger — vale para QUALQUER
  caminho de escrita, não só as RPCs. `atualizar_horario` com histórico
  desativa a linha antiga e cria a nova na mesma transação (`versionado:
  true` na resposta); sem histórico edita in-place (janela de correção de
  digitação). `posologia` sempre editável.
- **Desativação, nunca exclusão** em todos os cadastros (DEC-006 estendida).

### App (React/PWA)

```
src/
├── App.jsx                        # + estado "gestao"; cabeçalho Sereníssima
├── lib/erros.js                   # NOVO — mensagens para os códigos das RPCs
└── pages/
    ├── LoginCasa.jsx              # nome completo "Residencial Senior Sereníssima"
    ├── AssumirTurno.jsx           # + fluxo "Trocar meu PIN" (DEC-025)
    ├── Ronda.jsx                  # intacta (só nota do SOS corrigida p/ Sessão #4)
    ├── Gestao.jsx                 # NOVO — porta com PIN de admin + abas
    ├── GestaoCuidadoras.jsx       # NOVO — criar/editar/PIN/desativar equipe
    └── GestaoResidentes.jsx       # NOVO — residentes → medicamentos → horários
```

- Navegação da gestão em três níveis: lista de residentes → ficha do
  residente (medicamentos) → horários do medicamento.
- Identidade Sereníssima em `index.css` (variáveis globais): dourado
  #B08D4A, dourado escuro #8F7038, creme #FAF6EE, texto #3D3428. Regra de
  contraste respeitada: dourado puro só em destaques/superfícies; botões e
  cabeçalho usam o dourado escuro (branco sobre #8F7038 ≈ 4,6:1); texto
  pequeno dourado usa a variante `--cor-primaria-texto` (#7C6132). Cores
  funcionais (vermelho/verde/âmbar) intactas.
- Manifest do PWA: name "Residencial Senior Sereníssima", short_name
  "Sereníssima", theme_color #8F7038, background #FAF6EE.
- Seed: `admin: true` na Ana Souza (`eh_admin` no insert).

## 3. Verificações executadas

| Critério | Resultado |
|---|---|
| Smoke test das 3 migrations em transação com rollback antes do apply | OK |
| Bateria SQL de 16 testes funcionais (transação + rollback): autorização (não-admin, PIN errado), criação com hash bcrypt, PIN novo funciona no `abrir_turno`, guardas (turno aberto, última admin, duplicados, nascimento futuro), versionamento de horário com histórico, triggers de imutabilidade por UPDATE direto, residente desativado some da agenda | OK — 16/16 |
| Permissões (`set role authenticated/anon`): INSERT/UPDATE diretos negados em cuidadores/idosos/medicamentos/horarios; `pin_hash` ilegível; funções internas não executáveis; RPCs de gestão executáveis pelo authenticated e negadas ao anon | OK |
| Ciclo completo no navegador (viewport 375px): entrar na gestão com PIN da Ana → criar residente → criar medicamento contínuo → horário 20:00 com dose 0,5 → criar cuidadora Elisa (PIN 5555) → guarda da última admin exibida na tela → sair da gestão → abrir turno com a Elisa → ronda → encerrar turno | OK — console sem erros |
| Efeitos no banco após o ciclo: hash bcrypt da cuidadora nova, prescrição correta, turno fechado, 13 verificações de PIN auditadas | OK |
| Security advisors | Nenhum aviso novo não-intencional (novas RPCs entram no aviso já documentado de SECURITY DEFINER — são a API do app; Leaked Password Protection segue pendente no dashboard) |
| `npm run build` | OK |
| Reset final do seed (valida `eh_admin` no seed) | OK — banco limpo |

## 4. Pendências e riscos para a Sessão #4

1. **Bootstrap da administradora real (Thais)** — o seed marca a Ana; no
   cadastro dos dados reais (Sessão #5) a primeira admin real precisa nascer
   por seed/script (a gestão exige uma admin já existente para criar outras).
2. **Sem trilha própria de auditoria de cadastros** — sabe-se QUE uma admin
   autorizou (tentativas_pin) mas não O QUE mudou. Aceitável no piloto
   (cadastros não afetam o ledger); reavaliar se virar requisito.
3. **MH-001** — `abrir_turno` duplica a lógica de PIN+rate limit que agora
   vive em `fn_verificar_pin`; unificar numa sessão futura (não foi feito
   para não tocar no fluxo estável da Sessão #2).
4. **PIN de admin em memória do cliente durante a sessão de gestão** — por
   desenho (stateless); o risco real é o mesmo do teclado (dispositivo da
   casa). Registrado na DEC-024.
5. **Versionar horário muda o `horario_id`** — o histórico antigo continua
   ligado à linha desativada (leitura fiel); relatórios da Sessão #4 devem
   agrupar por medicamento, não por horário.
6. **Sessão #4 (estoque)**: entradas de compra, ajuste de contagem e perda
   manuais + visão de saldo/cobertura + fluxo SOS. As views
   `saldo_estoque`/`cobertura_estoque` ainda não filtram residente inativo —
   decidir na Sessão #4 como exibir (provavelmente mostrar com selo, pois o
   estoque físico continua existindo).
7. **Commit** — mudanças desta sessão no working tree, sem commit
   (pós-sessão do roteiro prevê commit + push pelo Guilherme).

## 5. Como rodar / testar

```bash
npm install
npm run dev                    # http://localhost:5173
# login: casa@namicare.app / senha em .env.local (CASA_SENHA)
# PINs de teste: Ana 1111 (ADMIN), Beatriz 2222, Carlos 3333, Débora 4444

# Gestão: botão "Gestão" no cabeçalho → Ana Souza → PIN 1111
npm run seed -- --reset        # repopula dados de teste (Ana volta a ser a única admin)
```
