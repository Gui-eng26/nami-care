import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase.js'

const FUSO = 'America/Sao_Paulo'

function horaLocal(iso) {
  return new Date(iso).toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: FUSO
  })
}

const ROTULO_STATUS = {
  tomado_no_horario: 'Tomou no horário',
  tomado_atrasado: 'Tomou atrasado',
  nao_tomado: 'Não tomou',
  recusado: 'Recusou'
}

function agruparPorSlot(lista) {
  const grupos = new Map()
  for (const dose of lista) {
    if (!grupos.has(dose.prevista_em)) grupos.set(dose.prevista_em, [])
    grupos.get(dose.prevista_em).push(dose)
  }
  return [...grupos.entries()].map(([prevista_em, itens]) => ({ prevista_em, itens }))
}

// Tela operacional central (DEC-003): a agenda do turno vem inteira da RPC
// doses_do_turno — slots, tolerância de 30 min e situação são calculados no
// banco, nunca aqui. A baixa de estoque é o trigger de administracoes (DEC-008).
export default function Ronda({ turno, onTurnoFechado }) {
  const [doses, setDoses] = useState(null)
  const [proximaRonda, setProximaRonda] = useState(null)
  const [doseAberta, setDoseAberta] = useState(null)
  const [avisoFechamento, setAvisoFechamento] = useState(null)
  const [fechando, setFechando] = useState(false)

  const carregar = useCallback(async () => {
    const { data, error } = await supabase.rpc('doses_do_turno', { p_turno_id: turno.id })
    if (!error) setDoses(data)
  }, [turno.id])

  const carregarProximaRonda = useCallback(async () => {
    const { data, error } = await supabase
      .from('horarios')
      .select('hora, medicamentos!inner(tipo, ativo)')
      .eq('ativo', true)
      .eq('medicamentos.tipo', 'continuo')
      .eq('medicamentos.ativo', true)
    if (error || !data) return
    const agora = new Date().toLocaleTimeString('pt-BR', { hour12: false, timeZone: FUSO })
    const futuras = data.map((h) => h.hora).filter((h) => h > agora).sort()
    if (futuras.length === 0) {
      setProximaRonda(null)
      return
    }
    setProximaRonda({
      hora: futuras[0].slice(0, 5),
      qtd: data.filter((h) => h.hora === futuras[0]).length
    })
  }, [])

  useEffect(() => {
    carregar()
    carregarProximaRonda()
    const relogio = setInterval(() => {
      carregar()
      carregarProximaRonda()
    }, 60000)
    return () => clearInterval(relogio)
  }, [carregar, carregarProximaRonda])

  const grupos = useMemo(() => {
    if (!doses) return null
    return {
      atrasadas: agruparPorSlot(doses.filter((d) => d.situacao === 'atrasada')),
      pendentes: agruparPorSlot(doses.filter((d) => d.situacao === 'pendente')),
      tratadas: doses.filter((d) => d.situacao === 'tratada')
    }
  }, [doses])

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
      onTurnoFechado()
      return
    }
    if (data.erro === 'doses_pendentes') {
      setAvisoFechamento(
        `Ainda há ${data.total} dose(s) sem tratativa. Trate todas antes de encerrar o turno.`
      )
      carregar()
    } else {
      setAvisoFechamento('Não foi possível encerrar o turno.')
    }
  }

  if (grupos === null) {
    return (
      <div className="card">
        <span className="status status-carregando">Carregando a ronda…</span>
      </div>
    )
  }

  const totalSemTratativa =
    grupos.atrasadas.reduce((n, g) => n + g.itens.length, 0) +
    grupos.pendentes.reduce((n, g) => n + g.itens.length, 0)

  return (
    <>
      {grupos.atrasadas.length > 0 && (
        <section className="secao secao-atrasadas">
          <h2>Atrasadas — precisam de tratativa</h2>
          {grupos.atrasadas.map((grupo) => (
            <SlotDeDoses
              key={grupo.prevista_em}
              grupo={grupo}
              onTratar={setDoseAberta}
            />
          ))}
        </section>
      )}

      <section className="secao">
        <h2>Ronda atual</h2>
        {grupos.pendentes.length === 0 ? (
          <div className="card">
            <p>
              Nenhuma dose aguardando agora.
              {proximaRonda
                ? ` Próxima ronda às ${proximaRonda.hora} (${proximaRonda.qtd} dose${proximaRonda.qtd > 1 ? 's' : ''}).`
                : ' Sem mais rondas hoje.'}
            </p>
          </div>
        ) : (
          grupos.pendentes.map((grupo) => (
            <SlotDeDoses key={grupo.prevista_em} grupo={grupo} onTratar={setDoseAberta} />
          ))
        )}
      </section>

      {grupos.tratadas.length > 0 && (
        <section className="secao">
          <h2>Tratadas neste turno ({grupos.tratadas.length})</h2>
          <div className="card">
            <ul className="lista-tratadas">
              {grupos.tratadas.map((d) => (
                <li key={d.administracao_id}>
                  <span>
                    {horaLocal(d.prevista_em)} — {d.nome_idoso}: {d.nome_medicamento}
                  </span>
                  <span className={`chip chip-${d.status_tratativa}`}>
                    {ROTULO_STATUS[d.status_tratativa]}
                  </span>
                </li>
              ))}
            </ul>
          </div>
        </section>
      )}

      <section className="secao">
        <div className="card card-sos">
          <p>
            <strong>Dose avulsa (SOS)</strong> — registro de medicamento sem horário fixo
            chega na Sessão #4 (fora da ronda).
          </p>
        </div>
      </section>

      <section className="secao secao-encerrar">
        {avisoFechamento && <p className="aviso aviso-erro">{avisoFechamento}</p>}
        <button
          type="button"
          className="botao-perigo"
          onClick={encerrarTurno}
          disabled={fechando}
        >
          {fechando ? 'Encerrando…' : 'Encerrar turno'}
        </button>
        {totalSemTratativa > 0 && (
          <p className="nota-encerrar">
            {totalSemTratativa} dose(s) do turno ainda sem tratativa — o encerramento
            só é liberado quando todas forem tratadas.
          </p>
        )}
      </section>

      {doseAberta && (
        <RegistrarDose
          dose={doseAberta}
          turno={turno}
          onFechar={() => setDoseAberta(null)}
          onRegistrada={() => {
            setDoseAberta(null)
            carregar()
          }}
        />
      )}
    </>
  )
}

function SlotDeDoses({ grupo, onTratar }) {
  return (
    <div className="card slot">
      <h3 className="slot-hora">{horaLocal(grupo.prevista_em)}</h3>
      {grupo.itens.map((dose) => (
        <button
          key={`${dose.horario_id}-${dose.prevista_em}`}
          type="button"
          className={`dose ${dose.situacao === 'atrasada' ? 'dose-atrasada' : ''}`}
          onClick={() => onTratar(dose)}
        >
          <span className="dose-idoso">{dose.nome_idoso}</span>
          <span className="dose-medicamento">
            {dose.nome_medicamento} {dose.dosagem} — {dose.qtd_dose}{' '}
            {dose.forma_farmaceutica || 'unidade(s)'}
          </span>
          <span className="dose-acao">Registrar ›</span>
        </button>
      ))}
    </div>
  )
}

function RegistrarDose({ dose, turno, onFechar, onRegistrada }) {
  const atrasada = dose.situacao === 'atrasada'
  const [status, setStatus] = useState(null)
  const [observacao, setObservacao] = useState('')
  const [erro, setErro] = useState(null)
  const [salvando, setSalvando] = useState(false)

  // Tratativas conforme BRIEFING §7: dentro da janela, tomou/recusou/não tomou;
  // atrasada ganha a distinção "tomou no horário (registro tardio)" vs "tomou agora".
  const opcoes = atrasada
    ? [
        { valor: 'tomado_no_horario', rotulo: 'Tomou no horário (só faltou registrar)' },
        { valor: 'tomado_atrasado', rotulo: 'Tomou agora (atrasado)' },
        { valor: 'recusado', rotulo: 'Recusou' },
        { valor: 'nao_tomado', rotulo: 'Não tomou' }
      ]
    : [
        { valor: 'tomado_no_horario', rotulo: 'Tomou' },
        { valor: 'recusado', rotulo: 'Recusou' },
        { valor: 'nao_tomado', rotulo: 'Não tomou' }
      ]

  async function salvar() {
    setSalvando(true)
    setErro(null)
    const registro = {
      medicamento_id: dose.medicamento_id,
      horario_id: dose.horario_id,
      cuidador_id: turno.cuidador_id,
      qtd: dose.qtd_dose,
      status,
      observacao: observacao.trim() || null,
      prevista_em: dose.prevista_em
    }
    // Registro tardio de dose tomada no horário: a baixa fica datada no
    // momento real da dose (DEC-008/DEC-010).
    if (atrasada && status === 'tomado_no_horario') registro.registrado_em = dose.prevista_em

    const { error } = await supabase.from('administracoes').insert(registro)
    if (error) {
      setErro(
        error.code === '23505'
          ? 'Esta dose já recebeu tratativa. Feche e recarregue a ronda.'
          : 'Não foi possível registrar. Tente novamente.'
      )
      setSalvando(false)
      return
    }
    onRegistrada()
  }

  return (
    <div className="modal-fundo" onClick={onFechar}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>
          {dose.nome_idoso} — {horaLocal(dose.prevista_em)}
        </h3>
        <p className="modal-medicamento">
          {dose.nome_medicamento} {dose.dosagem} — {dose.qtd_dose}{' '}
          {dose.forma_farmaceutica || 'unidade(s)'}
        </p>
        <div className="opcoes-tratativa">
          {opcoes.map((opcao) => (
            <button
              key={opcao.valor}
              type="button"
              className={`opcao ${status === opcao.valor ? 'opcao-ativa' : ''}`}
              onClick={() => setStatus(opcao.valor)}
            >
              {opcao.rotulo}
            </button>
          ))}
        </div>
        <label className="campo-observacao">
          Observação (opcional)
          <textarea
            rows={2}
            value={observacao}
            onChange={(e) => setObservacao(e.target.value)}
          />
        </label>
        {erro && <p className="aviso aviso-erro">{erro}</p>}
        <div className="modal-acoes">
          <button type="button" className="botao-secundario" onClick={onFechar} disabled={salvando}>
            Cancelar
          </button>
          <button
            type="button"
            className="botao-primario"
            onClick={salvar}
            disabled={!status || salvando}
          >
            {salvando ? 'Registrando…' : 'Registrar'}
          </button>
        </div>
      </div>
    </div>
  )
}
