# SESSAO_01 — Setup, schema e seed

> Roteiro da primeira sessão de implementação via Claude Code.
> Modelo recomendado: Claude Fable 5 (sessão longa e autônoma).
> Criado em: 2026-07-15

---

## Pré-requisitos (fazer ANTES de iniciar a sessão)

- [ ] Projeto Supabase criado (novo projeto, separado da Nami Life)
- [ ] Anotar: URL do projeto, anon key e service role key
- [ ] Node.js atualizado na máquina
- [ ] Claude Code aberto na raiz do repositório `nami-care`

## Prompt inicial da sessão

Copie e cole no Claude Code:

```
Leia BRIEFING.md, DECISIONS.md e CONTEXT.md na raiz deste repositório antes de
qualquer ação. Eles são a fonte de verdade do projeto.

Execute a Sessão #1 descrita abaixo. Trabalhe de forma autônoma, mas pare e me
pergunte se encontrar qualquer ambiguidade que exija decisão de produto — nesse
caso, registre a dúvida como candidata a DEC no DECISIONS.md.

ESCOPO DA SESSÃO #1:

1. SETUP DO PROJETO
   - React + Vite como PWA (manifest, service worker básico), mobile-first
   - Cliente Supabase configurado via variáveis de ambiente (.env.local,
     com .env.example versionado e .env.local no .gitignore)
   - Estrutura de pastas clara: src/pages, src/components, src/lib, supabase/migrations

2. MIGRATIONS DO SCHEMA (Postgres/Supabase)
   Criar as 7 tabelas conforme BRIEFING.md §5, incluindo:
   - medicamentos.tipo: 'continuo' | 'sos' (DEC-014)
   - administracoes.medicamento_id obrigatório + horario_id opcional (NULL = dose avulsa)
   - administracoes.status: 'tomado_no_horario' | 'tomado_atrasado' | 'nao_tomado' | 'recusado'
   - qtd_dose e quantidade como numeric, aceitando frações de 0,5 (DEC-013)
   - Soft delete: campo ativo em medicamentos e horarios (DEC-006)
   - Trigger de baixa automática de estoque (DEC-008):
     * status tomado_* → movimentação 'saida_administracao'
     * status recusado → movimentação 'perda'
     * status nao_tomado → sem movimentação
     * Constraint de unicidade em movimentacoes_estoque.administracao_id
       para impedir dupla baixa
   - View ou função de saldo: saldo por medicamento = SUM(movimentações)
   - View de cobertura: saldo / consumo médio diário (últimos 14 dias),
     para o alerta de reposição < 5 dias (DEC-012)

3. ROW LEVEL SECURITY
   - RLS habilitado em todas as tabelas
   - Política simples para o MVP: qualquer cuidador autenticado lê e escreve
     (DEC-011 — sem perfil admin), anônimos sem acesso

4. SEED DE DADOS DE TESTE
   - Script Node.js em scripts/seed.js, usando a service role key via variável
     de ambiente (DEC-015 — linguagem única JS)
   - 4 cuidadores fictícios (com PIN de teste)
   - 11 idosos fictícios
   - ~25 medicamentos distribuídos entre eles (mix de contínuos e 2-3 SOS),
     com horários que colidem de propósito entre idosos (para testar a rodada)
   - Estoque inicial via movimentações 'entrada_compra'
   - IMPORTANTE: nomes fictícios, nenhum dado real (LGPD — BRIEFING.md §9)

5. ENCERRAMENTO DA SESSÃO
   - Atualizar CONTEXT.md: marcar Sessão #1 como concluída, listar o que foi
     feito e apontar a Sessão #2 como próxima
   - Registrar no DECISIONS.md qualquer decisão técnica tomada durante a sessão
   - Gerar RELATORIO_SESSAO_01.md com: resumo do que foi feito, estrutura criada,
     como rodar o projeto localmente, e pendências/observações

FORA DO ESCOPO DESTA SESSÃO (não implementar):
- Telas além de um esqueleto mínimo de app rodando
- Autenticação por PIN (Sessão #2)
- Lógica de rodada, fechamento de turno e relatórios (Sessões #3 e #4)
```

## Critérios de aceite da sessão

- [ ] `npm run dev` sobe o app sem erros
- [ ] Migrations aplicam limpas em um projeto Supabase zerado
- [ ] Trigger testado: inserir administração 'tomado_no_horario' gera movimentação
      de saída; 'nao_tomado' não gera; dupla inserção da mesma administração falha
- [ ] Saldo da view bate com a soma manual das movimentações do seed
- [ ] RLS bloqueia acesso anônimo
- [ ] CONTEXT.md atualizado e RELATORIO_SESSAO_01.md gerado

## Pós-sessão (Guilherme)

- [ ] Revisar RELATORIO_SESSAO_01.md
- [ ] Salvar relatório no Google Drive (pasta de relatórios de sessão, padrão Nami)
- [ ] Commit + push
- [ ] Testar os critérios de aceite manualmente antes de iniciar a Sessão #2