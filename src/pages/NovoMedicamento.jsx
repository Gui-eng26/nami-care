import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase.js'
import { mensagemErro } from '../lib/erros.js'
import { lancarEstoqueInicial } from '../lib/estoqueInicial.js'
import { criarHorariosIniciais } from '../lib/horariosIniciais.js'
import FormMedicamento from '../components/FormMedicamento.jsx'

// Atalho "+ Medicamento" da aba Estoque (Sessão #8): mesma porta de sempre —
// criar_medicamento com o catálogo da casa (DEC-035) e o estoque inicial
// opcional — só que alcançável de dentro da operação diária, sem passar pela
// gestão de residentes. Nenhuma RPC nova; a autorização é o turno aberto
// (DEC-038), validada no banco.
//
// Como todo medicamento pertence a um residente (medicamentos.idoso_id é NOT
// NULL), o primeiro passo é escolher para quem é.
export default function NovoMedicamento({ onVoltar }) {
  const [residentes, setResidentes] = useState(null)
  const [residente, setResidente] = useState(null)
  const [aviso, setAviso] = useState(null)
  const [ocupado, setOcupado] = useState(false)

  useEffect(() => {
    supabase
      .from('idosos')
      .select('id, nome')
      .eq('ativo', true)
      .order('nome')
      .then(({ data, error }) => setResidentes(error ? [] : data))
  }, [])

  async function salvar(valores) {
    setOcupado(true)
    setAviso(null)
    const { data, error } = await supabase.rpc('criar_medicamento', {
      p_idoso_id: residente.id,
      p_catalogo_id: valores.catalogoId,
      p_nome: valores.nome,
      p_dosagem: valores.dosagem || null,
      p_forma_farmaceutica: valores.forma || null,
      p_posologia: valores.posologia || null,
      p_tipo: valores.tipo,
      p_estoque_minimo: valores.estoqueMinimo
    })
    if (error) {
      setOcupado(false)
      setAviso({ tipo: 'erro', texto: 'Falha de conexão. Tente novamente.' })
      return
    }
    if (!data.ok) {
      setOcupado(false)
      setAviso({ tipo: 'erro', texto: mensagemErro(data) })
      return
    }

    // Horários (Sessão #10) e estoque inicial (Sessão #8): encadeados pelas
    // RPCs que já existem. Se algum falhar, o cadastro fica de pé e a tela diz
    // o que ficou faltando — nada é desfeito.
    const falhaHorarios = await criarHorariosIniciais(data.medicamento.id, valores.horarios)
    const falhaEstoque = await lancarEstoqueInicial(data.medicamento.id, valores.estoqueInicial)
    setOcupado(false)
    setResidente(null)
    const falha = falhaHorarios || falhaEstoque
    const complementos = [
      valores.horarios?.length > 0 && `${valores.horarios.length} horário(s)`,
      valores.estoqueInicial && 'estoque inicial'
    ].filter(Boolean)
    setAviso(
      falha
        ? { tipo: 'erro', texto: falha }
        : {
            tipo: 'ok',
            texto: `${data.medicamento.nome} cadastrado${
              complementos.length > 0 ? ` com ${complementos.join(' e ')}` : ''
            }.`
          }
    )
  }

  return (
    <div className="card">
      <button type="button" className="botao-voltar" onClick={onVoltar}>
        ← Estoque
      </button>
      <h2>Novo medicamento</h2>
      <p className="pendencias-explicacao">
        Para qual residente é o medicamento? O cadastro é o mesmo da gestão de
        residentes — só o caminho é mais curto.
      </p>

      {aviso && (
        <p className={`aviso ${aviso.tipo === 'ok' ? 'aviso-ok' : 'aviso-erro'}`}>
          {aviso.texto}
        </p>
      )}

      {residentes === null ? (
        <span className="status status-carregando">Carregando residentes…</span>
      ) : (
        <div className="lista-cuidadores">
          {residentes.map((r) => (
            <button
              key={r.id}
              type="button"
              className="botao-cuidador"
              onClick={() => {
                setAviso(null)
                setResidente(r)
              }}
            >
              {r.nome}
            </button>
          ))}
          {residentes.length === 0 && <p>Nenhum residente ativo cadastrado.</p>}
        </div>
      )}

      {residente && (
        <FormMedicamento
          subtitulo={`Para ${residente.nome}`}
          ocupado={ocupado}
          onFechar={() => setResidente(null)}
          onSalvar={salvar}
        />
      )}
    </div>
  )
}
