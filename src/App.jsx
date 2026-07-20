import { useCallback, useEffect, useState } from 'react'
import { supabase } from './lib/supabase.js'
import LoginCasa from './pages/LoginCasa.jsx'
import AssumirTurno from './pages/AssumirTurno.jsx'
import Ronda from './pages/Ronda.jsx'
import Estoque from './pages/Estoque.jsx'
import Adesao from './pages/Adesao.jsx'
import PendenciasEntreTurnos from './pages/PendenciasEntreTurnos.jsx'
import Gestao from './pages/Gestao.jsx'

// Estados: sessão do usuário Supabase da casa (DEC-019) e turno aberto (PIN).
// undefined = ainda carregando; null = não existe.
// gestao: área de cadastros, protegida por PIN de administradora (DEC-024) —
// acessível com ou sem turno aberto.
export default function App() {
  const [sessao, setSessao] = useState(undefined)
  const [turno, setTurno] = useState(undefined)
  const [gestao, setGestao] = useState(false)
  // Com turno aberto, a operação tem duas telas: a ronda e o estoque (Sessão #4).
  const [telaTurno, setTelaTurno] = useState('ronda')
  // Doses vencidas em períodos sem turno aberto (Sessão #5.5 — BUG-002):
  // contagem para a aba, que fica em alerta enquanto houver pendência.
  const [pendencias, setPendencias] = useState(0)

  const carregarPendencias = useCallback(async () => {
    const { data, error } = await supabase.rpc('listar_pendencias_entre_turnos')
    if (!error && data?.ok) setPendencias(data.total)
  }, [])

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSessao(data.session))
    const { data: assinatura } = supabase.auth.onAuthStateChange((_evento, s) => setSessao(s))
    return () => assinatura.subscription.unsubscribe()
  }, [])

  const carregarTurnoAberto = useCallback(async () => {
    const { data, error } = await supabase
      .from('turnos')
      .select('id, inicio, cuidador_id, cuidadores (nome)')
      .is('fim', null)
      .maybeSingle()
    if (error) {
      setTurno(null)
      return
    }
    setTurno(
      data
        ? {
            id: data.id,
            cuidador_id: data.cuidador_id,
            cuidador_nome: data.cuidadores.nome,
            inicio: data.inicio
          }
        : null
    )
  }, [])

  useEffect(() => {
    if (sessao) carregarTurnoAberto()
    else if (sessao === null) {
      setTurno(undefined)
      setGestao(false)
    }
  }, [sessao, carregarTurnoAberto])

  useEffect(() => {
    if (turno) carregarPendencias()
  }, [turno, carregarPendencias])

  let conteudo
  if (sessao === undefined || (sessao && turno === undefined)) {
    conteudo = (
      <div className="card">
        <span className="status status-carregando">Carregando…</span>
      </div>
    )
  } else if (!sessao) {
    conteudo = <LoginCasa />
  } else if (gestao) {
    conteudo = <Gestao onSair={() => { setGestao(false); carregarTurnoAberto() }} />
  } else if (!turno) {
    conteudo = <AssumirTurno onTurnoAberto={setTurno} />
  } else {
    conteudo = (
      <>
        <div className="abas">
          <button
            type="button"
            className={`aba ${telaTurno === 'ronda' ? 'aba-ativa' : ''}`}
            onClick={() => setTelaTurno('ronda')}
          >
            Ronda
          </button>
          <button
            type="button"
            className={`aba ${telaTurno === 'estoque' ? 'aba-ativa' : ''}`}
            onClick={() => setTelaTurno('estoque')}
          >
            Estoque
          </button>
          {/* Adesão é aba de operação, sem PIN de gestão (DEC-031). */}
          <button
            type="button"
            className={`aba ${telaTurno === 'adesao' ? 'aba-ativa' : ''}`}
            onClick={() => setTelaTurno('adesao')}
          >
            Adesão
          </button>
          {/* Pendências entre turnos (Sessão #5.5): a aba INTEIRA fica em
              alerta enquanto houver pendência; neutra quando não há. */}
          <button
            type="button"
            className={`aba aba-pendencias ${telaTurno === 'pendencias' ? 'aba-ativa' : ''} ${
              pendencias > 0 ? 'aba-alerta' : ''
            }`}
            onClick={() => setTelaTurno('pendencias')}
          >
            Pendências entre turnos{pendencias > 0 ? ` (${pendencias})` : ''}
          </button>
        </div>
        {telaTurno === 'ronda' && (
          <Ronda
            turno={turno}
            onTurnoFechado={() => {
              setTurno(null)
              setTelaTurno('ronda')
            }}
          />
        )}
        {telaTurno === 'estoque' && <Estoque />}
        {telaTurno === 'adesao' && <Adesao />}
        {telaTurno === 'pendencias' && (
          <PendenciasEntreTurnos turno={turno} onMudanca={carregarPendencias} />
        )}
      </>
    )
  }

  return (
    <div className="app">
      <header className="app-header">
        <div className="app-header-titulo">
          <h1>Sereníssima</h1>
          <p>Gestão de medicação</p>
        </div>
        <div className="app-header-acoes">
          {!gestao && turno && <span className="turno-badge">{turno.cuidador_nome}</span>}
          {sessao && turno !== undefined && (
            <button
              type="button"
              className="botao-header"
              onClick={() => {
                if (gestao) carregarTurnoAberto()
                setGestao(!gestao)
              }}
            >
              {gestao ? '‹ Sair da gestão' : 'Gestão'}
            </button>
          )}
        </div>
      </header>
      <main className="app-main">{conteudo}</main>
    </div>
  )
}
