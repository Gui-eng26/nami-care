import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase.js'
import { mensagemErro } from '../lib/erros.js'

// Gestão da equipe (DEC-024/DEC-025): criar cuidadora (o PIN vira hash no
// banco — o cliente nunca vê pin_hash), editar nome/flag de admin, redefinir
// PIN e desativar/reativar (nunca excluir — auditoria).
export default function GestaoCuidadoras({ credencial }) {
  const [cuidadoras, setCuidadoras] = useState(null)
  const [aberta, setAberta] = useState(null)
  const [form, setForm] = useState(null) // {modo:'nova'|'editar'|'pin', cuidadora?}
  const [aviso, setAviso] = useState(null)
  const [ocupado, setOcupado] = useState(false)

  const carregar = useCallback(async () => {
    const { data, error } = await supabase
      .from('cuidadores')
      .select('id, nome, ativo, eh_admin')
      .order('ativo', { ascending: false })
      .order('nome')
    setCuidadoras(error ? [] : data)
  }, [])

  useEffect(() => {
    carregar()
  }, [carregar])

  async function chamarRpc(nome, params) {
    setOcupado(true)
    setAviso(null)
    const { data, error } = await supabase.rpc(nome, {
      p_admin_id: credencial.id,
      p_admin_pin: credencial.pin,
      ...params
    })
    setOcupado(false)
    if (error) {
      setAviso({ tipo: 'erro', texto: 'Falha de conexão. Tente novamente.' })
      return null
    }
    if (!data.ok) {
      setAviso({ tipo: 'erro', texto: mensagemErro(data) })
      return null
    }
    return data
  }

  async function alternarAtiva(c) {
    const r = await chamarRpc('definir_ativo_cuidador', {
      p_cuidador_id: c.id,
      p_ativo: !c.ativo
    })
    if (r) {
      setAviso({ tipo: 'ok', texto: c.ativo ? `${c.nome} desativada.` : `${c.nome} reativada.` })
      carregar()
    }
  }

  if (cuidadoras === null) {
    return (
      <div className="card">
        <span className="status status-carregando">Carregando equipe…</span>
      </div>
    )
  }

  return (
    <div className="card">
      <div className="gestao-cabecalho">
        <h2>Equipe ({cuidadoras.filter((c) => c.ativo).length} ativas)</h2>
        <button
          type="button"
          className="botao-mini"
          onClick={() => {
            setAviso(null)
            setForm({ modo: 'nova' })
          }}
        >
          + Nova cuidadora
        </button>
      </div>
      {aviso && (
        <p className={`aviso ${aviso.tipo === 'ok' ? 'aviso-ok' : 'aviso-erro'}`}>
          {aviso.texto}
        </p>
      )}
      <ul className="lista-gestao">
        {cuidadoras.map((c) => (
          <li key={c.id}>
            <button
              type="button"
              className={`item-gestao ${c.ativo ? '' : 'item-inativo'}`}
              onClick={() => setAberta(aberta === c.id ? null : c.id)}
            >
              <span className="item-gestao-nome">{c.nome}</span>
              <span className="item-gestao-chips">
                {c.eh_admin && <span className="chip chip-admin">Admin</span>}
                {!c.ativo && <span className="chip chip-inativo">Inativa</span>}
              </span>
            </button>
            {aberta === c.id && (
              <div className="acoes-item">
                {c.ativo && (
                  <>
                    <button
                      type="button"
                      className="botao-mini"
                      disabled={ocupado}
                      onClick={() => {
                        setAviso(null)
                        setForm({ modo: 'editar', cuidadora: c })
                      }}
                    >
                      Editar
                    </button>
                    <button
                      type="button"
                      className="botao-mini"
                      disabled={ocupado}
                      onClick={() => {
                        setAviso(null)
                        setForm({ modo: 'pin', cuidadora: c })
                      }}
                    >
                      Redefinir PIN
                    </button>
                  </>
                )}
                <button
                  type="button"
                  className={`botao-mini ${c.ativo ? 'botao-mini-perigo' : ''}`}
                  disabled={ocupado}
                  onClick={() => alternarAtiva(c)}
                >
                  {c.ativo ? 'Desativar' : 'Reativar'}
                </button>
              </div>
            )}
          </li>
        ))}
      </ul>

      {form && (
        <FormCuidadora
          form={form}
          ocupado={ocupado}
          onFechar={() => setForm(null)}
          onSalvar={async (valores) => {
            let r
            if (form.modo === 'nova') {
              r = await chamarRpc('criar_cuidador', {
                p_nome: valores.nome,
                p_pin: valores.pin,
                p_eh_admin: valores.ehAdmin
              })
            } else if (form.modo === 'editar') {
              r = await chamarRpc('atualizar_cuidador', {
                p_cuidador_id: form.cuidadora.id,
                p_nome: valores.nome,
                p_eh_admin: valores.ehAdmin
              })
            } else {
              r = await chamarRpc('redefinir_pin', {
                p_cuidador_id: form.cuidadora.id,
                p_pin_novo: valores.pin
              })
            }
            if (r) {
              setForm(null)
              setAviso({ tipo: 'ok', texto: 'Salvo.' })
              carregar()
            }
          }}
        />
      )}
    </div>
  )
}

function FormCuidadora({ form, ocupado, onFechar, onSalvar }) {
  const editando = form.modo === 'editar'
  const soPin = form.modo === 'pin'
  const [nome, setNome] = useState(editando ? form.cuidadora.nome : '')
  const [pin, setPin] = useState('')
  const [ehAdmin, setEhAdmin] = useState(editando ? form.cuidadora.eh_admin : false)

  const titulo = soPin
    ? `Novo PIN de ${form.cuidadora.nome}`
    : editando
      ? `Editar ${form.cuidadora.nome}`
      : 'Nova cuidadora'

  return (
    <div className="modal-fundo" onClick={onFechar}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>{titulo}</h3>
        <form
          className="formulario"
          onSubmit={(e) => {
            e.preventDefault()
            onSalvar({ nome: nome.trim(), pin, ehAdmin })
          }}
        >
          {!soPin && (
            <label>
              Nome
              <input value={nome} onChange={(e) => setNome(e.target.value)} required />
            </label>
          )}
          {!editando && (
            <label>
              {soPin ? 'Novo PIN (4 a 6 dígitos)' : 'PIN (4 a 6 dígitos)'}
              <input
                type="password"
                inputMode="numeric"
                pattern="[0-9]{4,6}"
                minLength={4}
                maxLength={6}
                value={pin}
                onChange={(e) => setPin(e.target.value.replace(/\D/g, ''))}
                required
              />
            </label>
          )}
          {!soPin && (
            <label className="campo-opcao">
              <input
                type="checkbox"
                checked={ehAdmin}
                onChange={(e) => setEhAdmin(e.target.checked)}
              />
              Administradora (acessa a gestão)
            </label>
          )}
          <div className="modal-acoes">
            <button type="button" className="botao-secundario" onClick={onFechar} disabled={ocupado}>
              Cancelar
            </button>
            <button type="submit" className="botao-primario" disabled={ocupado}>
              {ocupado ? 'Salvando…' : 'Salvar'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
