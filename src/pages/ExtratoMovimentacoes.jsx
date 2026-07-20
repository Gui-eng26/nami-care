import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase.js'
import { mensagemErro } from '../lib/erros.js'
import { fmtQtd, ROTULO_SUBTIPO, dataHoraLocal } from '../lib/formato.js'

const FUSO = 'America/Sao_Paulo'

function diaLocal(deslocDias = 0) {
  return new Date(Date.now() - deslocDias * 86400000).toLocaleDateString('en-CA', {
    timeZone: FUSO
  })
}

// Mesmo padrão de período da aba Adesão: atalhos + intervalo livre.
const ATALHOS = [
  { id: 'hoje', rotulo: 'Hoje', periodo: () => ({ inicio: diaLocal(), fim: diaLocal() }) },
  { id: 'ontem', rotulo: 'Ontem', periodo: () => ({ inicio: diaLocal(1), fim: diaLocal(1) }) },
  { id: '7dias', rotulo: 'Últimos 7 dias', periodo: () => ({ inicio: diaLocal(6), fim: diaLocal() }) },
  { id: 'mes', rotulo: 'Este mês', periodo: () => ({ inicio: `${diaLocal().slice(0, 8)}01`, fim: diaLocal() }) }
]

// Filtro por subtipo, combinável com o período. Entradas (verde) e saídas
// (vermelho) — a direção é o sinal da quantidade, não o tipo (DEC-036).
const FILTROS = [
  { grupo: 'Entradas', itens: [['compra', 'Compra'], ['ajuste_mais', 'Ajuste a mais']] },
  { grupo: 'Saídas', itens: [['dose', 'Dose'], ['ajuste_menos', 'Ajuste a menos'], ['perda', 'Perda']] }
]
const TODOS_SUBTIPOS = ['compra', 'ajuste_mais', 'dose', 'ajuste_menos', 'perda']

// Rótulo de situação por residente — mesma leitura da aba "Estoque atual"
// (DEC-027), sem jargão. Item inativo aparece sem alerta (DEC-029).
function rotuloResidente(tipo, r) {
  if (!r.item_ativo) return { texto: 'Inativo — sem alerta', alerta: false }
  if (tipo === 'continuo') {
    if (r.cobertura_dias === null) return { texto: 'Sem horários ativos', alerta: false }
    const dias = Number(r.cobertura_dias)
    if (dias < 1) return { texto: 'Menos de 1 dia de estoque', alerta: true }
    const arred = Math.round(dias)
    return { texto: `Dura ~${arred} dia${arred === 1 ? '' : 's'}`, alerta: r.alerta_reposicao }
  }
  if (r.estoque_minimo === null) return { texto: 'SOS — sem mínimo definido', alerta: false }
  if (r.alerta_reposicao) {
    return {
      texto: `Abaixo do mínimo (${fmtQtd(r.saldo)} de ${fmtQtd(r.estoque_minimo)})`,
      alerta: true
    }
  }
  return { texto: `SOS — mínimo ${fmtQtd(r.estoque_minimo)}`, alerta: false }
}

// Extrato de movimentações (DEC-036): tela SOMENTE LEITURA dentro da aba
// Estoque. A visão consolidada agrupa por item de catálogo (DEC-035) — uma
// linha por remédio, com o pior caso do grupo à frente e o detalhe por
// residente ao expandir. Clicar num residente abre o extrato do medicamento no
// período. Nenhuma ação de estoque vive aqui.
export default function ExtratoMovimentacoes() {
  const [tipo, setTipo] = useState('continuo')
  const [periodo, setPeriodo] = useState(ATALHOS[2].periodo()) // Últimos 7 dias
  const [atalho, setAtalho] = useState('7dias')
  const [aberto, setAberto] = useState(null) // { medicamentoId }

  function aplicarAtalho(a) {
    setAtalho(a.id)
    setPeriodo(a.periodo())
  }
  function mudarData(campo, valor) {
    if (!valor) return
    setAtalho(null)
    setPeriodo((p) => ({ ...p, [campo]: valor }))
  }

  return (
    <section className="secao">
      <div className="card">
        <div className="atalhos">
          {ATALHOS.map((a) => (
            <button
              key={a.id}
              type="button"
              className={`atalho ${atalho === a.id ? 'atalho-ativo' : ''}`}
              onClick={() => aplicarAtalho(a)}
            >
              {a.rotulo}
            </button>
          ))}
        </div>
        <div className="formulario-linha">
          <label>
            De
            <input
              type="date"
              value={periodo.inicio}
              max={diaLocal()}
              onChange={(e) => mudarData('inicio', e.target.value)}
            />
          </label>
          <label>
            Até
            <input
              type="date"
              value={periodo.fim}
              max={diaLocal()}
              onChange={(e) => mudarData('fim', e.target.value)}
            />
          </label>
        </div>
      </div>

      {aberto ? (
        <ExtratoDetalhe
          medicamentoId={aberto.medicamentoId}
          periodo={periodo}
          onVoltar={() => setAberto(null)}
        />
      ) : (
        <Consolidado
          tipo={tipo}
          onTipo={setTipo}
          onAbrir={(medicamentoId) => setAberto({ medicamentoId })}
        />
      )}
    </section>
  )
}

function Consolidado({ tipo, onTipo, onAbrir }) {
  const [itens, setItens] = useState(null)
  const [erro, setErro] = useState(null)
  const [expandido, setExpandido] = useState(() => new Set())

  useEffect(() => {
    let cancelado = false
    setItens(null)
    setErro(null)
    setExpandido(new Set())
    supabase.rpc('extrato_consolidado_estoque', { p_tipo: tipo }).then(({ data, error }) => {
      if (cancelado) return
      if (error) {
        setErro('Falha de conexão. Tente novamente.')
        return
      }
      if (!data.ok) {
        setErro(mensagemErro(data))
        return
      }
      setItens(data.itens)
    })
    return () => {
      cancelado = true
    }
  }, [tipo])

  function alternar(catalogoId) {
    setExpandido((s) => {
      const novo = new Set(s)
      if (novo.has(catalogoId)) novo.delete(catalogoId)
      else novo.add(catalogoId)
      return novo
    })
  }

  return (
    <>
      <div className="atalhos subabas">
        <button
          type="button"
          className={`atalho ${tipo === 'continuo' ? 'atalho-ativo' : ''}`}
          onClick={() => onTipo('continuo')}
        >
          Contínuo
        </button>
        <button
          type="button"
          className={`atalho ${tipo === 'sos' ? 'atalho-ativo' : ''}`}
          onClick={() => onTipo('sos')}
        >
          SOS
        </button>
      </div>

      {erro && (
        <div className="card">
          <p className="aviso aviso-erro">{erro}</p>
        </div>
      )}
      {!erro && itens === null && (
        <div className="card">
          <span className="status status-carregando">Carregando…</span>
        </div>
      )}
      {!erro && itens !== null && itens.length === 0 && (
        <div className="card">
          <p>Nenhum medicamento {tipo === 'sos' ? 'SOS' : 'contínuo'} cadastrado.</p>
        </div>
      )}
      {!erro && itens !== null && itens.length > 0 && (
        <div className="card">
          {itens.map((item) => (
            <ItemConsolidado
              key={item.catalogo_id}
              item={item}
              expandido={expandido.has(item.catalogo_id)}
              onAlternar={() => alternar(item.catalogo_id)}
              onAbrir={onAbrir}
            />
          ))}
        </div>
      )}
    </>
  )
}

function ItemConsolidado({ item, expandido, onAlternar, onAbrir }) {
  const multiplos = item.n_residentes > 1
  const pior = item.residentes[0] // já vem ordenado pior-primeiro do banco
  const situacao = rotuloResidente(item.tipo, pior)
  const nome = [item.nome, item.dosagem].filter(Boolean).join(' ')

  return (
    <div className="extrato-grupo">
      <button
        type="button"
        className={`dose ${item.n_ativos === 0 ? 'item-inativo' : ''}`}
        onClick={() => (multiplos ? onAlternar() : onAbrir(pior.medicamento_id))}
      >
        <span className="dose-idoso">
          {nome}
          {item.forma_farmaceutica ? ` — ${item.forma_farmaceutica}` : ''}
          {multiplos && <span className="chip chip-contagem"> {item.n_residentes} residentes</span>}
          {item.n_ativos === 0 && <span className="chip chip-inativo"> Inativo</span>}
        </span>
        <span className="dose-medicamento">
          {multiplos ? `Pior caso — ${pior.nome_idoso}: ` : ''}
          <span className={situacao.alerta ? 'estoque-rotulo-alerta' : ''}>{situacao.texto}</span>
        </span>
        <span className="dose-acao">{multiplos ? (expandido ? '▾' : '›') : '›'}</span>
      </button>

      {multiplos && expandido && (
        <ul className="extrato-detalhe-residentes">
          {item.residentes.map((r) => {
            const s = rotuloResidente(item.tipo, r)
            return (
              <li key={r.medicamento_id}>
                <button
                  type="button"
                  className={`dose dose-sub ${r.item_ativo ? '' : 'item-inativo'}`}
                  onClick={() => onAbrir(r.medicamento_id)}
                >
                  <span className="dose-idoso">
                    {r.nome_idoso}
                    {!r.item_ativo && <span className="chip chip-inativo"> Inativo</span>}
                  </span>
                  <span className="dose-medicamento">
                    {fmtQtd(r.saldo)} {item.forma_farmaceutica || 'unidade(s)'} —{' '}
                    <span className={s.alerta ? 'estoque-rotulo-alerta' : ''}>{s.texto}</span>
                  </span>
                  <span className="dose-acao">›</span>
                </button>
              </li>
            )
          })}
        </ul>
      )}
    </div>
  )
}

function ExtratoDetalhe({ medicamentoId, periodo, onVoltar }) {
  const [dados, setDados] = useState(null)
  const [erro, setErro] = useState(null)
  const [subtipos, setSubtipos] = useState(() => new Set(TODOS_SUBTIPOS))

  const pSubtipos = useMemo(() => {
    if (subtipos.size === TODOS_SUBTIPOS.length) return null // todos = sem filtro
    return [...subtipos]
  }, [subtipos])

  const carregar = useCallback(async () => {
    setErro(null)
    const { data, error } = await supabase.rpc('extrato_medicamento', {
      p_medicamento_id: medicamentoId,
      p_inicio: periodo.inicio,
      p_fim: periodo.fim,
      p_subtipos: pSubtipos
    })
    if (error) {
      setDados(null)
      setErro('Falha de conexão. Tente novamente.')
      return
    }
    if (!data.ok) {
      setDados(null)
      setErro(mensagemErro(data))
      return
    }
    setDados(data)
  }, [medicamentoId, periodo, pSubtipos])

  useEffect(() => {
    carregar()
  }, [carregar])

  function alternarSubtipo(chave) {
    setSubtipos((s) => {
      const novo = new Set(s)
      if (novo.has(chave)) novo.delete(chave)
      else novo.add(chave)
      return novo
    })
  }

  const med = dados?.medicamento
  const inativo = med && (!med.ativo || !med.idoso_ativo)

  return (
    <div className="card">
      <button type="button" className="botao-voltar" onClick={onVoltar}>
        ← Extrato
      </button>
      {med && (
        <>
          <div className="gestao-cabecalho">
            <h2>
              {med.nome} {med.dosagem}
            </h2>
            {med.tipo === 'sos' && <span className="chip chip-sos">SOS</span>}
          </div>
          <p>
            {med.nome_idoso}
            {inativo && <span className="chip chip-inativo"> Inativo</span>}
            {med.forma_farmaceutica ? ` — ${med.forma_farmaceutica}` : ''} · saldo atual{' '}
            <strong>{fmtQtd(med.saldo)}</strong>
          </p>
        </>
      )}

      <div className="extrato-filtros">
        {FILTROS.map((g) => (
          <div key={g.grupo} className="extrato-filtro-grupo">
            <span className="extrato-filtro-titulo">{g.grupo}</span>
            <div className="extrato-filtro-chips">
              {g.itens.map(([chave, rotulo]) => (
                <button
                  key={chave}
                  type="button"
                  className={`filtro-chip ${subtipos.has(chave) ? 'filtro-chip-ativo' : ''}`}
                  onClick={() => alternarSubtipo(chave)}
                >
                  {rotulo}
                </button>
              ))}
            </div>
          </div>
        ))}
      </div>

      {erro && <p className="aviso aviso-erro">{erro}</p>}
      {!erro && dados === null && <span className="status status-carregando">Carregando…</span>}
      {!erro && dados !== null && dados.movimentacoes.length === 0 && (
        <p>Nenhuma movimentação no período com os filtros escolhidos.</p>
      )}
      {!erro && dados !== null && dados.movimentacoes.length > 0 && (
        <ul className="lista-extrato">
          {dados.movimentacoes.map((mov) => {
            const positiva = Number(mov.quantidade) > 0
            return (
              <li key={mov.id} className="extrato-linha">
                <span className="extrato-info">
                  <span className="extrato-tipo">{ROTULO_SUBTIPO[mov.subtipo]}</span>
                  <span className="extrato-detalhe">
                    {dataHoraLocal(mov.criado_em)}
                    {mov.cuidador ? ` — ${mov.cuidador}` : ''}
                  </span>
                  {mov.motivo && <span className="extrato-detalhe">{mov.motivo}</span>}
                </span>
                <span
                  className={`extrato-qtd ${positiva ? 'extrato-qtd-positiva' : 'extrato-qtd-negativa'}`}
                >
                  {positiva ? '+' : '−'}
                  {fmtQtd(Math.abs(Number(mov.quantidade)))}
                </span>
              </li>
            )
          })}
        </ul>
      )}
    </div>
  )
}
