import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase.js'
import { mensagemErro } from '../lib/erros.js'
import { fmtQtd, fmtForma } from '../lib/formato.js'

// Dose avulsa SOS/PRN — reestruturada na Sessão #12 (DEC-047).
//
// A ordem foi invertida: primeiro QUEM TOMA, depois QUAL MEDICAMENTO. Antes a
// lista nascia do estoque SOS por residente, então só aparecia quem já tinha um
// SOS próprio cadastrado — e não havia como dar um SOS da casa a um residente
// qualquer.
//
// Passo 1: todos os residentes ATIVOS, exceto o "Da Casa" (DEC-044). É aqui, e
//   só aqui, que o sentinela é escondido — por simplesmente não entrar na lista.
// Passo 2: os SOS ativos DAQUELE residente + os SOS DA CASA, numa lista só. Os
//   dois coexistem: a Maria pode ter o SOS particular dela e também tomar da
//   caixa comum.
// Passo 3: quantidade (meio-em-meio) e o registro.
//
// O registro passa pela RPC `registrar_dose_sos` e não mais por INSERT direto:
// a regra do dono da dose (DEC-045 — medicamento da casa exige quem tomou,
// medicamento de residente exige que fique nulo) é do banco, não da tela. A
// baixa de estoque continua sendo o trigger da DEC-008 com FEFO (DEC-042).
export default function DoseSos({ onFechar, onRegistrada }) {
  const [residentes, setResidentes] = useState(null)
  const [itens, setItens] = useState(null)
  const [residente, setResidente] = useState(null)
  const [medicamento, setMedicamento] = useState(null)
  const [qtd, setQtd] = useState('1')
  const [observacao, setObservacao] = useState('')
  const [erro, setErro] = useState(null)
  const [salvando, setSalvando] = useState(false)

  useEffect(() => {
    // Quem toma: residentes ativos, sem o "Da Casa". Independe de ter estoque —
    // é justamente o ponto: qualquer residente pode tomar um SOS da casa.
    supabase
      .from('idosos')
      .select('id, nome')
      .eq('ativo', true)
      .eq('eh_sentinela', false)
      .order('nome')
      .then(({ data, error }) => setResidentes(error ? [] : data))

    // O que há para dar: SOS ativos, com saldo — dos residentes e da casa.
    supabase
      .from('cobertura_estoque')
      .select('medicamento_id, idoso_id, nome_idoso, nome, dosagem, forma_farmaceutica, saldo, idoso_da_casa')
      .eq('tipo', 'sos')
      .eq('ativo', true)
      .eq('idoso_ativo', true)
      .order('nome')
      .then(({ data, error }) => setItens(error ? [] : data))
  }, [])

  // Do residente escolhido + da casa, nessa ordem: o particular dele primeiro,
  // a caixa comum depois.
  const opcoes = useMemo(() => {
    if (!itens || !residente) return []
    const proprios = itens.filter((i) => i.idoso_id === residente.id)
    const daCasa = itens.filter((i) => i.idoso_da_casa)
    return [...proprios, ...daCasa]
  }, [itens, residente])

  async function registrar() {
    setSalvando(true)
    setErro(null)
    const { data, error } = await supabase.rpc('registrar_dose_sos', {
      p_medicamento_id: medicamento.medicamento_id,
      p_idoso_id: residente.id,
      p_qtd: Number(qtd),
      p_observacao: observacao.trim() || null
    })
    setSalvando(false)
    if (error) {
      setErro('Falha de conexão. Tente novamente.')
      return
    }
    if (!data.ok) {
      setErro(mensagemErro(data))
      return
    }
    onRegistrada(
      `Dose SOS registrada: ${medicamento.nome} ${medicamento.dosagem || ''} para ${residente.nome}${
        data.da_casa ? ' (estoque da casa)' : ''
      }.`
    )
  }

  const carregando = residentes === null || itens === null

  return (
    <div className="modal-fundo" onClick={onFechar}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>Dose avulsa (SOS)</h3>

        {carregando && <span className="status status-carregando">Carregando…</span>}

        {!carregando && residentes.length === 0 && (
          <>
            <p className="modal-medicamento">
              Nenhum residente ativo cadastrado.
            </p>
            <div className="modal-acoes">
              <button type="button" className="botao-secundario" onClick={onFechar}>
                Fechar
              </button>
            </div>
          </>
        )}

        {!carregando && residentes.length > 0 && !residente && (
          <>
            <p className="modal-medicamento">Para quem é a dose?</p>
            <div className="opcoes-tratativa">
              {residentes.map((r) => (
                <button
                  key={r.id}
                  type="button"
                  className="opcao"
                  onClick={() => setResidente(r)}
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

        {residente && !medicamento && (
          <>
            <p className="modal-medicamento">
              Qual medicamento SOS para <strong>{residente.nome}</strong>?
            </p>
            {opcoes.length === 0 ? (
              <p className="card-sos">
                Nenhum medicamento SOS disponível — nem dela, nem da casa. O
                cadastro é feito em “+ Medicamento”, na aba Estoque.
              </p>
            ) : (
              <div className="opcoes-tratativa">
                {opcoes.map((i) => (
                  <button
                    key={i.medicamento_id}
                    type="button"
                    className="opcao"
                    onClick={() => setMedicamento(i)}
                  >
                    {i.nome} {i.dosagem}
                    {i.idoso_da_casa && <span className="chip chip-casa"> Da casa</span>}
                    <span className="item-gestao-detalhe">
                      {' '}
                      — estoque: {fmtQtd(i.saldo)} {fmtForma(i.saldo, i.forma_farmaceutica)}
                    </span>
                  </button>
                ))}
              </div>
            )}
            <div className="modal-acoes">
              <button
                type="button"
                className="botao-secundario"
                onClick={() => setResidente(null)}
              >
                ‹ Voltar
              </button>
            </div>
          </>
        )}

        {medicamento && (
          <>
            <p className="modal-medicamento">
              <strong>{residente.nome}</strong> — {medicamento.nome}{' '}
              {medicamento.dosagem} (estoque: {fmtQtd(medicamento.saldo)})
              {medicamento.idoso_da_casa && (
                <>
                  <br />
                  Sai do estoque da casa; a dose entra na ficha da {residente.nome}.
                </>
              )}
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
