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
  // Encerramento do turno (Sessão #10): o botão vive no cabeçalho, então a
  // chamada de fechar_turno vive aqui — a cuidadora encerra de qualquer aba.
  // A LÓGICA de fechamento não mudou: é a mesma RPC, com a mesma recusa.
  const [fechando, setFechando] = useState(false)
  const [avisoFechamento, setAvisoFechamento] = useState(null)
  // Incrementado quando o fechamento é recusado: faz a Ronda reler a agenda,
  // para a cuidadora ver na hora o que o banco disse que falta tratar.
  const [recargaRonda, setRecargaRonda] = useState(0)

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

  // Troca de aba pelo menu: limpa o aviso de fechamento para não deixar tarja
  // vermelha velha na tela depois que a cuidadora já foi resolver o que faltava.
  function irPara(tela) {
    setAvisoFechamento(null)
    setTelaTurno(tela)
  }

  // Encerrar turno (Sessão #10) — mesma `fechar_turno` de sempre: quem recusa
  // com dose sem tratativa é o banco (DEC-010/DEC-022/DEC-033), não a tela.
  // A única novidade é de navegação: como o botão agora é alcançável de
  // Estoque e Adesão, a recusa LEVA a cuidadora até a fila que a bloqueou, em
  // vez de deixá-la numa aba onde não há o que resolver.
  async function encerrarTurno() {
    setFechando(true)
    setAvisoFechamento(null)
    const { data, error } = await supabase.rpc('fechar_turno', { p_turno_id: turno.id })
    setFechando(false)
    if (error) {
      setAvisoFechamento('Falha ao encerrar o turno. Tente novamente.')
      return
    }
    if (data.ok) {
      setTurno(null)
      setTelaTurno('ronda')
      return
    }
    if (data.erro === 'doses_pendentes') {
      // O bloqueio pode vir de duas filas (Sessão #5.5): doses deste turno
      // (ronda) e pendências de períodos sem turno aberto (tela própria).
      const partes = []
      if (data.total_ronda > 0) {
        partes.push(`${data.total_ronda} dose(s) deste turno sem tratativa (na Ronda)`)
      }
      if (data.total_entre_turnos > 0) {
        partes.push(
          `${data.total_entre_turnos} pendência(s) de períodos sem turno aberto ("Pendências entre turnos")`
        )
      }
      setAvisoFechamento(
        `Ainda há ${partes.join(' e ')}. Resolva tudo antes de encerrar o turno.`
      )
      // Leva para onde está o que resolver: a ronda tem prioridade porque é o
      // trabalho do turno corrente; se o bloqueio é só da outra fila, abre ela.
      setTelaTurno(data.total_ronda > 0 ? 'ronda' : 'pendencias')
      setRecargaRonda((n) => n + 1)
      carregarPendencias()
    } else {
      setAvisoFechamento('Não foi possível encerrar o turno.')
    }
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
    // Recarrega em vez de aproveitar o turno devolvido por abrir_turno: aquele
    // payload não tem eh_admin (e não deve ter — é a RPC do PIN, não a da UI).
    // Assim o objeto do turno é montado num lugar só e a home logo após assumir
    // o turno é idêntica à de depois de recarregar a página.
    conteudo = <AssumirTurno onTurnoAberto={carregarTurnoAberto} />
  } else if (telaTurno === 'pendencias') {
    conteudo = (
      <>
        <button
          type="button"
          className="botao-voltar"
          onClick={() => irPara('ronda')}
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
            onClick={() => irPara('ronda')}
          >
            Ronda
          </button>
          {/* Adesão é aba de operação, sem PIN de gestão (DEC-031). */}
          <button
            type="button"
            className={`aba ${telaTurno === 'adesao' ? 'aba-ativa' : ''}`}
            onClick={() => irPara('adesao')}
          >
            Adesão
          </button>
          <button
            type="button"
            className={`aba ${telaTurno === 'estoque' ? 'aba-ativa' : ''}`}
            onClick={() => irPara('estoque')}
          >
            Estoque
          </button>
        </div>
        {telaTurno === 'ronda' && <Ronda turno={turno} recarga={recargaRonda} />}
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

  // "Encerrar turno" (Sessão #10) fica no cabeçalho, e não mais dentro da aba
  // Ronda: navegando por Estoque ou Adesão, a cuidadora tentava encerrar e
  // precisava voltar à Ronda primeiro — atrito observado no uso real.
  const mostrarEncerrar = !!turno && !gestao

  return (
    <div className="app">
      <header className="app-header">
        <div className="app-header-topo">
          <div className="app-header-titulo">
            <h1>Sereníssima</h1>
            <p>Gestão de medicação</p>
            {turno && !gestao && (
              <p className="app-header-cuidadora">Turno de {turno.cuidador_nome}</p>
            )}
          </div>
          {/* Ação de SAÍDA: destacada e separada dos botões de gestão logo
              abaixo, que abrem áreas. Não competem visualmente. */}
          {mostrarEncerrar && (
            <button
              type="button"
              className="botao-encerrar-turno"
              onClick={encerrarTurno}
              disabled={fechando}
            >
              {fechando ? 'Encerrando…' : 'Encerrar turno'}
            </button>
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
      <main className="app-main">
        {/* Recusa do fechamento: fica logo abaixo do cabeçalho, junto da tela
            para onde a cuidadora acabou de ser levada. */}
        {avisoFechamento && <p className="aviso aviso-erro aviso-fechamento">{avisoFechamento}</p>}
        {conteudo}
      </main>
    </div>
  )
}
