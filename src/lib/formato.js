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
