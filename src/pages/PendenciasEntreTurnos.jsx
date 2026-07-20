import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase.js'
import { mensagemErro } from '../lib/erros.js'
import { RegistrarDose, horaLocal } from './Ronda.jsx'
import TecladoPin from '../components/TecladoPin.jsx'

// 'dia' vem do banco como yyyy-mm-dd já no fuso da casa; meio-dia UTC evita
// deslizar de dia ao formatar.
function diaLongo(dia) {
  const [ano, mes, d] = dia.split('-').map(Number)
  return new Date(Date.UTC(ano, mes - 1, d, 12)).toLocaleDateString('pt-BR', {
    weekday: 'long',
    day: '2-digit',
    month: '2-digit',
    timeZone: 'UTC'
  })
}

// Tela "Pendências entre turnos" (Sessão #5.5 — BUG-002, DEC-033/034).
// Doses que venceram em períodos sem NENHUM turno aberto: não pertencem à
// ronda (que segue bounded pelo início do turno) e são tratadas aqui —
// individualmente pelo MESMO modal da ronda, ou em lote com status 'pendente'
// (alerta de criticidade + PIN do próprio cuidador do turno).
export default function PendenciasEntreTurnos({ turno, onMudanca }) {
  const [dados, setDados] = useState(null)
  const [erro, setErro] = useState(null)
  const [doseAberta, setDoseAberta] = useState(null)
  const [loteAberto, setLoteAberto] = useState(false)
  const [avisoLote, setAvisoLote] = useState(null)
  const [avisoOk, setAvisoOk] = useState(null)

  const carregar = useCallback(async () => {
    setErro(null)
    const { data, error } = await supabase.rpc('listar_pendencias_entre_turnos')
    if (error || !data?.ok) {
      setDados(null)
      setErro('Falha de conexão. Tente novamente.')
      return
    }
    setDados(data)
  }, [])

  useEffect(() => {
    carregar()
  }, [carregar])

  // Agrupamento: por dia (mais antigo primeiro — a lista já vem ordenada por
  // prevista_em) e, dentro do dia, por residente em ordem alfabética.
  const dias = useMemo(() => {
    if (!dados) return null
    const porDia = new Map()
    for (const dose of dados.doses) {
      if (!porDia.has(dose.dia)) porDia.set(dose.dia, new Map())
      const residentes = porDia.get(dose.dia)
      if (!residentes.has(dose.idoso_id)) {
        residentes.set(dose.idoso_id, { nome: dose.nome_idoso, doses: [] })
      }
      residentes.get(dose.idoso_id).doses.push(dose)
    }
    return [...porDia.entries()].map(([dia, residentes]) => ({
      dia,
      residentes: [...residentes.values()].sort((a, b) => a.nome.localeCompare(b.nome, 'pt-BR'))
    }))
  }, [dados])

  async function confirmarLote(pin) {
    setAvisoLote(null)
    const { data, error } = await supabase.rpc('resolver_pendencias_em_lote', {
      p_turno_id: turno.id,
      p_pin: pin
    })
    if (error) {
      setAvisoLote('Falha de conexão. Tente novamente.')
      return
    }
    if (!data.ok) {
      setAvisoLote(mensagemErro(data))
      return
    }
    setLoteAberto(false)
    setAvisoOk(
      `${data.total} dose(s) encerrada(s) como "Pendente (não apurado)". Nenhuma baixa de estoque foi feita — se precisar, acerte pela tela de Estoque.`
    )
    carregar()
    onMudanca()
  }

  if (erro) {
    return (
      <div className="card">
        <p className="aviso aviso-erro">{erro}</p>
      </div>
    )
  }
  if (dias === null) {
    return (
      <div className="card">
        <span className="status status-carregando">Carregando as pendências…</span>
      </div>
    )
  }

  return (
    <>
      {/* Aviso permanente (DEC-033): dado além do teto não é mais tratável. */}
      {dados.dias_alem_do_teto > 0 && (
        <div className="card">
          <p className="aviso aviso-erro">
            Há doses sem registro em {dados.dias_alem_do_teto} dia
            {dados.dias_alem_do_teto > 1 ? 's' : ''} com mais de {dados.teto_dias} dias —
            o app não consegue mais tratá-las. Essas doses ficam de fora do relatório
            de adesão, e a contagem de estoque pode ter divergência: se precisar,
            acerte pela tela de Estoque (ajuste por contagem).
          </p>
        </div>
      )}

      <section className="secao">
        <h2>Pendências entre turnos{dados.total > 0 ? ` (${dados.total})` : ''}</h2>
        <div className="card">
          <p className="pendencias-explicacao">
            Doses que venceram em períodos sem nenhum turno aberto. Elas não aparecem
            na ronda — registre aqui o que aconteceu com cada uma.
          </p>
          {avisoOk && <p className="aviso aviso-ok">{avisoOk}</p>}
          {dados.total === 0 && !avisoOk && (
            <p>Nenhuma pendência. Tudo o que venceu fora de um turno já foi registrado.</p>
          )}
        </div>
      </section>

      {dias.map(({ dia, residentes }) => (
        <section key={dia} className="secao secao-atrasadas">
          <h2>{diaLongo(dia)}</h2>
          {residentes.map((residente) => (
            <div key={residente.nome} className="card slot">
              <h3 className="slot-hora">{residente.nome}</h3>
              {residente.doses.map((dose) => (
                <button
                  key={`${dose.horario_id}-${dose.prevista_em}`}
                  type="button"
                  className="dose dose-atrasada"
                  onClick={() => setDoseAberta({ ...dose, situacao: 'atrasada' })}
                >
                  <span className="dose-idoso">{horaLocal(dose.prevista_em)}</span>
                  <span className="dose-medicamento">
                    {dose.nome_medicamento} {dose.dosagem} — {dose.qtd_dose}{' '}
                    {dose.forma_farmaceutica || 'unidade(s)'}
                  </span>
                  <span className="dose-acao">Registrar ›</span>
                </button>
              ))}
            </div>
          ))}
        </section>
      ))}

      {dados.total > 0 && (
        <section className="secao">
          <div className="card">
            <p className="pendencias-explicacao">
              Sem condições de apurar dose a dose? O lote encerra tudo o que ainda
              está sem registro nesta lista, marcado como &ldquo;Pendente (não
              apurado)&rdquo;.
            </p>
            <button
              type="button"
              className="botao-perigo"
              onClick={() => {
                setAvisoLote(null)
                setAvisoOk(null)
                setLoteAberto(true)
              }}
            >
              Resolver pendências em lote
            </button>
          </div>
        </section>
      )}

      {doseAberta && (
        <RegistrarDose
          dose={doseAberta}
          turno={turno}
          onFechar={() => setDoseAberta(null)}
          onRegistrada={() => {
            setDoseAberta(null)
            setAvisoOk(null)
            carregar()
            onMudanca()
          }}
        />
      )}

      {/* Alerta de criticidade cheio de tela (DEC-034): difícil de ignorar,
          impacto em adesão E estoque explícito, PIN do cuidador do turno. */}
      {loteAberto && (
        <div className="alerta-critico">
          <div className="alerta-critico-conteudo">
            <h3>Encerrar {dados.total} dose(s) sem tratativa individual?</h3>
            <p>
              Essas doses serão marcadas como <strong>&ldquo;Pendente (não
              apurado)&rdquo;</strong> — ninguém confirmou se foram dadas ou não. Isso:
            </p>
            <ul>
              <li>
                vai impactar diretamente a <strong>taxa de adesão</strong> dos
                residentes no relatório; e
              </li>
              <li>
                pode gerar <strong>divergência na contagem de estoque</strong> —
                ajustes relacionados a essas doses precisarão ser feitos manualmente
                depois, pela tela de Estoque.
              </li>
            </ul>
            <p>
              Para confirmar, digite o seu PIN, {turno.cuidador_nome.split(' ')[0]}:
            </p>
            <TecladoPin onConfirmar={confirmarLote} aviso={avisoLote} />
            <button
              type="button"
              className="botao-secundario"
              onClick={() => setLoteAberto(false)}
            >
              Cancelar — vou tratar dose a dose
            </button>
          </div>
        </div>
      )}
    </>
  )
}
