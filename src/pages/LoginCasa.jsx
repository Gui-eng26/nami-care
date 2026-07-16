import { useState } from 'react'
import { supabase } from '../lib/supabase.js'

// Login do usuário Supabase único da casa (DEC-019). Feito uma única vez no
// celular compartilhado; a identificação de quem opera é pelo PIN do turno.
export default function LoginCasa() {
  const [email, setEmail] = useState('')
  const [senha, setSenha] = useState('')
  const [erro, setErro] = useState(null)
  const [enviando, setEnviando] = useState(false)

  async function entrar(evento) {
    evento.preventDefault()
    setEnviando(true)
    setErro(null)
    const { error } = await supabase.auth.signInWithPassword({ email, password: senha })
    if (error) {
      setErro('E-mail ou senha inválidos.')
      setEnviando(false)
    }
    // Sucesso: o onAuthStateChange no App troca a tela.
  }

  return (
    <div className="card">
      <h2>Entrar — conta da casa</h2>
      <p>
        Use as credenciais da casa de repouso. Este login é feito uma única vez
        neste aparelho; a troca de cuidador é pelo PIN do turno.
      </p>
      <form className="formulario" onSubmit={entrar}>
        <label>
          E-mail
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            autoComplete="username"
            required
          />
        </label>
        <label>
          Senha
          <input
            type="password"
            value={senha}
            onChange={(e) => setSenha(e.target.value)}
            autoComplete="current-password"
            required
          />
        </label>
        {erro && <p className="aviso aviso-erro">{erro}</p>}
        <button type="submit" className="botao-primario" disabled={enviando}>
          {enviando ? 'Entrando…' : 'Entrar'}
        </button>
      </form>
    </div>
  )
}
