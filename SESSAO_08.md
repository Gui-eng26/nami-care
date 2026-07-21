# SESSÃO 8 — Acesso da operação e usabilidade do cadastro

> Roteiro de entrada. Primeira sessão pós-MVP: ajustes de acesso e usabilidade
> a partir do teste real no dispositivo, antes de trazer a Thais.
> Data: 2026-07-21 | Anterior: `SESSAO_07.md` / `RELATORIO_SESSAO_07.md`

---

## Antes de começar

1. Fonte da verdade: `BRIEFING.md`, `DECISIONS.md` (DEC-001 a DEC-037 na
   abertura), `CONTEXT.md`, `ROADMAP.md`, `RELATORIO_SESSAO_07.md`.
2. Banco: exclusivamente o projeto `nami-care` (ref `uvkmvaheupziexlunnno`).
3. O go-live operacional (Railway, limpeza do banco, dados reais) do runbook da
   Sessão 7 **ainda não foi executado** — o banco continua com o seed de teste.
   Esta sessão trabalha sobre o seed; não executa `limpar-banco` nem toca no
   runbook de go-live.
4. Sessão COM decisão de produto nova e mudança de comportamento, incluindo a
   inversão de uma decisão aprovada — registrar como **DEC-038**.

## Contexto e objetivo

O Guilherme instalou o PWA no próprio celular e testou o fluxo antes de levar à
Thais. Três achados de uso e um de acesso motivam esta sessão. O tema comum é
**tirar travas que atrapalham a operação diária da cuidadora** e **encurtar o
caminho do cadastro de medicamento**, sem perder auditoria nem integridade
clínica.

Quatro entregas. A Parte 1 é a mais profunda (mexe em segurança de RPC e inverte
uma decisão); as outras três são de tela e de composição de RPCs que já existem.

---

## Parte 1 — Gestão de residentes aberta a todas as cuidadoras (DEC-038)

**O problema.** A DEC-024 exige PIN de administradora para TODA gestão de
residentes, medicamentos e prescrições. O teste real expôs que essa trava não
protege o histórico clínico — ela o corrompe: a residente volta da consulta com
prescrição nova, a cuidadora do turno (não-admin, porque a admin não fica na
casa 24/7) aplica a mudança no mundo real de qualquer forma, mas não consegue
registrá-la. A mudança acontece fora do app e a trilha de auditoria some.

**Decisão (já tomada — implementar e documentar como DEC-038):**

- Gestão de residentes passa a ser autorizada **por turno** (`fn_cuidador_do_turno`),
  não por PIN de admin: ver residentes, editar cadastro e observações, cadastrar
  medicamento e **editar prescrição** ficam abertos a qualquer cuidadora com
  turno aberto.
- **A DEC-026 permanece intacta e é o que torna isso seguro:** mudança de
  dose/horário de medicamento em uso versiona (desativa a antiga, cria a nova).
  A auditoria melhora — a ação passa a ficar atribuída à cuidadora do turno.
- **Gestão de EQUIPE continua exclusiva de administradora** (DEC-024 preservada
  nesse escopo): é administração de quem tem acesso ao sistema, não ato de
  cuidado.

**Escopo — banco.** Reescrever as nove RPCs (`criar_residente`,
`atualizar_residente`, `definir_ativo_residente`, `criar_medicamento`,
`atualizar_medicamento`, `definir_ativo_medicamento`, `criar_horario`,
`atualizar_horario`, `definir_ativo_horario`) para autorizar por turno aberto;
assinaturas mudam (drop + recreate), erro novo `sem_turno_aberto`, toda a
validação de negócio preservada. RPCs de equipe **não mudam**.

**Escopo — cliente.** Gestão de residentes sem tela de PIN; equipe mantém a
sua; `eh_admin` carregado junto com o turno apenas para decidir a UI.

## Parte 2 — Estoque inicial no cadastro de medicamento

Passo opcional no cadastro, com escolha da origem: **compra** →
`registrar_entrada_estoque` (`entrada_compra`); **remanescente** →
`registrar_ajuste_estoque` (`ajuste_contagem`). Encadear as RPCs existentes após
`criar_medicamento`; campo em branco = medicamento nasce sem movimentação. Sem
mudança de schema.

## Parte 3 — Atalho "+ Medicamento" dentro da aba Estoque

Botão no topo do conteúdo da aba Estoque, com seletor de residente + o mesmo
cadastro (catálogo da DEC-035) + o estoque inicial da Parte 2. Mesma
`criar_medicamento`, só um ponto de entrada mais curto. "Medicamento da casa"
(SOS sem residente) fica **postergado**.

## Parte 4 — Reorganização visual da home (pós-turno)

- Nome da cuidadora sai do header e vai abaixo do bloco de título, como texto.
- "Gestão" único vira **"Gestão residentes"** (todas) e **"Gestão equipe"**
  (só admin, ainda com PIN).
- "Pendências entre turnos" sai da faixa de abas e vira **faixa de alerta** que
  só aparece com pendência.
- Faixa de abas passa a ser **Ronda, Adesão, Estoque**.

---

## Restrições

- JavaScript apenas; toda mudança de RPC via migration, nunca SQL avulso.
- Esconder botão no cliente nunca é segurança — o enforcement é da RPC.
- Não tocar no runbook de go-live nem no banco de produção; seed permanece.
- DEC-026 e o ledger de estoque (DEC-004/016) permanecem intocados.
- PIN real nunca em texto no repo, relatório ou log.

## Critério de pronto

1. Cuidadora não-admin com turno aberto: abre "Gestão residentes", cadastra
   medicamento e edita prescrição sem PIN; "Gestão equipe" não aparece.
2. Editar dose de medicamento já administrado versiona (DEC-026).
3. Admin vê os dois botões; "Gestão equipe" ainda pede PIN.
4. RPC de residentes sem turno aberto retorna `sem_turno_aberto`.
5. RPC de equipe sem PIN de admin continua barrada no banco.
6. Atalho "+ Medicamento" com estoque inicial nas duas origens, visível no
   extrato.
7. Mesmo resultado pelo caminho de Residentes.
8. Home reorganizada conforme a Parte 4.
9. `npm run build` sem erro; sem regressão; advisors sem novidade não explicada.
