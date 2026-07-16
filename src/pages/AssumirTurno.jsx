import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase.js'
import TecladoPin from '../components/TecladoPin.jsx'

// Assumir turno no dispositivo compartilhado (DEC-002/DEC-019): o cuidador
// escolhe o próprio nome e confirma com PIN. A verificação é 100% server-side
// (RPC abrir_turno — DEC-020) com rate limit (DEC-021).
export default function AssumirTurno({ onTurnoAberto }) {
  const [cuidadores, setCuidadores] = useState(null)
  const [selecionado, setSelecionado] = useState(null)
  const [aviso, setAviso] = useState(null)

  useEffect(() => {
    supabase
      .from('cuidadores')
      .select('id, nome')
      .eq('ativo', true)
      .order('nome')
      .then(({ data, error }) => setCuidadores(error ? [] : data))
  }, [])

  async function confirmarPin(pin) {
    setAviso(null)
    const { data, error } = await supabase.rpc('abrir_turno', {
      p_cuidador_id: selecionado.id,
      p_pin: pin
    })
    if (error) {
      setAviso('Falha ao verificar o PIN. Verifique a conexão e tente novamente.')
      return
    }
    if (data.ok) {
      onTurnoAberto(data.turno)
      return
    }
    if (data.erro === 'pin_incorreto') {
      setAviso(
        data.tentativas_restantes > 0
          ? `PIN incorreto. ${data.tentativas_restantes} tentativa(s) antes do bloqueio.`
          : 'PIN incorreto. Próxima tentativa só após o desbloqueio.'
      )
    } else if (data.erro === 'pin_bloqueado') {
      const hora = new Date(data.desbloqueia_em).toLocaleTimeString('pt-BR', {
        hour: '2-digit',
        minute: '2-digit',
        timeZone: 'America/Sao_Paulo'
      })
      setAviso(`Muitas tentativas erradas. Bloqueado até ${hora}.`)
    } else if (data.erro === 'turno_aberto_outro_cuidador') {
      setAviso('Outro cuidador abriu um turno agora há pouco. Recarregue a tela.')
    } else {
      setAviso('Não foi possível abrir o turno.')
    }
  }

  if (cuidadores === null) {
    return (
      <div className="card">
        <span className="status status-carregando">Carregando cuidadores…</span>
      </div>
    )
  }

  if (!selecionado) {
    return (
      <div className="card">
        <h2>Quem está assumindo o turno?</h2>
        <div className="lista-cuidadores">
          {cuidadores.map((c) => (
            <button key={c.id} type="button" className="botao-cuidador" onClick={() => setSelecionado(c)}>
              {c.nome}
            </button>
          ))}
          {cuidadores.length === 0 && <p>Nenhum cuidador ativo cadastrado.</p>}
        </div>
      </div>
    )
  }

  return (
    <div className="card">
      <button
        type="button"
        className="botao-voltar"
        onClick={() => {
          setSelecionado(null)
          setAviso(null)
        }}
      >
        ← Trocar cuidador
      </button>
      <h2>PIN de {selecionado.nome}</h2>
      <TecladoPin onConfirmar={confirmarPin} aviso={aviso} />
    </div>
  )
}
