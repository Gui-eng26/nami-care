import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase.js'
import { mensagemErro } from '../lib/erros.js'
import { fmtQtd } from '../lib/formato.js'

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

  function aplicarAtalho(a) {
    setAtalho(a.id)
    setPeriodo(a.periodo())
  }

  function mudarData(campo, valor) {
    if (!valor) return
    setAtalho(null)
    setPeriodo((p) => ({ ...p, [campo]: valor }))
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
          <div className="formulario">
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
            <label>
              Residente
              <select value={idosoId} onChange={(e) => setIdosoId(e.target.value)}>
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
        {!erro && dados !== null && <ResultadoAdesao dados={dados} rotuloPeriodo={rotuloPeriodo} />}
      </section>
    </>
  )
}

function ResultadoAdesao({ dados, rotuloPeriodo }) {
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

      {CATEGORIAS.map(({ chave, rotulo, cor }) => {
        const { qtd, pct } = dados[chave]
        return (
          <div key={chave}>
            <div className="adesao-linha">
              <span>
                {rotulo} <span className="adesao-qtd">({fmtQtd(qtd)} de {fmtQtd(total)})</span>
              </span>
              <span className="adesao-pct">{fmtPct(pct)}</span>
            </div>
            <div className="adesao-barra">
              <div
                className="adesao-barra-preenchida"
                style={{ width: `${pct ?? 0}%`, background: cor }}
              />
            </div>
          </div>
        )
      })}

      {dados.nao_apurada.qtd > 0 && (
        <p className="adesao-legenda">
          &ldquo;Pendente (não apurado)&rdquo;: doses de períodos sem turno aberto,
          encerradas em lote na tela de pendências — não se confirmou se foram
          dadas ou não.
        </p>
      )}

      {pendentes > 0 && (
        <p className="aviso aviso-alerta">
          {fmtQtd(pendentes)} dose{pendentes > 1 ? 's' : ''} do turno aberto ainda sem
          tratativa — fora dos percentuais até {pendentes > 1 ? 'serem registradas' : 'ser registrada'}.
        </p>
      )}

      <p className="adesao-sos">
        Doses SOS no período: <strong>{fmtQtd(dados.sos)}</strong>
        <span className="adesao-sos-nota">
          {' '}
          — contagem à parte; dose avulsa não tem horário planejado e fica fora dos
          percentuais.
        </span>
      </p>
    </div>
  )
}
