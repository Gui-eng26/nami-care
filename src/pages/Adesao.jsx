import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase.js'
import { mensagemErro } from '../lib/erros.js'
import { fmtQtd, dataHoraLocal, horaLocal } from '../lib/formato.js'

const FUSO = 'America/Sao_Paulo'

function diaLocal(deslocDias = 0) {
  // yyyy-mm-dd no fuso da casa, deslocDias atrás (0 = hoje)
  return new Date(Date.now() - deslocDias * 86400000).toLocaleDateString('en-CA', {
    timeZone: FUSO
  })
}

// Atalhos apenas pré-calculam as duas datas — mesmo caminho de consulta do
// calendário livre, sem query nem estado próprios.
const ATALHOS = [
  { id: 'hoje', rotulo: 'Hoje', periodo: () => ({ inicio: diaLocal(), fim: diaLocal() }) },
  { id: 'ontem', rotulo: 'Ontem', periodo: () => ({ inicio: diaLocal(1), fim: diaLocal(1) }) },
  { id: '7dias', rotulo: 'Últimos 7 dias', periodo: () => ({ inicio: diaLocal(6), fim: diaLocal() }) },
  { id: 'mes', rotulo: 'Este mês', periodo: () => ({ inicio: `${diaLocal().slice(0, 8)}01`, fim: diaLocal() }) }
]

// Rótulos legíveis para a cuidadora (padrão DEC-027). "Recusada" e "não
// tomada" nunca se somam: uma é decisão do residente, a outra é falha
// operacional — o sinal mais grave dos dois. "Pendente (não apurado)"
// (DEC-034) também é categoria própria: não é confirmação de falta (seria
// "não tomada") nem de ocorrência — é a decisão consciente de não apurar,
// vinda da resolução em lote das pendências entre turnos.
const CATEGORIAS = [
  { chave: 'no_horario', rotulo: 'No horário', cor: 'var(--cor-ok)' },
  { chave: 'atrasada', rotulo: 'Atrasadas', cor: 'var(--cor-alerta)' },
  { chave: 'recusada', rotulo: 'Recusadas', cor: 'var(--cor-erro)' },
  { chave: 'nao_tomada', rotulo: 'Não tomadas', cor: '#7f1d1d' },
  { chave: 'nao_apurada', rotulo: 'Pendente (não apurado)', cor: '#78716c' }
]

// Rótulo do detalhe (DEC-048). O SOS não é categoria do denominador, mas tem
// extrato próprio — daí não estar na lista acima e aparecer aqui.
const ROTULO_CATEGORIA = {
  ...Object.fromEntries(CATEGORIAS.map((c) => [c.chave, c.rotulo])),
  sos: 'Doses SOS'
}

function fmtPct(pct) {
  if (pct === null || pct === undefined) return '—'
  return `${String(pct).replace('.', ',')}%`
}

function dataCurta(iso) {
  const [ano, mes, dia] = iso.split('-')
  return `${dia}/${mes}/${ano}`
}

// Relatório de adesão (DEC-030/031/032): tudo calculado no banco pela RPC
// relatorio_adesao — percentuais inclusive. Aqui só apresentação e formato.
// A visão da casa é a do residente sem o filtro: mesmo caminho de cálculo.
export default function Adesao() {
  const [periodo, setPeriodo] = useState(ATALHOS[0].periodo())
  const [atalho, setAtalho] = useState('hoje')
  const [idosoId, setIdosoId] = useState('')
  const [residentes, setResidentes] = useState([])
  const [dados, setDados] = useState(null)
  const [erro, setErro] = useState(null)
  // Categoria aberta no extrato (DEC-048). Só existe com residente escolhido.
  const [categoria, setCategoria] = useState(null)

  useEffect(() => {
    // O "Da Casa" (DEC-044) fica fora: ele não tem adesão própria — o consumo
    // do SOS da casa é contado no residente que tomou (DEC-046).
    supabase
      .from('idosos')
      .select('id, nome, ativo')
      .eq('eh_sentinela', false)
      .order('nome')
      .then(({ data, error }) => {
        if (!error) setResidentes(data)
      })
  }, [])

  const carregar = useCallback(async () => {
    setErro(null)
    const { data, error } = await supabase.rpc('relatorio_adesao', {
      p_inicio: periodo.inicio,
      p_fim: periodo.fim,
      p_idoso_id: idosoId || null
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
  }, [periodo, idosoId])

  useEffect(() => {
    carregar()
  }, [carregar])

  // Trocar de residente, de período ou de atalho fecha o detalhe aberto: a
  // lista na tela sempre corresponde ao filtro que está na tela.
  function aplicarAtalho(a) {
    setAtalho(a.id)
    setPeriodo(a.periodo())
    setCategoria(null)
  }

  function mudarData(campo, valor) {
    if (!valor) return
    setAtalho(null)
    setPeriodo((p) => ({ ...p, [campo]: valor }))
    setCategoria(null)
  }

  function mudarResidente(valor) {
    setIdosoId(valor)
    setCategoria(null)
  }

  const diaUnico = periodo.inicio === periodo.fim
  const rotuloPeriodo = diaUnico
    ? dataCurta(periodo.inicio)
    : `${dataCurta(periodo.inicio)} a ${dataCurta(periodo.fim)}`

  return (
    <>
      <section className="secao">
        <h2>Adesão à medicação</h2>
        <div className="card">
          <div className="atalhos-periodo">
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
          <div className="formulario">
            <div className="periodo-datas">
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
            <label>
              Residente
              <select value={idosoId} onChange={(e) => mudarResidente(e.target.value)}>
                <option value="">Toda a casa</option>
                {residentes.map((r) => (
                  <option key={r.id} value={r.id}>
                    {r.nome}
                    {r.ativo ? '' : ' — inativo'}
                  </option>
                ))}
              </select>
            </label>
          </div>
        </div>
      </section>

      <section className="secao">
        {erro && (
          <div className="card">
            <p className="aviso aviso-erro">{erro}</p>
          </div>
        )}
        {!erro && dados === null && (
          <div className="card">
            <span className="status status-carregando">Calculando…</span>
          </div>
        )}
        {!erro && dados !== null && categoria === null && (
          <ResultadoAdesao
            dados={dados}
            rotuloPeriodo={rotuloPeriodo}
            temResidente={Boolean(idosoId)}
            onAbrir={setCategoria}
          />
        )}
        {!erro && dados !== null && categoria !== null && (
          <DetalheAdesao
            categoria={categoria}
            periodo={periodo}
            idosoId={idosoId}
            rotuloPeriodo={rotuloPeriodo}
            onVoltar={() => setCategoria(null)}
          />
        )}
      </section>
    </>
  )
}

function ResultadoAdesao({ dados, rotuloPeriodo, temResidente, onAbrir }) {
  const total = dados.total_planejadas
  const pendentes = dados.pendentes
  const devidas = dados.devidas_ate_agora

  if (total === 0 && pendentes === 0) {
    return (
      <div className="card">
        <p>
          Nenhuma dose de ronda em {rotuloPeriodo}.
          {dados.sos > 0 &&
            ` Houve ${fmtQtd(dados.sos)} dose${dados.sos > 1 ? 's' : ''} SOS no período.`}
        </p>
      </div>
    )
  }

  return (
    <div className="card">
      <p className="adesao-contexto">
        {pendentes > 0
          ? `${fmtQtd(total)} de ${fmtQtd(devidas)} doses devidas até agora já têm tratativa em ${rotuloPeriodo}.`
          : `${fmtQtd(total)} dose${total === 1 ? ' planejada' : 's planejadas'} em ${rotuloPeriodo}.`}
      </p>

      {/* Com residente escolhido cada categoria abre a lista das doses que a
          compõem (DEC-048). Na visão da casa a linha fica estática: uma lista
          de todas as doses de onze pessoas não ajuda a agir sobre nenhuma. */}
      {CATEGORIAS.map(({ chave, rotulo, cor }) => {
        const { qtd, pct } = dados[chave]
        const conteudo = (
          <>
            <div className="adesao-linha">
              <span>
                {rotulo} <span className="adesao-qtd">({fmtQtd(qtd)} de {fmtQtd(total)})</span>
              </span>
              <span className="adesao-pct">
                {fmtPct(pct)}
                {temResidente && <span className="adesao-seta"> ›</span>}
              </span>
            </div>
            <div className="adesao-barra">
              <div
                className="adesao-barra-preenchida"
                style={{ width: `${pct ?? 0}%`, background: cor }}
              />
            </div>
          </>
        )
        // Todas as cinco abrem, inclusive com zero: a lista vazia é resposta
        // ("nenhuma dose nesta categoria"), não um beco.
        if (!temResidente) return <div key={chave}>{conteudo}</div>
        return (
          <button key={chave} type="button" className="adesao-categoria" onClick={() => onAbrir(chave)}>
            {conteudo}
          </button>
        )
      })}

      {!temResidente && (
        <p className="adesao-legenda">
          Selecione um residente para ver quais doses formam cada número.
        </p>
      )}

      {dados.nao_apurada.qtd > 0 && (
        <p className="adesao-legenda">
          &ldquo;Pendente (não apurado)&rdquo;: doses de períodos sem turno aberto,
          encerradas em lote na tela de pendências — não se confirmou se foram
          dadas ou não.
        </p>
      )}

      {/* SOS em bloco próprio, com o mesmo layout de linha das categorias
          (BUG-006): rótulo à esquerda, número à direita onde os olhos já
          procuram o percentual, seta na mesma coluna das outras cinco. Não vira
          categoria porque não tem denominador — logo, sem percentual e sem
          barra (DEC-030). Sem residente o bloco continua aparecendo: some
          apenas a seta e o clique (DEC-048). */}
      <div className="adesao-sos-bloco">
        {temResidente ? (
          <button type="button" className="adesao-categoria" onClick={() => onAbrir('sos')}>
            <LinhaSos qtd={dados.sos} comSeta />
          </button>
        ) : (
          <LinhaSos qtd={dados.sos} />
        )}
        {/* Fora da área clicável: é explicação, não alvo de toque. */}
        <p className="adesao-legenda">
          Contagem à parte — dose avulsa não tem horário planejado e fica fora dos
          percentuais.
        </p>
      </div>

      {/* Por último de propósito: alerta acionável fecha o card, onde tem mais
          chance de ser lido e lembrado. */}
      {pendentes > 0 && (
        <p className="aviso aviso-alerta">
          {fmtQtd(pendentes)} dose{pendentes > 1 ? 's' : ''} do turno aberto ainda sem
          tratativa — fora dos percentuais até {pendentes > 1 ? 'serem registradas' : 'ser registrada'}.
        </p>
      )}
    </div>
  )
}

function LinhaSos({ qtd, comSeta = false }) {
  return (
    <div className="adesao-linha">
      <span>Doses SOS no período</span>
      <span className="adesao-pct">
        {fmtQtd(qtd)}
        {comSeta && <span className="adesao-seta"> ›</span>}
      </span>
    </div>
  )
}

// Extrato de adesão (DEC-048): a lista das doses que formam UM número do
// relatório. Vem da RPC `detalhe_adesao`, que lê a mesma `fn_doses_adesao` do
// relatório — por construção, o que se lista aqui é o que se conta lá. Nenhum
// cálculo no cliente: só formatação.
function DetalheAdesao({ categoria, periodo, idosoId, rotuloPeriodo, onVoltar }) {
  const [dados, setDados] = useState(null)
  const [erro, setErro] = useState(null)

  useEffect(() => {
    let cancelado = false
    setDados(null)
    setErro(null)
    supabase
      .rpc('detalhe_adesao', {
        p_inicio: periodo.inicio,
        p_fim: periodo.fim,
        p_idoso_id: idosoId,
        p_categoria: categoria
      })
      .then(({ data, error }) => {
        if (cancelado) return
        if (error) return setErro('Falha de conexão. Tente novamente.')
        if (!data.ok) return setErro(mensagemErro(data))
        setDados(data)
      })
    return () => {
      cancelado = true
    }
  }, [categoria, periodo, idosoId])

  return (
    <div className="card">
      <button type="button" className="botao-voltar" onClick={onVoltar}>
        ← Adesão
      </button>
      <div className="gestao-cabecalho">
        <h2>{ROTULO_CATEGORIA[categoria]}</h2>
      </div>
      <p className="adesao-contexto">
        {rotuloPeriodo}
        {dados && ` · ${fmtQtd(dados.total)} dose${dados.total === 1 ? '' : 's'}`}
      </p>

      {erro && <p className="aviso aviso-erro">{erro}</p>}
      {!erro && dados === null && <span className="status status-carregando">Carregando…</span>}
      {!erro && dados !== null && dados.doses.length === 0 && (
        <p>Nenhuma dose nesta categoria no período.</p>
      )}
      {!erro && dados !== null && dados.truncado && (
        <p className="aviso aviso-alerta">
          Mostrando as {fmtQtd(dados.limite)} mais recentes de {fmtQtd(dados.total)}. Escolha um
          período menor para ver as demais.
        </p>
      )}
      {!erro && dados !== null && dados.doses.length > 0 && (
        <ul className="lista-extrato">
          {dados.doses.map((d) => (
            <li key={d.administracao_id} className="extrato-linha">
              <span className="extrato-info">
                <span className="extrato-tipo">
                  {[d.nome_medicamento, d.dosagem].filter(Boolean).join(' ')}
                  {d.eh_da_casa && <span className="chip chip-casa"> Da casa</span>}
                </span>
                <span className="extrato-detalhe">{linhaQuando(categoria, d)}</span>
                {categoria === 'nao_apurada' && (
                  <span className="extrato-detalhe">
                    Encerrada em lote nas pendências entre turnos — não se apurou se foi dada.
                  </span>
                )}
                {d.observacao && <span className="extrato-detalhe">{d.observacao}</span>}
              </span>
              <span className="extrato-qtd">{fmtQtd(d.qtd)}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

// Quando a dose aconteceu, por categoria. A atrasada é a única que mostra os
// DOIS instantes: o buraco entre previsto e registrado é a informação.
function linhaQuando(categoria, d) {
  const cuidadora = d.cuidador_nome ? ` · ${d.cuidador_nome}` : ''
  if (categoria === 'sos') return `${dataHoraLocal(d.registrado_em)}${cuidadora}`
  if (categoria === 'atrasada') {
    return `previsto ${dataHoraLocal(d.prevista_em)}, registrado ${horaLocal(d.registrado_em)}${cuidadora}`
  }
  if (categoria === 'nao_apurada') return dataHoraLocal(d.prevista_em)
  return `${dataHoraLocal(d.prevista_em)}${cuidadora}`
}
