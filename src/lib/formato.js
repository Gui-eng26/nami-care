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

export function dataHoraLocal(iso) {
  return new Date(iso).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'America/Sao_Paulo'
  })
}
