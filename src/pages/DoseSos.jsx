import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase.js'
import { fmtQtd } from '../lib/formato.js'

// Dose avulsa SOS/PRN (DEC-014): residente → medicamento SOS → quantidade →
// confirmar. O registro é um INSERT em administracoes com horario_id nulo —
// o mesmo caminho da ronda: o trigger da DEC-008 faz a baixa de estoque
// (nenhuma lógica paralela) e o trigger de turno exige o cuidador do turno
// aberto. Só medicamentos com a flag SOS aparecem aqui.
export default function DoseSos({ turno, onFechar, onRegistrada }) {
  const [itens, setItens] = useState(null)
  const [residenteId, setResidenteId] = useState(null)
  const [medicamento, setMedicamento] = useState(null)
  const [qtd, setQtd] = useState('1')
  const [observacao, setObservacao] = useState('')
  const [erro, setErro] = useState(null)
  const [salvando, setSalvando] = useState(false)

  useEffect(() => {
    // A view de estoque já tem tudo: só SOS ativos de residentes ativos,
    // com o saldo atual para a cuidadora ver antes de dar a dose.
    supabase
      .from('cobertura_estoque')
      .select('medicamento_id, idoso_id, nome_idoso, nome, dosagem, forma_farmaceutica, saldo')
      .eq('tipo', 'sos')
      .eq('ativo', true)
      .eq('idoso_ativo', true)
      .order('nome_idoso')
      .order('nome')
      .then(({ data, error }) => setItens(error ? [] : data))
  }, [])

  const residentes = useMemo(() => {
    if (!itens) return []
    const vistos = new Map()
    for (const item of itens) {
      if (!vistos.has(item.idoso_id)) vistos.set(item.idoso_id, item.nome_idoso)
    }
    return [...vistos.entries()].map(([id, nome]) => ({ id, nome }))
  }, [itens])

  async function registrar() {
    setSalvando(true)
    setErro(null)
    const { error } = await supabase.from('administracoes').insert({
      medicamento_id: medicamento.medicamento_id,
      cuidador_id: turno.cuidador_id,
      qtd: Number(qtd),
      status: 'tomado_no_horario',
      observacao: observacao.trim() || null
    })
    setSalvando(false)
    if (error) {
      setErro('Não foi possível registrar a dose. Tente novamente.')
      return
    }
    onRegistrada(
      `Dose SOS registrada: ${medicamento.nome} ${medicamento.dosagem || ''} para ${medicamento.nome_idoso}.`
    )
  }

  return (
    <div className="modal-fundo" onClick={onFechar}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>Dose avulsa (SOS)</h3>

        {itens === null && <span className="status status-carregando">Carregando…</span>}

        {itens !== null && itens.length === 0 && (
          <>
            <p className="modal-medicamento">
              Nenhum medicamento SOS cadastrado. O cadastro (com a flag SOS) é feito
              na área de gestão.
            </p>
            <div className="modal-acoes">
              <button type="button" className="botao-secundario" onClick={onFechar}>
                Fechar
              </button>
            </div>
          </>
        )}

        {itens !== null && itens.length > 0 && !residenteId && (
          <>
            <p className="modal-medicamento">Para quem é a dose?</p>
            <div className="opcoes-tratativa">
              {residentes.map((r) => (
                <button
                  key={r.id}
                  type="button"
                  className="opcao"
                  onClick={() => setResidenteId(r.id)}
                >
                  {r.nome}
                </button>
              ))}
            </div>
            <div className="modal-acoes">
              <button type="button" className="botao-secundario" onClick={onFechar}>
                Cancelar
              </button>
            </div>
          </>
        )}

        {residenteId && !medicamento && (
          <>
            <p className="modal-medicamento">Qual medicamento SOS?</p>
            <div className="opcoes-tratativa">
              {itens
                .filter((i) => i.idoso_id === residenteId)
                .map((i) => (
                  <button
                    key={i.medicamento_id}
                    type="button"
                    className="opcao"
                    onClick={() => setMedicamento(i)}
                  >
                    {i.nome} {i.dosagem}
                    <span className="item-gestao-detalhe">
                      {' '}
                      — estoque: {fmtQtd(i.saldo)} {i.forma_farmaceutica || 'unidade(s)'}
                    </span>
                  </button>
                ))}
            </div>
            <div className="modal-acoes">
              <button
                type="button"
                className="botao-secundario"
                onClick={() => setResidenteId(null)}
              >
                ‹ Voltar
              </button>
            </div>
          </>
        )}

        {medicamento && (
          <>
            <p className="modal-medicamento">
              <strong>{medicamento.nome_idoso}</strong> — {medicamento.nome}{' '}
              {medicamento.dosagem} (estoque: {fmtQtd(medicamento.saldo)})
            </p>
            <div className="formulario">
              <label>
                Quantidade (passos de 0,5)
                <input
                  type="number"
                  min="0.5"
                  step="0.5"
                  inputMode="decimal"
                  value={qtd}
                  onChange={(e) => setQtd(e.target.value)}
                />
              </label>
              <label>
                Observação (opcional)
                <textarea
                  rows={2}
                  placeholder="ex.: queixa de dor de cabeça"
                  value={observacao}
                  onChange={(e) => setObservacao(e.target.value)}
                />
              </label>
            </div>
            {erro && <p className="aviso aviso-erro">{erro}</p>}
            <div className="modal-acoes">
              <button
                type="button"
                className="botao-secundario"
                onClick={() => setMedicamento(null)}
                disabled={salvando}
              >
                ‹ Voltar
              </button>
              <button
                type="button"
                className="botao-primario"
                onClick={registrar}
                disabled={salvando || !qtd || Number(qtd) <= 0}
              >
                {salvando ? 'Registrando…' : 'Registrar dose'}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
