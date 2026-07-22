import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase.js'
import { mensagemErro } from '../lib/erros.js'
import { fmtQtd, ROTULO_MOVIMENTACAO, dataHoraLocal, dataLocal, resumoLotesMov } from '../lib/formato.js'
import ExtratoMovimentacoes from './ExtratoMovimentacoes.jsx'
import NovoMedicamento from './NovoMedicamento.jsx'

// Aba Estoque com duas visões (DEC-036). O seletor comunica diferença de
// FUNÇÃO: "Estoque atual" tem as ações de compra/ajuste/perda (Sessão #4, sem
// mudança); "Extrato de movimentações" é somente leitura. Abre sempre em
// "Estoque atual" — idêntica à de antes.
//
// O atalho "+ Medicamento" (Sessão #8) mora aqui, e não na home: é nesta aba
// que a cuidadora já vem ver saldo e lançar compra — e é aqui que o estoque
// inicial do cadastro aparece. Ao voltar, a lista remonta e relê o saldo.
export default function Estoque() {
  const [visao, setVisao] = useState('atual')
  const [cadastrando, setCadastrando] = useState(false)

  if (cadastrando) {
    return <NovoMedicamento onVoltar={() => setCadastrando(false)} />
  }

  return (
    <>
      <div className="estoque-acoes">
        <button
          type="button"
          className="botao-secundario"
          onClick={() => setCadastrando(true)}
        >
          + Medicamento
        </button>
      </div>
      <div className="segmented">
        <button
          type="button"
          className={`segmented-opcao ${visao === 'atual' ? 'segmented-ativa' : ''}`}
          onClick={() => setVisao('atual')}
        >
          Estoque atual
        </button>
        <button
          type="button"
          className={`segmented-opcao ${visao === 'extrato' ? 'segmented-ativa' : ''}`}
          onClick={() => setVisao('extrato')}
        >
          Extrato de movimentações
        </button>
      </div>
      {visao === 'atual' ? <EstoqueAtual /> : <ExtratoMovimentacoes />}
    </>
  )
}

const FUSO = 'America/Sao_Paulo'

function hojeLocal() {
  // yyyy-mm-dd no fuso da casa (para o input de data da compra)
  return new Date().toLocaleDateString('en-CA', { timeZone: FUSO })
}

// Rótulo de situação legível para a cuidadora (DEC-027): nada de jargão.
function rotuloSituacao(item) {
  if (item.tipo === 'continuo') {
    if (item.cobertura_dias === null) return { texto: 'Sem horários ativos', alerta: false }
    const dias = Number(item.cobertura_dias)
    if (dias < 1) return { texto: 'Menos de 1 dia de estoque', alerta: true }
    const arred = Math.round(dias)
    return {
      texto: `Dura ~${arred} dia${arred === 1 ? '' : 's'}`,
      alerta: item.alerta_reposicao
    }
  }
  if (item.estoque_minimo === null) {
    return { texto: 'SOS — sem mínimo definido', alerta: false }
  }
  if (item.alerta_reposicao) {
    return {
      texto: `Abaixo do mínimo (${fmtQtd(item.saldo)} de ${fmtQtd(item.estoque_minimo)})`,
      alerta: true
    }
  }
  return { texto: `SOS — mínimo ${fmtQtd(item.estoque_minimo)}`, alerta: false }
}

// Visão de estoque (DEC-004/DEC-027): tudo que a tela mostra vem da view
// cobertura_estoque (saldo = soma do ledger; cobertura e alerta calculados no
// banco). Organização por residente (DEC-029): espelha as caixas físicas —
// cada residente tem o próprio estoque; itens em alerta sobem para o topo.
function EstoqueAtual() {
  const [itens, setItens] = useState(null)
  const [lotesPorMed, setLotesPorMed] = useState(() => new Map())
  const [abertoId, setAbertoId] = useState(null)

  const carregar = useCallback(async () => {
    const [{ data, error }, lotesRes] = await Promise.all([
      supabase.from('cobertura_estoque').select('*').order('nome_idoso').order('nome'),
      // Lotes vivos (saldo > 0), próximo a vencer primeiro (DEC-043).
      supabase
        .from('lotes_estoque_vivo')
        .select('medicamento_id, lote, validade, saldo_atual')
        .order('validade', { ascending: true })
        .order('data_entrada', { ascending: true })
    ])
    if (!error) setItens(data)
    const mapa = new Map()
    for (const l of lotesRes.data ?? []) {
      if (!mapa.has(l.medicamento_id)) mapa.set(l.medicamento_id, [])
      mapa.get(l.medicamento_id).push(l)
    }
    setLotesPorMed(mapa)
  }, [])

  useEffect(() => {
    carregar()
  }, [carregar])

  // Dois blocos (DEC-044): o estoque da casa é uma prateleira à parte, não um
  // "residente" no meio dos outros — espelha a caixa comum da bancada.
  const grupos = useMemo(() => {
    if (!itens) return null
    const porResidente = new Map()
    const casa = []
    for (const item of itens) {
      if (item.idoso_da_casa) {
        casa.push(item)
        continue
      }
      if (!porResidente.has(item.idoso_id)) {
        porResidente.set(item.idoso_id, {
          nome: item.nome_idoso,
          ativo: item.idoso_ativo,
          itens: []
        })
      }
      porResidente.get(item.idoso_id).itens.push(item)
    }
    return { casa, residentes: [...porResidente.values()] }
  }, [itens])

  if (grupos === null) {
    return (
      <div className="card">
        <span className="status status-carregando">Carregando o estoque…</span>
      </div>
    )
  }

  const aberto = abertoId ? itens.find((i) => i.medicamento_id === abertoId) : null
  if (aberto) {
    return (
      <FichaEstoque
        item={aberto}
        lotes={lotesPorMed.get(aberto.medicamento_id) ?? []}
        onVoltar={() => setAbertoId(null)}
        onMovimentado={carregar}
      />
    )
  }

  const alertas = itens.filter((i) => i.alerta_reposicao)

  return (
    <>
      {alertas.length > 0 && (
        <section className="secao secao-repor">
          <h2>Repor — {alertas.length} {alertas.length === 1 ? 'item' : 'itens'} em alerta</h2>
          <div className="card card-alerta">
            {alertas.map((item) => (
              <ItemEstoque
                key={item.medicamento_id}
                item={item}
                lotes={lotesPorMed.get(item.medicamento_id) ?? []}
                mostrarResidente
                onAbrir={() => setAbertoId(item.medicamento_id)}
              />
            ))}
          </div>
        </section>
      )}

      {grupos.casa.length > 0 && (
        <section className="secao">
          <h2>Medicamentos da casa</h2>
          <div className="card card-casa">
            <p className="estoque-casa-explicacao">
              SOS da caixa comum: não pertencem a um residente, mas quem toma é
              sempre registrado no nome dela.
            </p>
            {grupos.casa.map((item) => (
              <ItemEstoque
                key={item.medicamento_id}
                item={item}
                lotes={lotesPorMed.get(item.medicamento_id) ?? []}
                onAbrir={() => setAbertoId(item.medicamento_id)}
              />
            ))}
          </div>
        </section>
      )}

      <section className="secao">
        <h2>Estoque por residente</h2>
        {grupos.residentes.map((grupo) => (
          <div className="card" key={grupo.nome}>
            <h3 className="estoque-residente">
              {grupo.nome}
              {!grupo.ativo && <span className="chip chip-inativo"> Inativo</span>}
            </h3>
            {grupo.itens.map((item) => (
              <ItemEstoque
                key={item.medicamento_id}
                item={item}
                lotes={lotesPorMed.get(item.medicamento_id) ?? []}
                onAbrir={() => setAbertoId(item.medicamento_id)}
              />
            ))}
          </div>
        ))}
      </section>
    </>
  )
}

function ItemEstoque({ item, lotes = [], mostrarResidente = false, onAbrir }) {
  const situacao = rotuloSituacao(item)
  return (
    <button type="button" className={`dose ${item.ativo ? '' : 'item-inativo'}`} onClick={onAbrir}>
      <span className="dose-idoso">
        {mostrarResidente ? `${item.nome_idoso} — ` : ''}
        {item.nome} {item.dosagem}
        {item.tipo === 'sos' && <span className="chip chip-sos"> SOS</span>}
        {!item.ativo && <span className="chip chip-inativo"> Inativo</span>}
      </span>
      <span className="dose-medicamento">
        {fmtQtd(item.saldo)} {item.forma_farmaceutica || 'unidade(s)'} —{' '}
        <span className={situacao.alerta ? 'estoque-rotulo-alerta' : ''}>{situacao.texto}</span>
        {situacao.alerta && item.sugestao_compra !== null && item.tipo === 'continuo' && (
          <> · comprar {fmtQtd(item.sugestao_compra)}</>
        )}
      </span>
      <ResumoLotes lotes={lotes} />
      <span className="dose-acao">›</span>
    </button>
  )
}

// Lotes vivos por validade (próximo a vencer em destaque — DEC-043). Compacto
// na lista; a ficha mostra a versão completa.
function ResumoLotes({ lotes }) {
  if (!lotes || lotes.length === 0) return null
  return (
    <span className="estoque-lotes">
      {lotes.map((l, i) => (
        <span key={l.lote ?? i} className={`lote-chip ${i === 0 ? 'lote-chip-proximo' : ''}`}>
          venc. {dataLocal(l.validade)} · {fmtQtd(l.saldo_atual)}
        </span>
      ))}
    </span>
  )
}

// Ficha do medicamento: saldo, situação, movimentações manuais e o extrato —
// a auditoria linha a linha que substitui o caderno.
function FichaEstoque({ item, lotes = [], onVoltar, onMovimentado }) {
  const [extrato, setExtrato] = useState(null)
  const [modal, setModal] = useState(null) // 'entrada' | 'ajuste' | 'perda'
  const [aviso, setAviso] = useState(null)

  const carregarExtrato = useCallback(async () => {
    const { data, error } = await supabase
      .from('movimentacoes_estoque')
      .select(
        'id, tipo, quantidade, motivo, criado_em, cuidadores (nome), movimentacao_lote (quantidade, lotes_estoque (lote, validade))'
      )
      .eq('medicamento_id', item.medicamento_id)
      .order('criado_em', { ascending: false })
      .limit(50)
    setExtrato(error ? [] : data)
  }, [item.medicamento_id])

  useEffect(() => {
    carregarExtrato()
  }, [carregarExtrato])

  const situacao = rotuloSituacao(item)

  async function chamarRpc(nome, params, textoOk) {
    setAviso(null)
    const { data, error } = await supabase.rpc(nome, params)
    if (error) {
      setAviso({ tipo: 'erro', texto: 'Falha de conexão. Tente novamente.' })
      return false
    }
    if (!data.ok) {
      setAviso({ tipo: 'erro', texto: mensagemErro(data) })
      return false
    }
    setModal(null)
    setAviso({ tipo: 'ok', texto: textoOk(data) })
    carregarExtrato()
    onMovimentado()
    return true
  }

  return (
    <div className="card">
      <button type="button" className="botao-voltar" onClick={onVoltar}>
        ← Estoque
      </button>
      <div className="gestao-cabecalho">
        <h2>
          {item.nome} {item.dosagem}
        </h2>
        {item.tipo === 'sos' && <span className="chip chip-sos">SOS</span>}
        {item.idoso_da_casa && <span className="chip chip-casa">Da casa</span>}
      </div>
      <p>
        {item.nome_idoso}
        {item.forma_farmaceutica ? ` — ${item.forma_farmaceutica}` : ''}
      </p>

      <p className="estoque-saldo">
        {fmtQtd(item.saldo)}{' '}
        <span className="estoque-saldo-unidade">{item.forma_farmaceutica || 'unidade(s)'}</span>
      </p>
      <p className={situacao.alerta ? 'estoque-rotulo-alerta' : 'estoque-rotulo'}>
        {situacao.texto}
        {situacao.alerta && item.sugestao_compra !== null && item.tipo === 'continuo' && (
          <> — sugestão: comprar {fmtQtd(item.sugestao_compra)} para ~30 dias</>
        )}
      </p>

      <div className="lotes-prateleira">
        <h3 className="lotes-titulo">Lotes na prateleira</h3>
        {lotes.length === 0 ? (
          <p className="lotes-vazio">Sem lote com saldo. Registre uma compra para começar.</p>
        ) : (
          <ul className="lotes-lista">
            {lotes.map((l, i) => (
              <li key={l.lote ?? i} className={`lote-linha ${i === 0 ? 'lote-linha-proximo' : ''}`}>
                <span className="lote-nome">
                  {l.lote || 'Lote não identificado'}
                  {i === 0 && lotes.length > 1 && <span className="chip chip-proximo"> Próximo a vencer</span>}
                </span>
                <span className="lote-detalhe">
                  Vence {dataLocal(l.validade)} · {fmtQtd(l.saldo_atual)}{' '}
                  {item.forma_farmaceutica || 'un.'}
                </span>
              </li>
            ))}
          </ul>
        )}
      </div>

      {aviso && (
        <p className={`aviso ${aviso.tipo === 'ok' ? 'aviso-ok' : 'aviso-erro'}`}>{aviso.texto}</p>
      )}

      <div className="acoes-item">
        {item.ativo && (
          <button type="button" className="botao-mini" onClick={() => { setAviso(null); setModal('entrada') }}>
            + Registrar compra
          </button>
        )}
        <button type="button" className="botao-mini" onClick={() => { setAviso(null); setModal('ajuste') }}>
          Ajustar por contagem
        </button>
        <button type="button" className="botao-mini botao-mini-perigo" onClick={() => { setAviso(null); setModal('perda') }}>
          Registrar perda
        </button>
      </div>

      <div className="gestao-cabecalho" style={{ marginTop: '1rem' }}>
        <h2>Extrato de movimentações</h2>
      </div>
      {extrato === null ? (
        <span className="status status-carregando">Carregando…</span>
      ) : extrato.length === 0 ? (
        <p>Nenhuma movimentação registrada.</p>
      ) : (
        <ul className="lista-extrato">
          {extrato.map((mov) => {
            const resumoLotes = resumoLotesMov(
              (mov.movimentacao_lote ?? []).map((ml) => ({
                lote: ml.lotes_estoque?.lote,
                validade: ml.lotes_estoque?.validade,
                quantidade: ml.quantidade
              }))
            )
            return (
            <li key={mov.id} className="extrato-linha">
              <span className="extrato-info">
                <span className="extrato-tipo">{ROTULO_MOVIMENTACAO[mov.tipo]}</span>
                <span className="extrato-detalhe">
                  {dataHoraLocal(mov.criado_em)}
                  {mov.cuidadores ? ` — ${mov.cuidadores.nome}` : ''}
                </span>
                {mov.motivo && <span className="extrato-detalhe">{mov.motivo}</span>}
                {resumoLotes && <span className="extrato-detalhe extrato-lote">Lote: {resumoLotes}</span>}
              </span>
              <span className={`extrato-qtd ${Number(mov.quantidade) > 0 ? 'extrato-qtd-positiva' : 'extrato-qtd-negativa'}`}>
                {Number(mov.quantidade) > 0 ? '+' : '−'}{fmtQtd(Math.abs(Number(mov.quantidade)))}
              </span>
            </li>
            )
          })}
        </ul>
      )}

      {modal === 'entrada' && (
        <ModalEntrada
          item={item}
          onFechar={() => setModal(null)}
          onSalvar={(valores) =>
            chamarRpc(
              'registrar_entrada_estoque',
              {
                p_medicamento_id: item.medicamento_id,
                p_quantidade: valores.quantidade,
                p_validade: valores.validade,
                p_lote: valores.lote || null,
                p_data: valores.data,
                p_observacao: valores.observacao || null
              },
              (r) => `Compra registrada. Saldo atual: ${fmtQtd(r.saldo)}.`
            )
          }
        />
      )}
      {modal === 'ajuste' && (
        <ModalAjuste
          item={item}
          onFechar={() => setModal(null)}
          onSalvar={(valores) =>
            chamarRpc(
              'registrar_ajuste_estoque',
              {
                p_medicamento_id: item.medicamento_id,
                p_quantidade_contada: valores.contada,
                p_observacao: valores.observacao || null,
                p_lote: valores.lote || null,
                p_validade: valores.validade || null
              },
              (r) =>
                r.sem_diferenca
                  ? `Contagem confere com o sistema (${fmtQtd(r.saldo)}). Nada a ajustar.`
                  : `Ajuste registrado: ${Number(r.diferenca) > 0 ? '+' : '−'}${fmtQtd(Math.abs(Number(r.diferenca)))}. Saldo corrigido: ${fmtQtd(r.saldo)}.`
            )
          }
        />
      )}
      {modal === 'perda' && (
        <ModalPerda
          item={item}
          onFechar={() => setModal(null)}
          onSalvar={(valores) =>
            chamarRpc(
              'registrar_perda_estoque',
              {
                p_medicamento_id: item.medicamento_id,
                p_quantidade: valores.quantidade,
                p_motivo: valores.motivo
              },
              (r) => `Perda registrada. Saldo atual: ${fmtQtd(r.saldo)}.`
            )
          }
        />
      )}
    </div>
  )
}

function ModalEntrada({ item, onFechar, onSalvar }) {
  const [quantidade, setQuantidade] = useState('')
  const [data, setData] = useState(hojeLocal())
  const [lote, setLote] = useState('')
  const [validade, setValidade] = useState('')
  const [observacao, setObservacao] = useState('')
  const [salvando, setSalvando] = useState(false)

  return (
    <div className="modal-fundo" onClick={onFechar}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>Registrar compra</h3>
        <p className="modal-medicamento">
          {item.nome} {item.dosagem} — {item.nome_idoso}
        </p>
        <form
          className="formulario"
          onSubmit={async (e) => {
            e.preventDefault()
            setSalvando(true)
            await onSalvar({
              quantidade: Number(quantidade),
              data,
              lote: lote.trim(),
              validade,
              observacao: observacao.trim()
            })
            setSalvando(false)
          }}
        >
          <div className="formulario-linha">
            <label>
              Quantidade
              <input
                type="number"
                min="0.5"
                step="0.5"
                inputMode="decimal"
                value={quantidade}
                onChange={(e) => setQuantidade(e.target.value)}
                required
                autoFocus
              />
            </label>
            <label>
              Data da compra
              <input
                type="date"
                value={data}
                max={hojeLocal()}
                onChange={(e) => setData(e.target.value)}
                required
              />
            </label>
          </div>
          <div className="formulario-linha">
            <label>
              Lote (opcional)
              <input
                value={lote}
                placeholder="código da caixa"
                onChange={(e) => setLote(e.target.value)}
              />
            </label>
            <label>
              Validade
              <input
                type="date"
                value={validade}
                onChange={(e) => setValidade(e.target.value)}
                required
              />
            </label>
          </div>
          <label>
            Observação (opcional)
            <input
              value={observacao}
              placeholder="ex.: farmácia do bairro, 2 caixas"
              onChange={(e) => setObservacao(e.target.value)}
            />
          </label>
          <div className="modal-acoes">
            <button type="button" className="botao-secundario" onClick={onFechar} disabled={salvando}>
              Cancelar
            </button>
            <button type="submit" className="botao-primario" disabled={salvando}>
              {salvando ? 'Registrando…' : 'Registrar compra'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}

function ModalAjuste({ item, onFechar, onSalvar }) {
  const [contada, setContada] = useState('')
  const [lote, setLote] = useState('')
  const [validade, setValidade] = useState('')
  const [observacao, setObservacao] = useState('')
  const [erro, setErro] = useState(null)
  const [salvando, setSalvando] = useState(false)

  // A recontagem para CIMA (contou mais do que o sistema) achou unidades que
  // pertencem a um lote físico — a validade é obrigatória (DEC-041). Para baixo
  // (ou igual), lote/validade são ignorados: o abate é por FEFO.
  const paraCima = contada !== '' && Number(contada) > Number(item.saldo)

  return (
    <div className="modal-fundo" onClick={onFechar}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>Ajustar por contagem</h3>
        <p className="modal-medicamento">
          {item.nome} {item.dosagem} — {item.nome_idoso}
          <br />
          Saldo no sistema: <strong>{fmtQtd(item.saldo)}</strong>. Informe o que você contou;
          a diferença fica registrada no extrato.
        </p>
        <form
          className="formulario"
          onSubmit={async (e) => {
            e.preventDefault()
            if (paraCima && !validade) {
              setErro('Você contou mais do que o sistema: informe a validade do lote encontrado.')
              return
            }
            setErro(null)
            setSalvando(true)
            await onSalvar({
              contada: Number(contada),
              observacao: observacao.trim(),
              lote: paraCima ? lote.trim() : '',
              validade: paraCima ? validade : ''
            })
            setSalvando(false)
          }}
        >
          <label>
            Quantidade contada
            <input
              type="number"
              min="0"
              step="0.5"
              inputMode="decimal"
              value={contada}
              onChange={(e) => {
                setErro(null)
                setContada(e.target.value)
              }}
              required
              autoFocus
            />
          </label>
          {paraCima && (
            <div className="formulario-linha">
              <label>
                Lote encontrado (opcional)
                <input
                  value={lote}
                  placeholder="código da caixa"
                  onChange={(e) => setLote(e.target.value)}
                />
              </label>
              <label>
                Validade
                <input
                  type="date"
                  value={validade}
                  onChange={(e) => setValidade(e.target.value)}
                  required
                />
              </label>
            </div>
          )}
          {erro && <p className="aviso aviso-erro">{erro}</p>}
          <label>
            Observação (opcional)
            <input
              value={observacao}
              placeholder="ex.: conferência semanal"
              onChange={(e) => setObservacao(e.target.value)}
            />
          </label>
          <div className="modal-acoes">
            <button type="button" className="botao-secundario" onClick={onFechar} disabled={salvando}>
              Cancelar
            </button>
            <button type="submit" className="botao-primario" disabled={salvando}>
              {salvando ? 'Registrando…' : 'Registrar contagem'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}

function ModalPerda({ item, onFechar, onSalvar }) {
  const [quantidade, setQuantidade] = useState('')
  const [motivo, setMotivo] = useState('')
  const [salvando, setSalvando] = useState(false)

  return (
    <div className="modal-fundo" onClick={onFechar}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>Registrar perda</h3>
        <p className="modal-medicamento">
          {item.nome} {item.dosagem} — {item.nome_idoso}
          <br />
          Quebra, vencimento ou metade descartada (DEC-013).
        </p>
        <form
          className="formulario"
          onSubmit={async (e) => {
            e.preventDefault()
            setSalvando(true)
            await onSalvar({ quantidade: Number(quantidade), motivo: motivo.trim() })
            setSalvando(false)
          }}
        >
          <label>
            Quantidade perdida
            <input
              type="number"
              min="0.5"
              step="0.5"
              inputMode="decimal"
              value={quantidade}
              onChange={(e) => setQuantidade(e.target.value)}
              required
              autoFocus
            />
          </label>
          <label>
            Motivo (obrigatório)
            <input
              value={motivo}
              placeholder="ex.: comprimido caiu no chão"
              onChange={(e) => setMotivo(e.target.value)}
              required
            />
          </label>
          <div className="modal-acoes">
            <button type="button" className="botao-secundario" onClick={onFechar} disabled={salvando}>
              Cancelar
            </button>
            <button type="submit" className="botao-primario" disabled={salvando}>
              {salvando ? 'Registrando…' : 'Registrar perda'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
