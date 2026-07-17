import { useCallback, useEffect, useState } from 'react'
import { supabase } from './lib/supabase.js'
import LoginCasa from './pages/LoginCasa.jsx'
import AssumirTurno from './pages/AssumirTurno.jsx'
import Ronda from './pages/Ronda.jsx'
import Gestao from './pages/Gestao.jsx'

// Estados: sessão do usuário Supabase da casa (DEC-019) e turno aberto (PIN).
// undefined = ainda carregando; null = não existe.
// gestao: área de cadastros, protegida por PIN de administradora (DEC-024) —
// acessível com ou sem turno aberto.
export default function App() {
  const [sessao, setSessao] = useState(undefined)
  const [turno, setTurno] = useState(undefined)
  const [gestao, setGestao] = useState(false)

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
    conteudo = <Ronda turno={turno} onTurnoFechado={() => setTurno(null)} />
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
