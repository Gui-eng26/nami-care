// Recorrência de horário (DEC-055): mesma regra do banco (doses_do_turno,
// Parte 3), em JS — só para a PRÉVIA de conferência do cadastro (Parte 6).
// Não é fonte de verdade; o banco decide de fato quais doses a ronda gera.

function paraDataUTC(valor) {
  if (valor instanceof Date) {
    return new Date(Date.UTC(valor.getFullYear(), valor.getMonth(), valor.getDate()))
  }
  const [y, m, d] = String(valor).slice(0, 10).split('-').map(Number)
  return new Date(Date.UTC(y, m - 1, d))
}

// ISO: segunda=1 ... domingo=7 (mesma convenção do banco).
function isoDow(dataUTC) {
  const dow = dataUTC.getUTCDay()
  return dow === 0 ? 7 : dow
}

function diffDias(a, b) {
  return Math.round((a.getTime() - b.getTime()) / 86400000)
}

// Os próximos `n` dias (hoje incluso).
export function proximosDias(n, hoje = new Date()) {
  const inicio = paraDataUTC(hoje)
  return Array.from({ length: n }, (_, i) => new Date(inicio.getTime() + i * 86400000))
}

// true se ESTE horário dispara no dia informado — espelha o WHERE de
// doses_do_turno. Aceita tanto os nomes de coluna do banco (snake_case)
// quanto os do estado do formulário (camelCase).
export function geraDoseNoDia(horario, dataUTC) {
  const tipo = horario.recorrenciaTipo ?? horario.recorrencia_tipo ?? 'diario'
  if (tipo === 'diario') return true
  if (tipo === 'dias_semana') {
    const dias = horario.diasSemana ?? horario.dias_semana ?? []
    return dias.includes(isoDow(dataUTC))
  }
  if (tipo === 'intervalo') {
    const ref = horario.dataReferencia ?? horario.data_referencia
    const intervalo = Number(horario.intervaloDias ?? horario.intervalo_dias)
    if (!ref || !(intervalo > 1)) return false
    const diff = diffDias(dataUTC, paraDataUTC(ref))
    return diff >= 0 && diff % intervalo === 0
  }
  return false
}

export function fmtDiaCurto(dataUTC) {
  return dataUTC.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', timeZone: 'UTC' })
}

export const DIAS_SEMANA = [
  { valor: 1, curto: 'Seg' },
  { valor: 2, curto: 'Ter' },
  { valor: 3, curto: 'Qua' },
  { valor: 4, curto: 'Qui' },
  { valor: 5, curto: 'Sex' },
  { valor: 6, curto: 'Sáb' },
  { valor: 7, curto: 'Dom' }
]

export function fmtDiaSemanaCurto(dataUTC) {
  return DIAS_SEMANA[isoDow(dataUTC) - 1].curto
}
