// Formatação compartilhada das telas de estoque (quantidades em passos de 0,5).

export function fmtQtd(n) {
  const v = Number(n)
  return Number.isInteger(v) ? String(v) : v.toLocaleString('pt-BR')
}

// Rótulo por SUBTIPO do extrato (DEC-036): o ajuste de contagem é entrada ou
// saída conforme o sinal da quantidade — a distinção mora aqui, não no tipo.
// Desde a DEC-049 é o ÚNICO rótulo de movimentação do app: a ficha do estoque e
// a aba de extrato leem o mesmo `subtipo` da mesma RPC. O antigo
// `ROTULO_MOVIMENTACAO`, que rotulava por `tipo` e dizia "Ajuste de contagem"
// onde esta tabela diz "(a menos)", foi removido junto com o caminho que o usava.
export const ROTULO_SUBTIPO = {
  compra: 'Compra',
  dose: 'Dose administrada',
  ajuste_mais: 'Ajuste de contagem (a mais)',
  ajuste_menos: 'Ajuste de contagem (a menos)',
  perda: 'Perda'
}

export function dataHoraLocal(iso) {
  return new Date(iso).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'America/Sao_Paulo'
  })
}

// Só a hora ('08:00'), para o par previsto × registrado do extrato de adesão
// (DEC-048), onde o dia já vem dito na primeira metade da linha.
export function horaLocal(iso) {
  if (!iso) return ''
  return new Date(iso).toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'America/Sao_Paulo'
  })
}

// Data sem hora ('yyyy-mm-dd' → 'dd/mm/aaaa'). Formata a string direto, sem
// passar por Date, para a validade (um DATE) não deslizar de fuso.
export function dataLocal(iso) {
  if (!iso) return ''
  const [y, m, d] = String(iso).slice(0, 10).split('-')
  return `${d}/${m}/${y}`
}

// Rótulo curto de um lote para a cuidadora (sem jargão). Lote sem código vira
// "lote não identificado" (DEC-041).
export function rotuloLote(lote) {
  return lote || 'lote não identificado'
}

// Resumo dos lotes de UMA movimentação do extrato (DEC-043): a entrada mostra o
// lote que criou; a saída, de qual(is) lote(s) saiu, com a quantidade de cada.
export function resumoLotesMov(lotes) {
  if (!lotes || lotes.length === 0) return null
  return lotes
    .map((l) => `${fmtQtd(Math.abs(Number(l.quantidade)))} de ${rotuloLote(l.lote)} (venc. ${dataLocal(l.validade)})`)
    .join(' · ')
}
