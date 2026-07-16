# CONTEXT — Nami Care

> Estado atual do projeto para continuidade entre sessões (Claude.ai e Claude Code).
> Última atualização: 2026-07-15

## Onde estamos

**Fase atual:** Fase 2 — Documentação de projeto (CONCLUÍDA nesta sessão)
- [x] Decisão de interface (PWA, celular compartilhado da casa)
- [x] Modelo de dados desenhado (7 tabelas — ver BRIEFING.md §5)
- [x] Conceitos centrais definidos (rodada de medicação, ledger de estoque, turno)
- [x] BRIEFING.md v1.2 e DECISIONS.md (DEC-001 a DEC-014) criados
- [x] Regras de negócio 100% definidas (recusa, janela 30 min, fechamento de turno,
      permissões, ponto de reposição < 5 dias, doses fracionadas 0,5, dose avulsa SOS)

**Próxima fase:** Fase 3 — Implementação via Claude Code

## Próximos passos (ordem sugerida)

1. **Guilherme:** revisão final do BRIEFING.md v1.2 e DECISIONS.md
3. Criar repositório `nami-care` no GitHub
4. Copiar BRIEFING.md, DECISIONS.md e CONTEXT.md para a raiz do repositório
5. **Sessão Claude Code #1 (candidata a Fable 5, sessão longa):**
   - Setup do projeto React PWA + Supabase
   - Migrations do schema completo (7 tabelas + RLS + trigger de baixa automática,
     conforme DEC-008)
   - Seed de dados de teste (4 cuidadores, 11 idosos fictícios)
6. **Sessão Claude Code #2:** telas de cadastro (idosos, medicamentos, horários)
7. **Sessão Claude Code #3:** rodada de medicação + confirmações + baixa de estoque
8. **Sessão Claude Code #4:** relatórios (adesão, estoque, previsão de ruptura)
9. Preparar termo LGPD com a casa de repouso ANTES de inserir dados reais
10. Piloto assistido: 1ª semana com acompanhamento próximo dos 4 cuidadores

## Convenções deste projeto

- Documentação segue o padrão Nami Life: BRIEFING.md (o quê e por quê),
  DECISIONS.md (decisões com racional), CONTEXT.md (estado e próximos passos)
- Bugs: numerar como BUG-001+; melhorias como MH-001+ (padrão Nami)
- Relatórios de sessão: salvar no Google Drive, mesma estrutura usada na Nami
- Idioma da documentação: português; código e nomes de tabelas/colunas: português
  sem acentos (ex.: `movimentacoes_estoque`)

## Vínculo com a Nami Life

Projeto independente em código e banco, mas estrategicamente ligado: valida a
hipótese "casas de repouso como segmento B2B". Aprendizados de posologia, formas
farmacêuticas e estoque da Nami se aplicam diretamente. NÃO compartilhar banco de
dados nem repositório com a Nami Life.