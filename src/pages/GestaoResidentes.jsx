import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase.js'
import { mensagemErro } from '../lib/erros.js'
import { fmtForma } from '../lib/formato.js'
import { lancarEstoqueInicial } from '../lib/estoqueInicial.js'
import { criarHorariosIniciais } from '../lib/horariosIniciais.js'
import FormMedicamento from '../components/FormMedicamento.jsx'

const ROTULO_TIPO = { continuo: 'Contínuo', sos: 'SOS' }

function dataLocal(iso) {
  if (!iso) return null
  const [ano, mes, dia] = iso.split('-')
  return `${dia}/${mes}/${ano}`
}

// Gestão de residentes e prescrições (DEC-038/DEC-026): navegação em três
// níveis — lista de residentes → ficha do residente (medicamentos) → horários
// do medicamento. Toda escrita passa pelas RPCs; alterações de prescrição com
// histórico geram versão nova no banco (atualizar_horario), nunca reescrita.
//
// Sem PIN de administradora (DEC-038): a autorização é o TURNO ABERTO, exigido
// dentro de cada RPC (fn_cuidador_do_turno) — quem registra a mudança clínica é
// a cuidadora do turno, e é o turno dela que fica na trilha de auditoria.
export default function GestaoResidentes() {
  const [residentes, setResidentes] = useState(null)
  const [residente, setResidente] = useState(null)

  const carregar = useCallback(async () => {
    const { data, error } = await supabase
      .from('idosos')
      .select('id, nome, nascimento, observacoes, ativo, eh_sentinela')
      .order('ativo', { ascending: false })
      .order('nome')
    setResidentes(error ? [] : data)
  }, [])

  useEffect(() => {
    carregar()
  }, [carregar])

  if (residentes === null) {
    return (
      <div className="card">
        <span className="status status-carregando">Carregando residentes…</span>
      </div>
    )
  }

  if (residente) {
    return (
      <FichaResidente
        residente={residente}
        onVoltar={() => {
          setResidente(null)
          carregar()
        }}
        onAtualizado={async () => {
          await carregar()
          const { data } = await supabase
            .from('idosos')
            .select('id, nome, nascimento, observacoes, ativo, eh_sentinela')
            .eq('id', residente.id)
            .single()
          if (data) setResidente(data)
        }}
      />
    )
  }

  return (
    <ListaResidentes
      residentes={residentes}
      onAbrir={setResidente}
      onRecarregar={carregar}
    />
  )
}

function ListaResidentes({ residentes, onAbrir, onRecarregar }) {
  const [form, setForm] = useState(false)
  const [aviso, setAviso] = useState(null)
  const [ocupado, setOcupado] = useState(false)

  async function criar(valores) {
    setOcupado(true)
    setAviso(null)
    const { data, error } = await supabase.rpc('criar_residente', {
      p_nome: valores.nome,
      p_nascimento: valores.nascimento || null,
      p_observacoes: valores.observacoes || null
    })
    setOcupado(false)
    if (error) {
      setAviso('Falha de conexão. Tente novamente.')
      return
    }
    if (!data.ok) {
      setAviso(mensagemErro(data))
      return
    }
    setForm(false)
    onRecarregar()
  }

  return (
    <div className="card">
      <div className="gestao-cabecalho">
        {/* O "Da Casa" não é uma pessoa: fora da contagem de residentes. */}
        <h2>
          Residentes ({residentes.filter((r) => r.ativo && !r.eh_sentinela).length} ativos)
        </h2>
        <button
          type="button"
          className="botao-mini"
          onClick={() => {
            setAviso(null)
            setForm(true)
          }}
        >
          + Novo residente
        </button>
      </div>
      {aviso && <p className="aviso aviso-erro">{aviso}</p>}
      <ul className="lista-gestao">
        {residentes.map((r) => (
          <li key={r.id}>
            {/* O "Da Casa" (DEC-044) aparece de propósito, destacado em
                vermelho: é a identificação visual da caixa comum, e é por ele
                que se cadastra um medicamento do estoque compartilhado. */}
            <button
              type="button"
              className={`item-gestao ${r.ativo ? '' : 'item-inativo'} ${
                r.eh_sentinela ? 'item-gestao-casa' : ''
              }`}
              onClick={() => onAbrir(r)}
            >
              <span className="item-gestao-nome">
                {r.nome}
                {r.eh_sentinela && (
                  <span className="item-gestao-detalhe">
                    Estoque compartilhado — medicamentos SOS da casa
                  </span>
                )}
                {r.nascimento && (
                  <span className="item-gestao-detalhe">Nascimento: {dataLocal(r.nascimento)}</span>
                )}
              </span>
              <span className="item-gestao-chips">
                {r.eh_sentinela && <span className="chip chip-casa">Da casa</span>}
                {!r.ativo && <span className="chip chip-inativo">Inativo</span>}
                <span className="dose-acao">›</span>
              </span>
            </button>
          </li>
        ))}
      </ul>
      {form && (
        <FormResidente
          ocupado={ocupado}
          onFechar={() => setForm(false)}
          onSalvar={criar}
        />
      )}
    </div>
  )
}

function FichaResidente({ residente, onVoltar, onAtualizado }) {
  const [medicamentos, setMedicamentos] = useState(null)
  const [medicamento, setMedicamento] = useState(null)
  const [form, setForm] = useState(null) // 'residente' | 'medicamento'
  const [aviso, setAviso] = useState(null)
  const [ocupado, setOcupado] = useState(false)

  const carregarMedicamentos = useCallback(async () => {
    const { data, error } = await supabase
      .from('medicamentos')
      .select('id, catalogo_id, nome, dosagem, forma_farmaceutica, posologia, tipo, ativo, estoque_minimo')
      .eq('idoso_id', residente.id)
      .order('ativo', { ascending: false })
      .order('nome')
    setMedicamentos(error ? [] : data)
  }, [residente.id])

  useEffect(() => {
    carregarMedicamentos()
  }, [carregarMedicamentos])

  async function chamarRpc(nome, params) {
    setOcupado(true)
    setAviso(null)
    const { data, error } = await supabase.rpc(nome, params)
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

  if (medicamento) {
    return (
      <FichaMedicamento
        residente={residente}
        medicamento={medicamento}
        onVoltar={() => {
          setMedicamento(null)
          carregarMedicamentos()
        }}
        onAtualizado={async () => {
          await carregarMedicamentos()
          const { data } = await supabase
            .from('medicamentos')
            .select('id, catalogo_id, nome, dosagem, forma_farmaceutica, posologia, tipo, ativo, estoque_minimo')
            .eq('id', medicamento.id)
            .single()
          if (data) setMedicamento(data)
        }}
      />
    )
  }

  return (
    <div className="card">
      <button type="button" className="botao-voltar" onClick={onVoltar}>
        ← Residentes
      </button>
      <div className="gestao-cabecalho">
        <h2>
          {residente.nome}
          {!residente.ativo && <span className="chip chip-inativo"> Inativo</span>}
        </h2>
        <button
          type="button"
          className="botao-mini"
          onClick={() => {
            setAviso(null)
            setForm('residente')
          }}
        >
          Editar
        </button>
      </div>
      {residente.eh_sentinela ? (
        <p className="card-casa-explicacao">
          Estoque compartilhado da casa: medicamentos SOS que não pertencem a um
          residente. Quem toma é sempre registrado no nome da pessoa, na dose
          avulsa da ronda.
        </p>
      ) : (
        <p>
          {residente.nascimento ? `Nascimento: ${dataLocal(residente.nascimento)}` : 'Sem data de nascimento'}
          {residente.observacoes ? ` — ${residente.observacoes}` : ''}
        </p>
      )}

      {aviso && (
        <p className={`aviso ${aviso.tipo === 'ok' ? 'aviso-ok' : 'aviso-erro'}`}>
          {aviso.texto}
        </p>
      )}

      <div className="gestao-cabecalho" style={{ marginTop: '1rem' }}>
        <h2>Medicamentos</h2>
        {residente.ativo && (
          <button
            type="button"
            className="botao-mini"
            onClick={() => {
              setAviso(null)
              setForm('medicamento')
            }}
          >
            + Novo
          </button>
        )}
      </div>
      {medicamentos === null ? (
        <span className="status status-carregando">Carregando…</span>
      ) : (
        <ul className="lista-gestao">
          {medicamentos.map((m) => (
            <li key={m.id}>
              <button
                type="button"
                className={`item-gestao ${m.ativo ? '' : 'item-inativo'}`}
                onClick={() => setMedicamento(m)}
              >
                <span className="item-gestao-nome">
                  {m.nome} {m.dosagem}
                  <span className="item-gestao-detalhe">
                    {[m.forma_farmaceutica, m.posologia].filter(Boolean).join(' — ')}
                  </span>
                </span>
                <span className="item-gestao-chips">
                  {m.tipo === 'sos' && <span className="chip chip-sos">SOS</span>}
                  {!m.ativo && <span className="chip chip-inativo">Inativo</span>}
                  <span className="dose-acao">›</span>
                </span>
              </button>
            </li>
          ))}
          {medicamentos.length === 0 && <p>Nenhum medicamento cadastrado.</p>}
        </ul>
      )}

      {/* O estoque da casa não se desativa: a caixa comum continua na
          prateleira (o banco também recusa — DEC-044). */}
      {!residente.eh_sentinela && (
        <div className="acoes-item">
          <button
            type="button"
            className={`botao-mini ${residente.ativo ? 'botao-mini-perigo' : ''}`}
            disabled={ocupado}
            onClick={async () => {
              const r = await chamarRpc('definir_ativo_residente', {
                p_idoso_id: residente.id,
                p_ativo: !residente.ativo
              })
              if (r) onAtualizado()
            }}
          >
            {residente.ativo ? 'Desativar residente' : 'Reativar residente'}
          </button>
        </div>
      )}

      {form === 'residente' && (
        <FormResidente
          residente={residente}
          ocupado={ocupado}
          onFechar={() => setForm(null)}
          onSalvar={async (valores) => {
            const r = await chamarRpc('atualizar_residente', {
              p_idoso_id: residente.id,
              p_nome: valores.nome,
              p_nascimento: valores.nascimento || null,
              p_observacoes: valores.observacoes || null
            })
            if (r) {
              setForm(null)
              onAtualizado()
            }
          }}
        />
      )}
      {form === 'medicamento' && (
        <FormMedicamento
          daCasa={residente.eh_sentinela}
          ocupado={ocupado}
          onFechar={() => setForm(null)}
          onSalvar={async (valores) => {
            const r = await chamarRpc('criar_medicamento', {
              p_catalogo_id: valores.catalogoId,
              p_idoso_id: residente.id,
              p_nome: valores.nome,
              p_dosagem: valores.dosagem || null,
              p_forma_farmaceutica: valores.forma || null,
              p_posologia: valores.posologia || null,
              p_tipo: valores.tipo,
              p_estoque_minimo: valores.estoqueMinimo
            })
            if (r) {
              setForm(null)
              // Horários (Sessão #10) e estoque inicial (Sessão #8):
              // encadeados pelas RPCs que já existem; se algum falhar, o
              // cadastro fica de pé e a tela avisa o que ficou faltando.
              const falhaHorarios = await criarHorariosIniciais(
                r.medicamento.id,
                valores.horarios
              )
              const falhaEstoque = await lancarEstoqueInicial(
                r.medicamento.id,
                valores.estoqueInicial
              )
              const falha = falhaHorarios || falhaEstoque
              setAviso(falha ? { tipo: 'erro', texto: falha } : null)
              carregarMedicamentos()
            }
          }}
        />
      )}
    </div>
  )
}

function FichaMedicamento({ residente, medicamento, onVoltar, onAtualizado }) {
  const [horarios, setHorarios] = useState(null)
  const [form, setForm] = useState(null) // {modo:'medicamento'} | {modo:'horario', horario?}
  const [aviso, setAviso] = useState(null)
  const [ocupado, setOcupado] = useState(false)

  const carregarHorarios = useCallback(async () => {
    const { data, error } = await supabase
      .from('horarios')
      .select('id, hora, qtd_dose, ativo')
      .eq('medicamento_id', medicamento.id)
      .order('ativo', { ascending: false })
      .order('hora')
    setHorarios(error ? [] : data)
  }, [medicamento.id])

  useEffect(() => {
    carregarHorarios()
  }, [carregarHorarios])

  async function chamarRpc(nome, params) {
    setOcupado(true)
    setAviso(null)
    const { data, error } = await supabase.rpc(nome, params)
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

  return (
    <div className="card">
      <button type="button" className="botao-voltar" onClick={onVoltar}>
        ← {residente.nome}
      </button>
      <div className="gestao-cabecalho">
        <h2>
          {medicamento.nome} {medicamento.dosagem}
        </h2>
        <button
          type="button"
          className="botao-mini"
          onClick={() => {
            setAviso(null)
            setForm({ modo: 'medicamento' })
          }}
        >
          Editar
        </button>
      </div>
      <p>
        {[
          ROTULO_TIPO[medicamento.tipo],
          medicamento.forma_farmaceutica,
          medicamento.posologia
        ]
          .filter(Boolean)
          .join(' — ')}
      </p>

      {aviso && (
        <p className={`aviso ${aviso.tipo === 'ok' ? 'aviso-ok' : 'aviso-erro'}`}>
          {aviso.texto}
        </p>
      )}

      {medicamento.tipo === 'continuo' && (
        <>
          <div className="gestao-cabecalho" style={{ marginTop: '1rem' }}>
            <h2>Horários das rondas</h2>
            {medicamento.ativo && (
              <button
                type="button"
                className="botao-mini"
                onClick={() => {
                  setAviso(null)
                  setForm({ modo: 'horario' })
                }}
              >
                + Novo
              </button>
            )}
          </div>
          {horarios === null ? (
            <span className="status status-carregando">Carregando…</span>
          ) : (
            <ul className="lista-gestao">
              {horarios.map((h) => (
                <li key={h.id}>
                  <div className={`item-gestao ${h.ativo ? '' : 'item-inativo'}`}>
                    <span className="item-gestao-nome">
                      {h.hora.slice(0, 5)}
                      <span className="item-gestao-detalhe">
                        {Number(h.qtd_dose)} {fmtForma(h.qtd_dose, medicamento.forma_farmaceutica)}
                      </span>
                    </span>
                    <span className="item-gestao-chips">
                      {!h.ativo && <span className="chip chip-inativo">Inativo</span>}
                      {h.ativo && (
                        <button
                          type="button"
                          className="botao-mini"
                          disabled={ocupado}
                          onClick={() => {
                            setAviso(null)
                            setForm({ modo: 'horario', horario: h })
                          }}
                        >
                          Editar
                        </button>
                      )}
                      <button
                        type="button"
                        className={`botao-mini ${h.ativo ? 'botao-mini-perigo' : ''}`}
                        disabled={ocupado}
                        onClick={async () => {
                          const r = await chamarRpc('definir_ativo_horario', {
                            p_horario_id: h.id,
                            p_ativo: !h.ativo
                          })
                          if (r) carregarHorarios()
                        }}
                      >
                        {h.ativo ? 'Desativar' : 'Reativar'}
                      </button>
                    </span>
                  </div>
                </li>
              ))}
              {horarios.length === 0 && (
                <p>Nenhum horário — o medicamento não entra nas rondas até ter horário ativo.</p>
              )}
            </ul>
          )}
        </>
      )}
      {medicamento.tipo === 'sos' && (
        <p className="card-sos">
          Medicamento SOS: sem horários fixos — registrado como dose avulsa na
          tela da ronda.{' '}
          {medicamento.estoque_minimo !== null
            ? `Estoque mínimo de segurança: ${Number(medicamento.estoque_minimo)} (alerta de recompra abaixo disso).`
            : 'Sem estoque mínimo definido — o alerta de recompra fica desligado.'}
        </p>
      )}

      <div className="acoes-item">
        <button
          type="button"
          className={`botao-mini ${medicamento.ativo ? 'botao-mini-perigo' : ''}`}
          disabled={ocupado}
          onClick={async () => {
            const r = await chamarRpc('definir_ativo_medicamento', {
              p_medicamento_id: medicamento.id,
              p_ativo: !medicamento.ativo
            })
            if (r) onAtualizado()
          }}
        >
          {medicamento.ativo ? 'Desativar medicamento' : 'Reativar medicamento'}
        </button>
      </div>

      {form?.modo === 'medicamento' && (
        <FormMedicamento
          medicamento={medicamento}
          daCasa={residente.eh_sentinela}
          ocupado={ocupado}
          onFechar={() => setForm(null)}
          onSalvar={async (valores) => {
            const r = await chamarRpc('atualizar_medicamento', {
              p_medicamento_id: medicamento.id,
              p_catalogo_id: valores.catalogoId,
              p_nome: valores.nome,
              p_dosagem: valores.dosagem || null,
              p_forma_farmaceutica: valores.forma || null,
              p_posologia: valores.posologia || null,
              p_tipo: valores.tipo,
              p_estoque_minimo: valores.estoqueMinimo
            })
            if (r) {
              setForm(null)
              onAtualizado()
            }
          }}
        />
      )}
      {form?.modo === 'horario' && (
        <FormHorario
          horario={form.horario}
          ocupado={ocupado}
          onFechar={() => setForm(null)}
          onSalvar={async (valores) => {
            const r = form.horario
              ? await chamarRpc('atualizar_horario', {
                  p_horario_id: form.horario.id,
                  p_hora: valores.hora,
                  p_qtd_dose: valores.qtdDose
                })
              : await chamarRpc('criar_horario', {
                  p_medicamento_id: medicamento.id,
                  p_hora: valores.hora,
                  p_qtd_dose: valores.qtdDose
                })
            if (r) {
              setForm(null)
              if (r.versionado) {
                setAviso({
                  tipo: 'ok',
                  texto:
                    'Horário com histórico: a versão antiga foi desativada e uma nova foi criada (DEC-026).'
                })
              }
              carregarHorarios()
            }
          }}
        />
      )}
    </div>
  )
}

function FormResidente({ residente, ocupado, onFechar, onSalvar }) {
  const [nome, setNome] = useState(residente?.nome ?? '')
  const [nascimento, setNascimento] = useState(residente?.nascimento ?? '')
  const [observacoes, setObservacoes] = useState(residente?.observacoes ?? '')

  return (
    <div className="modal-fundo" onClick={onFechar}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>{residente ? `Editar ${residente.nome}` : 'Novo residente'}</h3>
        <form
          className="formulario"
          onSubmit={(e) => {
            e.preventDefault()
            onSalvar({ nome: nome.trim(), nascimento, observacoes: observacoes.trim() })
          }}
        >
          <label>
            Nome
            <input value={nome} onChange={(e) => setNome(e.target.value)} required />
          </label>
          <label>
            Nascimento (opcional)
            <input type="date" value={nascimento} onChange={(e) => setNascimento(e.target.value)} />
          </label>
          <label>
            Observações (opcional)
            <textarea
              rows={2}
              value={observacoes}
              onChange={(e) => setObservacoes(e.target.value)}
            />
          </label>
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

function FormHorario({ horario, ocupado, onFechar, onSalvar }) {
  const [hora, setHora] = useState(horario ? horario.hora.slice(0, 5) : '')
  const [qtdDose, setQtdDose] = useState(horario ? String(Number(horario.qtd_dose)) : '1')

  return (
    <div className="modal-fundo" onClick={onFechar}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>{horario ? `Editar horário ${horario.hora.slice(0, 5)}` : 'Novo horário'}</h3>
        <form
          className="formulario"
          onSubmit={(e) => {
            e.preventDefault()
            onSalvar({ hora, qtdDose: Number(qtdDose) })
          }}
        >
          <div className="formulario-linha">
            <label>
              Horário
              <input type="time" value={hora} onChange={(e) => setHora(e.target.value)} required />
            </label>
            <label>
              Dose (passos de 0,5)
              <input
                type="number"
                min="0.5"
                step="0.5"
                inputMode="decimal"
                value={qtdDose}
                onChange={(e) => setQtdDose(e.target.value)}
                required
              />
            </label>
          </div>
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
