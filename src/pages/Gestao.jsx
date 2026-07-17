import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase.js'
import { mensagemErro } from '../lib/erros.js'
import TecladoPin from '../components/TecladoPin.jsx'
import GestaoCuidadoras from './GestaoCuidadoras.jsx'
import GestaoResidentes from './GestaoResidentes.jsx'

// Área de gestão (DEC-024): entrada com PIN de administradora, validado no
// banco (RPC autorizar_gestao). A credencial fica só em memória e é reenviada
// a cada RPC de gestão — o servidor revalida tudo; a tela é apenas a porta.
export default function Gestao({ onSair }) {
  const [admins, setAdmins] = useState(null)
  const [selecionada, setSelecionada] = useState(null)
  const [aviso, setAviso] = useState(null)
  const [credencial, setCredencial] = useState(null)
  const [aba, setAba] = useState('residentes')

  useEffect(() => {
    supabase
      .from('cuidadores')
      .select('id, nome')
      .eq('ativo', true)
      .eq('eh_admin', true)
      .order('nome')
      .then(({ data, error }) => setAdmins(error ? [] : data))
  }, [])

  async function confirmarPin(pin) {
    setAviso(null)
    const { data, error } = await supabase.rpc('autorizar_gestao', {
      p_admin_id: selecionada.id,
      p_admin_pin: pin
    })
    if (error) {
      setAviso('Falha ao verificar o PIN. Verifique a conexão e tente novamente.')
      return
    }
    if (data.ok) {
      setCredencial({ id: selecionada.id, pin, nome: selecionada.nome })
      return
    }
    setAviso(mensagemErro(data))
  }

  if (!credencial) {
    if (admins === null) {
      return (
        <div className="card">
          <span className="status status-carregando">Carregando…</span>
        </div>
      )
    }
    if (!selecionada) {
      return (
        <div className="card">
          <h2>Gestão — quem é a administradora?</h2>
          <p>Cadastros de equipe, residentes e prescrições exigem PIN de administradora.</p>
          <div className="lista-cuidadores">
            {admins.map((a) => (
              <button
                key={a.id}
                type="button"
                className="botao-cuidador"
                onClick={() => setSelecionada(a)}
              >
                {a.nome}
              </button>
            ))}
            {admins.length === 0 && <p>Nenhuma administradora ativa cadastrada.</p>}
          </div>
          <div className="acoes-item">
            <button type="button" className="botao-mini" onClick={onSair}>
              ‹ Voltar
            </button>
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
            setSelecionada(null)
            setAviso(null)
          }}
        >
          ← Trocar administradora
        </button>
        <h2>PIN de {selecionada.nome}</h2>
        <TecladoPin onConfirmar={confirmarPin} aviso={aviso} />
      </div>
    )
  }

  return (
    <>
      <p className="gestao-admin-nota">
        Gestão como <strong>{credencial.nome}</strong> — cada alteração é
        autorizada e registrada no banco.
      </p>
      <div className="abas">
        <button
          type="button"
          className={`aba ${aba === 'residentes' ? 'aba-ativa' : ''}`}
          onClick={() => setAba('residentes')}
        >
          Residentes
        </button>
        <button
          type="button"
          className={`aba ${aba === 'equipe' ? 'aba-ativa' : ''}`}
          onClick={() => setAba('equipe')}
        >
          Equipe
        </button>
      </div>
      {aba === 'residentes' ? (
        <GestaoResidentes credencial={credencial} />
      ) : (
        <GestaoCuidadoras credencial={credencial} />
      )}
    </>
  )
}
