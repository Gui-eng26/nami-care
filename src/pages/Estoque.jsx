import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase.js'
import { mensagemErro } from '../lib/erros.js'
import { fmtQtd, ROTULO_MOVIMENTACAO, dataHoraLocal } from '../lib/formato.js'
import ExtratoMovimentacoes from './ExtratoMovimentacoes.jsx'

// Aba Estoque com duas visões (DEC-036). O seletor comunica diferença de
// FUNÇÃO: "Estoque atual" tem as ações de compra/ajuste/perda (Sessão #4, sem
// mudança); "Extrato de movimentações" é somente leitura. Abre sempre em
// "Estoque atual" — idêntica à de antes.
export default function Estoque() {
  const [visao, setVisao] = useState('atual')
  return (
    <>
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
  const [abertoId, setAbertoId] = useState(null)

  const carregar = useCallback(async () => {
    const { data, error } = await supabase
      .from('cobertura_estoque')
      .select('*')
      .order('nome_idoso')
      .order('nome')
    if (!error) setItens(data)
  }, [])

  useEffect(() => {
    carregar()
  }, [carregar])

  const grupos = useMemo(() => {
    if (!itens) return null
    const porResidente = new Map()
    for (const item of itens) {
      if (!porResidente.has(item.idoso_id)) {
        porResidente.set(item.idoso_id, {
          nome: item.nome_idoso,
          ativo: item.idoso_ativo,
          itens: []
        })
      }
      porResidente.get(item.idoso_id).itens.push(item)
    }
    return [...porResidente.values()]
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
                mostrarResidente
                onAbrir={() => setAbertoId(item.medicamento_id)}
              />
            ))}
          </div>
        </section>
      )}

      <section className="secao">
        <h2>Estoque por residente</h2>
        {grupos.map((grupo) => (
          <div className="card" key={grupo.nome}>
            <h3 className="estoque-residente">
              {grupo.nome}
              {!grupo.ativo && <span className="chip chip-inativo"> Inativo</span>}
            </h3>
            {grupo.itens.map((item) => (
              <ItemEstoque
                key={item.medicamento_id}
                item={item}
                onAbrir={() => setAbertoId(item.medicamento_id)}
              />
            ))}
          </div>
        ))}
      </section>
    </>
  )
}

function ItemEstoque({ item, mostrarResidente = false, onAbrir }) {
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
      <span className="dose-acao">›</span>
    </button>
  )
}

// Ficha do medicamento: saldo, situação, movimentações manuais e o extrato —
// a auditoria linha a linha que substitui o caderno.
function FichaEstoque({ item, onVoltar, onMovimentado }) {
  const [extrato, setExtrato] = useState(null)
  const [modal, setModal] = useState(null) // 'entrada' | 'ajuste' | 'perda'
  const [aviso, setAviso] = useState(null)

  const carregarExtrato = useCallback(async () => {
    const { data, error } = await supabase
      .from('movimentacoes_estoque')
      .select('id, tipo, quantidade, motivo, criado_em, cuidadores (nome)')
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
          {extrato.map((mov) => (
            <li key={mov.id} className="extrato-linha">
              <span className="extrato-info">
                <span className="extrato-tipo">{ROTULO_MOVIMENTACAO[mov.tipo]}</span>
                <span className="extrato-detalhe">
                  {dataHoraLocal(mov.criado_em)}
                  {mov.cuidadores ? ` — ${mov.cuidadores.nome}` : ''}
                </span>
                {mov.motivo && <span className="extrato-detalhe">{mov.motivo}</span>}
              </span>
              <span className={`extrato-qtd ${Number(mov.quantidade) > 0 ? 'extrato-qtd-positiva' : 'extrato-qtd-negativa'}`}>
                {Number(mov.quantidade) > 0 ? '+' : '−'}{fmtQtd(Math.abs(Number(mov.quantidade)))}
              </span>
            </li>
          ))}
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
                p_observacao: valores.observacao || null
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
  const [observacao, setObservacao] = useState('')
  const [salvando, setSalvando] = useState(false)

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
            setSalvando(true)
            await onSalvar({ contada: Number(contada), observacao: observacao.trim() })
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
              onChange={(e) => setContada(e.target.value)}
              required
              autoFocus
            />
          </label>
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
