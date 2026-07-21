import { useCallback, useEffect, useState } from 'react'
import { supabase } from './lib/supabase.js'
import LoginCasa from './pages/LoginCasa.jsx'
import AssumirTurno from './pages/AssumirTurno.jsx'
import Ronda from './pages/Ronda.jsx'
import Estoque from './pages/Estoque.jsx'
import Adesao from './pages/Adesao.jsx'
import PendenciasEntreTurnos from './pages/PendenciasEntreTurnos.jsx'
import GestaoResidentes from './pages/GestaoResidentes.jsx'
import Gestao from './pages/Gestao.jsx'

// Estados: sessão do usuário Supabase da casa (DEC-019) e turno aberto (PIN).
// undefined = ainda carregando; null = não existe.
//
// gestao: null | 'residentes' | 'equipe' (DEC-038).
//   'residentes' — cadastros de residentes, medicamentos e prescrições: aberta
//     a QUALQUER cuidadora com turno aberto, sem PIN de administradora. A
//     autorização real é do banco (fn_cuidador_do_turno em cada RPC).
//   'equipe' — quem tem acesso ao sistema: segue sob PIN de administradora
//     (DEC-024), revalidado no banco a cada RPC. O botão só aparece para a
//     admin, mas quem barra é a RPC — esconder botão nunca é segurança.
export default function App() {
  const [sessao, setSessao] = useState(undefined)
  const [turno, setTurno] = useState(undefined)
  const [gestao, setGestao] = useState(null)
  // Com turno aberto, a operação tem três abas: ronda, adesão e estoque.
  const [telaTurno, setTelaTurno] = useState('ronda')
  // Doses vencidas em períodos sem turno aberto (Sessão #5.5 — BUG-002):
  // contagem da faixa de alerta, que só existe enquanto houver pendência.
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

  // eh_admin vem junto com o turno só para decidir a UI (mostrar ou não o botão
  // de gestão de equipe) — o enforcement continua no banco.
  const carregarTurnoAberto = useCallback(async () => {
    const { data, error } = await supabase
      .from('turnos')
      .select('id, inicio, cuidador_id, cuidadores (nome, eh_admin)')
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
            eh_admin: data.cuidadores.eh_admin,
            inicio: data.inicio
          }
        : null
    )
  }, [])

  useEffect(() => {
    if (sessao) carregarTurnoAberto()
    else if (sessao === null) {
      setTurno(undefined)
      setGestao(null)
    }
  }, [sessao, carregarTurnoAberto])

  useEffect(() => {
    if (turno) carregarPendencias()
  }, [turno, carregarPendencias])

  function sairDaGestao() {
    setGestao(null)
    carregarTurnoAberto()
  }

  let conteudo
  if (sessao === undefined || (sessao && turno === undefined)) {
    conteudo = (
      <div className="card">
        <span className="status status-carregando">Carregando…</span>
      </div>
    )
  } else if (!sessao) {
    conteudo = <LoginCasa />
  } else if (gestao === 'residentes') {
    conteudo = <GestaoResidentes />
  } else if (gestao === 'equipe') {
    conteudo = <Gestao onSair={sairDaGestao} />
  } else if (!turno) {
    conteudo = <AssumirTurno onTurnoAberto={setTurno} />
  } else if (telaTurno === 'pendencias') {
    conteudo = (
      <>
        <button
          type="button"
          className="botao-voltar"
          onClick={() => setTelaTurno('ronda')}
        >
          ← Voltar
        </button>
        <PendenciasEntreTurnos turno={turno} onMudanca={carregarPendencias} />
      </>
    )
  } else {
    conteudo = (
      <>
        {/* Pendências entre turnos (Sessão #5.5): faixa de alerta que existe
            apenas enquanto há pendência — some sozinha quando zera. */}
        {pendencias > 0 && (
          <button
            type="button"
            className="faixa-alerta"
            onClick={() => setTelaTurno('pendencias')}
          >
            <span>Pendências entre turnos ({pendencias})</span>
            <span aria-hidden="true">›</span>
          </button>
        )}
        <div className="abas">
          <button
            type="button"
            className={`aba ${telaTurno === 'ronda' ? 'aba-ativa' : ''}`}
            onClick={() => setTelaTurno('ronda')}
          >
            Ronda
          </button>
          {/* Adesão é aba de operação, sem PIN de gestão (DEC-031). */}
          <button
            type="button"
            className={`aba ${telaTurno === 'adesao' ? 'aba-ativa' : ''}`}
            onClick={() => setTelaTurno('adesao')}
          >
            Adesão
          </button>
          <button
            type="button"
            className={`aba ${telaTurno === 'estoque' ? 'aba-ativa' : ''}`}
            onClick={() => setTelaTurno('estoque')}
          >
            Estoque
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
        {telaTurno === 'adesao' && <Adesao />}
        {telaTurno === 'estoque' && <Estoque />}
      </>
    )
  }

  // Gestão de residentes exige turno aberto (é a autorização da DEC-038).
  // Gestão de equipe é da administradora — e continua alcançável antes do
  // turno, para a casa conseguir cadastrar a primeira cuidadora.
  const mostrarBotoesGestao = sessao && turno !== undefined && !gestao
  const podeResidentes = !!turno
  const podeEquipe = !turno || turno.eh_admin

  return (
    <div className="app">
      <header className="app-header">
        <div className="app-header-titulo">
          <h1>Sereníssima</h1>
          <p>Gestão de medicação</p>
          {turno && !gestao && (
            <p className="app-header-cuidadora">Turno de {turno.cuidador_nome}</p>
          )}
        </div>
        <div className="app-header-acoes">
          {gestao && (
            <button type="button" className="botao-header" onClick={sairDaGestao}>
              ‹ Sair da gestão
            </button>
          )}
          {mostrarBotoesGestao && podeResidentes && (
            <button
              type="button"
              className="botao-header"
              onClick={() => setGestao('residentes')}
            >
              Gestão residentes
            </button>
          )}
          {mostrarBotoesGestao && podeEquipe && (
            <button
              type="button"
              className="botao-header"
              onClick={() => setGestao('equipe')}
            >
              Gestão equipe
            </button>
          )}
        </div>
      </header>
      <main className="app-main">{conteudo}</main>
    </div>
  )
}
