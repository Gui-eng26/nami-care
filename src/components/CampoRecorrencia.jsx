import { DIAS_SEMANA } from '../lib/recorrencia.js'

// Sub-formulário de recorrência (DEC-055), extraído do FormHorario na Sessão
// #17 (BUG-013) para ser reutilizado também no cadastro de horários dentro do
// FormMedicamento — sem isso as duas telas divergiriam na primeira alteração.
// Componente controlado: recebe e devolve o estado, não fala com o banco.
export default function CampoRecorrencia({
  recorrenciaTipo,
  onChangeRecorrenciaTipo,
  diasSemana,
  onChangeDiasSemana,
  intervaloDias,
  onChangeIntervaloDias,
  dataReferencia,
  onChangeDataReferencia
}) {
  // Chama onChangeDiasSemana com uma função atualizadora (não o array já
  // calculado): dois toques em botões diferentes disparam dois cliques no
  // mesmo lote do React antes de qualquer re-render, então calcular a partir
  // do `diasSemana` capturado no fechamento perderia o primeiro toque — cada
  // chamador precisa resolver a função contra o estado mais recente (ex.:
  // `setDiasSemana` do React já faz isso nativamente).
  function alternarDiaSemana(valor) {
    onChangeDiasSemana((atual) =>
      (atual ?? []).includes(valor) ? atual.filter((v) => v !== valor) : [...atual, valor].sort()
    )
  }

  return (
    <>
      <label>
        Repetição
        <select value={recorrenciaTipo} onChange={(e) => onChangeRecorrenciaTipo(e.target.value)}>
          <option value="diario">Todo dia</option>
          <option value="dias_semana">Dias da semana</option>
          <option value="intervalo">A cada N dias</option>
        </select>
      </label>

      {recorrenciaTipo === 'dias_semana' && (
        <div className="dias-semana-selecao">
          {DIAS_SEMANA.map((d) => (
            <button
              key={d.valor}
              type="button"
              className={`dia-semana-opcao ${diasSemana.includes(d.valor) ? 'dia-semana-ativo' : ''}`}
              onClick={() => alternarDiaSemana(d.valor)}
            >
              {d.curto}
            </button>
          ))}
        </div>
      )}

      {recorrenciaTipo === 'intervalo' && (
        <div className="formulario-linha">
          <label>
            A cada quantos dias
            <input
              type="number"
              min="2"
              step="1"
              inputMode="numeric"
              value={intervaloDias}
              onChange={(e) => onChangeIntervaloDias(e.target.value)}
              required
            />
          </label>
          <label>
            A partir de
            <input
              type="date"
              value={dataReferencia}
              onChange={(e) => onChangeDataReferencia(e.target.value)}
              required
            />
          </label>
        </div>
      )}
    </>
  )
}

// Mesmas validações que viviam no `submeter` do FormHorario: modo
// `dias_semana` exige ao menos um dia marcado, modo `intervalo` exige
// `intervalo_dias > 1`. Extraída para ser aplicada por cartão no
// FormMedicamento (Sessão #17), não só uma vez no FormHorario.
export function erroRecorrencia({ recorrenciaTipo, diasSemana, intervaloDias }) {
  if (recorrenciaTipo === 'dias_semana' && (!diasSemana || diasSemana.length === 0)) {
    return 'Selecione ao menos um dia da semana.'
  }
  if (recorrenciaTipo === 'intervalo' && !(Number(intervaloDias) > 1)) {
    return 'O intervalo deve ser maior que 1 dia.'
  }
  return null
}
