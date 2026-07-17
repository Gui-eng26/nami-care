import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase.js'
import { mensagemErro } from '../lib/erros.js'
import TecladoPin from '../components/TecladoPin.jsx'

// Assumir turno no dispositivo compartilhado (DEC-002/DEC-019): o cuidador
// escolhe o próprio nome e confirma com PIN. A verificação é 100% server-side
// (RPC abrir_turno — DEC-020) com rate limit (DEC-021).
export default function AssumirTurno({ onTurnoAberto }) {
  const [cuidadores, setCuidadores] = useState(null)
  const [selecionado, setSelecionado] = useState(null)
  const [aviso, setAviso] = useState(null)
  const [trocandoPin, setTrocandoPin] = useState(false)

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
    if (data.erro === 'turno_aberto_outro_cuidador') {
      setAviso('Outro cuidador abriu um turno agora há pouco. Recarregue a tela.')
    } else {
      setAviso(mensagemErro(data))
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

  if (trocandoPin) {
    return (
      <TrocarPin
        cuidador={selecionado}
        onVoltar={() => setTrocandoPin(false)}
      />
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
      <div className="acoes-item">
        <button
          type="button"
          className="botao-mini"
          onClick={() => {
            setAviso(null)
            setTrocandoPin(true)
          }}
        >
          Trocar meu PIN
        </button>
      </div>
    </div>
  )
}

// Troca de PIN self-service (DEC-025): exige o PIN atual, verificado no banco
// com o mesmo rate limit do login. Esquecimento = administradora redefine na
// área de gestão.
function TrocarPin({ cuidador, onVoltar }) {
  const [pinAtual, setPinAtual] = useState('')
  const [pinNovo, setPinNovo] = useState('')
  const [aviso, setAviso] = useState(null)
  const [ocupado, setOcupado] = useState(false)

  async function salvar(evento) {
    evento.preventDefault()
    setOcupado(true)
    setAviso(null)
    const { data, error } = await supabase.rpc('trocar_pin', {
      p_cuidador_id: cuidador.id,
      p_pin_atual: pinAtual,
      p_pin_novo: pinNovo
    })
    setOcupado(false)
    if (error) {
      setAviso({ tipo: 'erro', texto: 'Falha de conexão. Tente novamente.' })
      return
    }
    if (!data.ok) {
      setAviso({ tipo: 'erro', texto: mensagemErro(data) })
      return
    }
    setPinAtual('')
    setPinNovo('')
    setAviso({ tipo: 'ok', texto: 'PIN trocado. Use o novo PIN para assumir o turno.' })
  }

  return (
    <div className="card">
      <button type="button" className="botao-voltar" onClick={onVoltar}>
        ← Voltar
      </button>
      <h2>Trocar o PIN de {cuidador.nome}</h2>
      <p>Se esqueceu o PIN atual, peça à administradora para redefinir na Gestão.</p>
      <form className="formulario" onSubmit={salvar}>
        <label>
          PIN atual
          <input
            type="password"
            inputMode="numeric"
            pattern="[0-9]{4,6}"
            minLength={4}
            maxLength={6}
            value={pinAtual}
            onChange={(e) => setPinAtual(e.target.value.replace(/\D/g, ''))}
            required
          />
        </label>
        <label>
          Novo PIN (4 a 6 dígitos)
          <input
            type="password"
            inputMode="numeric"
            pattern="[0-9]{4,6}"
            minLength={4}
            maxLength={6}
            value={pinNovo}
            onChange={(e) => setPinNovo(e.target.value.replace(/\D/g, ''))}
            required
          />
        </label>
        {aviso && (
          <p className={`aviso ${aviso.tipo === 'ok' ? 'aviso-ok' : 'aviso-erro'}`}>
            {aviso.texto}
          </p>
        )}
        <button type="submit" className="botao-primario" disabled={ocupado}>
          {ocupado ? 'Trocando…' : 'Trocar PIN'}
        </button>
      </form>
    </div>
  )
}
