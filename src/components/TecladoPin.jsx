import { useState } from 'react'

const TECLAS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'apagar', '0', 'ok']
const PIN_MIN = 4
const PIN_MAX = 6

// Teclado numérico de PIN. onConfirmar(pin) é async; o campo é limpo após
// cada tentativa (sucesso troca de tela; falha exibe o aviso do chamador).
export default function TecladoPin({ onConfirmar, aviso }) {
  const [pin, setPin] = useState('')
  const [ocupado, setOcupado] = useState(false)

  async function tocar(tecla) {
    if (ocupado) return
    if (tecla === 'apagar') {
      setPin(pin.slice(0, -1))
      return
    }
    if (tecla === 'ok') {
      if (pin.length < PIN_MIN) return
      setOcupado(true)
      await onConfirmar(pin)
      setPin('')
      setOcupado(false)
      return
    }
    if (pin.length < PIN_MAX) setPin(pin + tecla)
  }

  return (
    <div className="teclado-pin">
      <div className="pin-pontos" aria-label={`PIN com ${pin.length} dígitos`}>
        {Array.from({ length: PIN_MAX }).map((_, i) => (
          <span key={i} className={i < pin.length ? 'pin-ponto preenchido' : 'pin-ponto'} />
        ))}
      </div>
      {aviso && <p className="aviso aviso-erro">{aviso}</p>}
      <div className="teclado-grade">
        {TECLAS.map((tecla) => (
          <button
            key={tecla}
            type="button"
            className={
              tecla === 'ok' ? 'tecla tecla-ok' : tecla === 'apagar' ? 'tecla tecla-apagar' : 'tecla'
            }
            disabled={ocupado || (tecla === 'ok' && pin.length < PIN_MIN)}
            onClick={() => tocar(tecla)}
          >
            {tecla === 'apagar' ? '⌫' : tecla === 'ok' ? (ocupado ? '…' : 'OK') : tecla}
          </button>
        ))}
      </div>
    </div>
  )
}
