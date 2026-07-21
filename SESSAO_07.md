# SESSÃO 7 — Deploy e go-live

> Roteiro de entrada da última sessão do MVP planejado no ROADMAP.
> Data: 2026-07-21 | Anterior: `SESSAO_06.md` / `RELATORIO_SESSAO_06.md`

---

## Antes de começar

1. Fonte da verdade: `BRIEFING.md`, `DECISIONS.md` (DEC-001 a DEC-036 na
   abertura), `CONTEXT.md`, `ROADMAP.md`, `RELATORIO_SESSAO_06.md`.
2. Banco: exclusivamente o projeto `nami-care` (ref `uvkmvaheupziexlunnno`).
3. Sessão de **execução operacional e de infraestrutura** sobre o que as
   Sessões 1–6 construíram. Nenhuma decisão de produto nova prevista; se
   surgir escolha estrutural inevitável, registrar como DEC-037+.

## Contexto e objetivo

O produto está completo (a Sessão 6 fechou catálogo de medicamentos e extrato
de movimentação). Falta tirar o app do ambiente de desenvolvimento e colocar a
casa operando nele de verdade, substituindo a planilha e a contagem manual
semanal — a dor nº 1 da cliente (BRIEFING §1).

**Critério de sucesso:** o critério de pronto do ROADMAP para o MVP — a casa
operando no app, sem planilha e sem contagem manual.

## Quatro entregas, nesta ordem

### Parte 1 — Deploy do frontend (Railway)

Infra já decidida (DEC-007): Railway, sem introduzir Vercel ou outra
plataforma.

- `npm run build` de produção limpo antes de qualquer publish.
- Serviço no Railway servindo o conteúdo estático de `dist/`; comandos de build
  e de serve adequados a site estático — **não** deixar o dev server do Vite
  rodando em produção.
- Variáveis de ambiente de produção: apenas as `VITE_*` do cliente
  (`VITE_SUPABASE_URL`, anon key). `SUPABASE_SERVICE_ROLE_KEY` e credenciais
  `CASA_*` nunca em variável exposta ao cliente nem no serviço de frontend.
- Confirmar que o build do PWA (`vite-plugin-pwa`, `registerType: 'autoUpdate'`)
  gera manifest e service worker servidos pela URL pública, sem 404.

**Pronto quando:** URL pública serve o app; a tela de login abre sem erro de
console; `npm run build` local sem erro imediatamente antes do deploy.

### Parte 2 — Supabase Auth em produção

- Adicionar a URL de produção ao Site URL e às Redirect URLs, mantendo
  `localhost` durante a transição.
- Confirmar que o usuário único da casa (`casa@namicare.app`, DEC-019)
  autentica a partir da URL de produção.
- Revisar os security advisors uma última vez antes do go-live.

**Pronto quando:** login funciona da URL de produção, sem erro de
redirect/CORS; advisors sem aviso novo não explicado.

### Parte 3 — PWA instalável no celular da casa

O manifest apontava só para ícones SVG. Para instalação limpa como app na tela
inicial (Android/Chrome) o PWA precisa de PNGs rasterizados 192×192 e 512×512.

- Base: o logo real da casa em `public/icons/logo-serenissima.png`.
  Recomendação: usar o **símbolo isolado** (casinha com o casal e o coração)
  nos ícones — a 192px o texto do logo horizontal fica ilegível. O logo
  horizontal completo continua servindo para cabeçalho/tela de login.
- Gerar 192×192 e 512×512, incluindo a variante maskable.
- Atualizar o `manifest` no `vite.config.js` (`sizes`, `type: image/png`,
  `purpose` any e maskable), mantendo `name`, `short_name: "Sereníssima"`,
  `background_color`, `theme_color`, `display`, `orientation`.
- Rebuild e conferir no navegador (Application/Manifest) que não há warning de
  instalabilidade e que os ícones carregam pela URL de produção.

Fora do escopo: a instalação física no celular da casa ("adicionar à tela
inicial") é feita pelo Guilherme/Thais fora da sessão.

**Pronto quando:** manifest válido, sem warning de instalabilidade, com ícones
PNG 192/512 servidos pela URL de produção.

### Parte 4 — Cadastro dos dados reais

**LGPD:** resolvido, não bloqueante.

**Bootstrap:** a gestão exige uma administradora já existente (DEC-024) — toda
RPC de gestão valida o PIN de uma admin no banco. Em banco de produção limpo
não há ninguém; a PRIMEIRA admin nasce fora do fluxo normal.

- Script/seed mínimo e reprodutível que cria a Thais com `eh_admin = true` e o
  PIN definido por ela — hash gerado no banco, nunca PIN em texto no repositório
  ou no relatório. Este é o único cadastro fora do app.
- Demais cadastros pela tela de gestão, logada como Thais: as outras 3
  cuidadoras, os 11 residentes e as prescrições. Sem SQL direto.
- Medicamentos SEMPRE pelo catálogo (DEC-035): o primeiro cadastro de cada
  remédio cria o item; residentes seguintes REAPROVEITAM por busca/seleção.
- Estoque inicial = última contagem manual, lançado como movimentação de
  entrada no ledger (DEC-004/016) com a data real da contagem — nunca saldo
  sobrescrito. `entrada_compra` ou `ajuste_contagem` conforme a natureza do dado.
- Isolamento: os dados fictícios do seed NÃO podem conviver com os reais no
  banco de produção. Limpar antes de os dados reais entrarem.

**Pronto quando:** (1) Thais logada como admin real com PIN próprio;
(2) 4 cuidadoras, 11 residentes e prescrições cadastrados pelo app, com remédio
compartilhado reaproveitando o mesmo `catalogo_id`; (3) estoque inicial
auditável no extrato de movimentações; (4) nenhum dado de seed no banco.

## Restrições

- JavaScript apenas (Vite + PWA); Supabase; mudança de schema só via migration
  (nenhuma esperada).
- NENHUMA tela, RPC, trigger, view ou fluxo das Sessões 1–6 muda: Ronda, turno,
  Pendências entre turnos, Adesão, Estoque (atual e extrato), gestão e catálogo
  ficam INTOCADOS em comportamento.
- `SUPABASE_SERVICE_ROLE_KEY` e `CASA_*` nunca em frontend ou serviço público.
- PIN real nunca em texto no repo, relatório ou log; hash sempre no banco
  (DEC-020).
- Tema Sereníssima preservado; nenhuma regressão visual.

## Fora do escopo

- Qualquer funcionalidade nova de produto — o MVP está fechado.
- Painel remoto, notificações push, multi-casa, exportação para
  família/vigilância: backlog pós-piloto.
- Bloqueio por inatividade (repedir PIN — DEC-002): reavaliar depois do piloto.
- Custo/valor monetário por movimentação (não há campo de preço no schema).
- Logo definitivo refinado do PWA: o logo atual serve por enquanto.

## Encerramento

- Checklist de deploy conferido de ponta a ponta.
- Cadastro real conferido NO NAVEGADOR, não só no banco.
- `npm run build` final sem erro; revisão dos security advisors.
- `RELATORIO_SESSAO_07.md` no padrão das sessões anteriores, com a URL de
  produção, pendências e as instruções operacionais de instalação no celular.
- `CONTEXT.md` e `ROADMAP.md` atualizados.
- Alinhar o formato do acompanhamento assistido da 1ª semana com a Thais.
