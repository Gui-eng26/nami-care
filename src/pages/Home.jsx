import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase.js'

// Esqueleto da Sessão #1: só verifica a conexão com o Supabase.
// Sem sessão autenticada, o RLS deve devolver zero linhas (e nenhum erro) —
// é isso que este componente confirma. Login por PIN chega na Sessão #2.
export default function Home() {
  const [estado, setEstado] = useState({ fase: 'carregando' })

  useEffect(() => {
    supabase
      .from('cuidadores')
      .select('id')
      .limit(1)
      .then(({ data, error }) => {
        if (error) setEstado({ fase: 'erro', mensagem: error.message })
        else setEstado({ fase: 'ok', linhasVisiveis: data.length })
      })
  }, [])

  return (
    <>
      <div className="card">
        <h2>Status do sistema</h2>
        {estado.fase === 'carregando' && (
          <span className="status status-carregando">Conectando ao Supabase…</span>
        )}
        {estado.fase === 'ok' && (
          <>
            <span className="status status-ok">Supabase conectado</span>
            <p>
              {estado.linhasVisiveis === 0
                ? 'RLS ativo: sem sessão autenticada, nenhum dado é visível — comportamento esperado nesta fase.'
                : 'Atenção: dados visíveis sem autenticação — revisar políticas de RLS.'}
            </p>
          </>
        )}
        {estado.fase === 'erro' && (
          <>
            <span className="status status-erro">Falha na conexão</span>
            <p>{estado.mensagem}</p>
          </>
        )}
      </div>
      <div className="card">
        <h2>Próximas sessões</h2>
        <p>
          Sessão #2: login por PIN e cadastros. Sessão #3: rodada de medicação.
          Sessão #4: relatórios de adesão e estoque.
        </p>
      </div>
    </>
  )
}
