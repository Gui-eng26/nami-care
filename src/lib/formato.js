// Formatação compartilhada das telas de estoque (quantidades em passos de 0,5).

export function fmtQtd(n) {
  const v = Number(n)
  return Number.isInteger(v) ? String(v) : v.toLocaleString('pt-BR')
}

export const ROTULO_MOVIMENTACAO = {
  entrada_compra: 'Compra',
  saida_administracao: 'Dose administrada',
  ajuste_contagem: 'Ajuste de contagem',
  perda: 'Perda'
}

// Rótulo por SUBTIPO do extrato (DEC-036): o ajuste de contagem é entrada ou
// saída conforme o sinal da quantidade — a distinção mora aqui, não no tipo.
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
