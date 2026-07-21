import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase.js'

const FUSO = 'America/Sao_Paulo'

function hojeLocal() {
  return new Date().toLocaleDateString('en-CA', { timeZone: FUSO })
}

// Formata "Nome dosagem — forma" para exibir um item do catálogo.
function rotuloCatalogo(item) {
  const dose = item.dosagem ? ` ${item.dosagem}` : ''
  const forma = item.forma_farmaceutica ? ` — ${item.forma_farmaceutica}` : ''
  return `${item.nome}${dose}${forma}`
}

// Cadastro/edição de medicamento (DEC-035): nome/dosagem/forma vêm do CATÁLOGO
// da casa (entidade compartilhada), nunca de texto livre na tela do residente —
// editar por texto mudaria o remédio de todos os residentes vinculados ao item.
// O medicamento é a) selecionar um item existente (busca por nome) ou b) criar
// um item novo do catálogo. posologia/tipo/estoque_minimo continuam por
// residente e sempre editáveis.
//
// No CADASTRO (não na edição) há ainda o estoque inicial opcional da Sessão #8:
// evita a segunda viagem à aba Estoque para lançar o que já veio com o remédio.
//
// Componente compartilhado pelas duas portas de cadastro: a gestão de
// residentes e o atalho "+ Medicamento" da aba Estoque.
export default function FormMedicamento({ medicamento, subtitulo, ocupado, onFechar, onSalvar }) {
  // catalogo escolhido: { id, nome, dosagem, forma_farmaceutica } | null.
  const [catalogo, setCatalogo] = useState(
    medicamento
      ? {
          id: medicamento.catalogo_id,
          nome: medicamento.nome,
          dosagem: medicamento.dosagem,
          forma_farmaceutica: medicamento.forma_farmaceutica
        }
      : null
  )
  // 'escolhido' (item definido) | 'buscar' (procurando) | 'novo' (criando item).
  const [modo, setModo] = useState(medicamento ? 'escolhido' : 'buscar')
  const [termo, setTermo] = useState('')
  const [resultados, setResultados] = useState([])
  const [novo, setNovo] = useState({ nome: '', dosagem: '', forma: '' })
  const [erroCatalogo, setErroCatalogo] = useState(null)

  const [posologia, setPosologia] = useState(medicamento?.posologia ?? '')
  const [tipo, setTipo] = useState(medicamento?.tipo ?? 'continuo')
  const [estoqueMinimo, setEstoqueMinimo] = useState(
    medicamento?.estoque_minimo != null ? String(Number(medicamento.estoque_minimo)) : ''
  )

  // Estoque inicial (Sessão #8) — só no cadastro; em branco = sem movimentação.
  const [qtdInicial, setQtdInicial] = useState('')
  const [origemInicial, setOrigemInicial] = useState('compra')
  const [dataInicial, setDataInicial] = useState(hojeLocal())

  useEffect(() => {
    if (modo !== 'buscar') return
    const t = termo.trim()
    if (t.length < 2) {
      setResultados([])
      return
    }
    let cancelado = false
    supabase
      .from('catalogo_medicamentos')
      .select('id, nome, dosagem, forma_farmaceutica')
      .ilike('nome', `%${t}%`)
      .order('nome')
      .limit(15)
      .then(({ data }) => {
        if (!cancelado) setResultados(data ?? [])
      })
    return () => {
      cancelado = true
    }
  }, [termo, modo])

  function submeter(e) {
    e.preventDefault()
    setErroCatalogo(null)
    let catalogoId = null
    let nome = ''
    let dosagem = ''
    let forma = ''
    if (modo === 'escolhido' && catalogo?.id) {
      catalogoId = catalogo.id
    } else if (modo === 'novo') {
      nome = novo.nome.trim()
      dosagem = novo.dosagem.trim()
      forma = novo.forma.trim()
      if (nome === '') {
        setErroCatalogo('Informe o nome do medicamento.')
        return
      }
    } else {
      setErroCatalogo('Selecione um medicamento do catálogo ou crie um novo item.')
      return
    }
    onSalvar({
      catalogoId,
      nome,
      dosagem,
      forma,
      posologia: posologia.trim(),
      tipo,
      // Estoque mínimo só faz sentido para SOS (DEC-027).
      estoqueMinimo: tipo === 'sos' && estoqueMinimo !== '' ? Number(estoqueMinimo) : null,
      estoqueInicial:
        !medicamento && qtdInicial !== '' && Number(qtdInicial) > 0
          ? {
              quantidade: Number(qtdInicial),
              origem: origemInicial,
              data: origemInicial === 'compra' ? dataInicial : null
            }
          : null
    })
  }

  return (
    <div className="modal-fundo" onClick={onFechar}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>{medicamento ? `Editar ${medicamento.nome}` : 'Novo medicamento'}</h3>
        {subtitulo && <p className="modal-subtitulo">{subtitulo}</p>}
        <form className="formulario" onSubmit={submeter}>
          <div className="catalogo-bloco">
            <span className="catalogo-rotulo">Medicamento (catálogo da casa)</span>

            {modo === 'escolhido' && (
              <div className="catalogo-escolhido">
                <span className="catalogo-escolhido-nome">
                  {catalogo ? rotuloCatalogo(catalogo) : '—'}
                </span>
                <button
                  type="button"
                  className="botao-mini"
                  onClick={() => {
                    setModo('buscar')
                    setTermo('')
                    setResultados([])
                  }}
                >
                  Trocar
                </button>
              </div>
            )}

            {modo === 'buscar' && (
              <>
                <input
                  autoFocus
                  value={termo}
                  placeholder="Buscar por nome (ex.: Losartana)"
                  onChange={(e) => setTermo(e.target.value)}
                />
                {termo.trim().length >= 2 && (
                  <ul className="catalogo-resultados">
                    {resultados.map((item) => (
                      <li key={item.id}>
                        <button
                          type="button"
                          className="catalogo-opcao"
                          onClick={() => {
                            setCatalogo(item)
                            setModo('escolhido')
                            setErroCatalogo(null)
                          }}
                        >
                          {rotuloCatalogo(item)}
                        </button>
                      </li>
                    ))}
                    {resultados.length === 0 && (
                      <li className="catalogo-vazio">Nada encontrado no catálogo.</li>
                    )}
                  </ul>
                )}
                <button
                  type="button"
                  className="botao-secundario botao-catalogo-novo"
                  onClick={() => {
                    setNovo({ nome: termo.trim(), dosagem: '', forma: '' })
                    setModo('novo')
                    setErroCatalogo(null)
                  }}
                >
                  + Criar novo item do catálogo
                </button>
                {medicamento && (
                  <button
                    type="button"
                    className="botao-mini catalogo-cancelar-troca"
                    onClick={() => setModo('escolhido')}
                  >
                    Cancelar troca
                  </button>
                )}
              </>
            )}

            {modo === 'novo' && (
              <>
                <label>
                  Nome
                  <input
                    autoFocus
                    value={novo.nome}
                    onChange={(e) => setNovo((n) => ({ ...n, nome: e.target.value }))}
                    required
                  />
                </label>
                <div className="formulario-linha">
                  <label>
                    Dosagem
                    <input
                      value={novo.dosagem}
                      placeholder="ex.: 50 mg"
                      onChange={(e) => setNovo((n) => ({ ...n, dosagem: e.target.value }))}
                    />
                  </label>
                  <label>
                    Forma
                    <input
                      value={novo.forma}
                      placeholder="ex.: comprimido"
                      onChange={(e) => setNovo((n) => ({ ...n, forma: e.target.value }))}
                    />
                  </label>
                </div>
                <button
                  type="button"
                  className="botao-mini"
                  onClick={() => {
                    setModo('buscar')
                    setErroCatalogo(null)
                  }}
                >
                  ‹ Voltar à busca
                </button>
              </>
            )}

            {erroCatalogo && <p className="aviso aviso-erro">{erroCatalogo}</p>}
          </div>

          <label>
            Posologia (orientação)
            <textarea rows={2} value={posologia} onChange={(e) => setPosologia(e.target.value)} />
          </label>
          <label>
            Tipo
            <select value={tipo} onChange={(e) => setTipo(e.target.value)}>
              <option value="continuo">Contínuo (com horários de ronda)</option>
              <option value="sos">SOS (dose avulsa, sem horários)</option>
            </select>
          </label>
          {tipo === 'sos' && (
            <label>
              Estoque mínimo de segurança (opcional)
              <input
                type="number"
                min="0"
                step="0.5"
                inputMode="decimal"
                placeholder="alerta de recompra abaixo desta quantidade"
                value={estoqueMinimo}
                onChange={(e) => setEstoqueMinimo(e.target.value)}
              />
            </label>
          )}

          {!medicamento && (
            <div className="catalogo-bloco">
              <span className="catalogo-rotulo">Estoque inicial (opcional)</span>
              <label>
                Quantidade
                <input
                  type="number"
                  min="0"
                  step="0.5"
                  inputMode="decimal"
                  placeholder="deixe em branco para não lançar nada"
                  value={qtdInicial}
                  onChange={(e) => setQtdInicial(e.target.value)}
                />
              </label>
              {qtdInicial !== '' && Number(qtdInicial) > 0 && (
                <>
                  <label>
                    De onde veio
                    <select
                      value={origemInicial}
                      onChange={(e) => setOrigemInicial(e.target.value)}
                    >
                      <option value="compra">Compra (entrada no estoque)</option>
                      <option value="remanescente">
                        Já estava na prateleira (ajuste de contagem)
                      </option>
                    </select>
                  </label>
                  {origemInicial === 'compra' && (
                    <label>
                      Data da compra
                      <input
                        type="date"
                        max={hojeLocal()}
                        value={dataInicial}
                        onChange={(e) => setDataInicial(e.target.value)}
                      />
                    </label>
                  )}
                </>
              )}
            </div>
          )}

          <div className="modal-acoes">
            <button type="button" className="botao-secundario" onClick={onFechar} disabled={ocupado}>
              Cancelar
            </button>
            <button type="submit" className="botao-primario" disabled={ocupado}>
              {ocupado ? 'Salvando…' : 'Salvar'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
