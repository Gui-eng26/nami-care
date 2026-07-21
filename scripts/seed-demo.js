// Cenário de DEMONSTRAÇÃO do Nami Care (Sessão #9).
//
// Objetivo: deixar o banco de TESTE parecendo uma casa em plena operação AGORA,
// para a conversa ao vivo com a Thais. Difere do `--com-historico` (Sessão #5)
// em três pontos, que são exatamente o que a demonstração precisa mostrar:
//
//   1. DOSES NA JANELA DE AGORA — os horários da demonstração são função do
//      instante em que o script roda, nunca constantes ("16:00"). O script cria
//      horários novos (pelas RPCs de gestão, DEC-038) espalhados de ~-85 min a
//      ~+110 min em relação ao now(), de modo que a ronda sempre tenha dose
//      ATRASADA (destaque), dose NA HORA (dentro da tolerância de 30 min,
//      DEC-023) e dose já TRATADA — e continue tendo por ~2 h, mesmo que a
//      conversa escorregue ou se estenda.
//   2. PENDÊNCIAS ENTRE TURNOS — uma lacuna deliberada de turno em D-3 (dentro
//      do teto de 5 dias da DEC-033) deixa as doses da tarde/noite daquele dia
//      sem nenhum turno cobrindo: é o que faz a faixa vermelha de alerta
//      aparecer com contagem.
//   3. HISTÓRICO DE ADESÃO — D-6..D-1 completos com os quatro status
//      distribuídos, para a aba Adesão mostrar percentuais reais.
//
// Todas as escritas passam pelas RPCs reais (abrir/fechar turno, criar_horario,
// registrar_entrada_estoque) e pelos triggers (baixa de estoque, exigência de
// turno aberto). Os ÚNICOS ajustes diretos via service role — mesma tolerância
// que o seed-historico já documenta — são de datas, e existem porque o passado
// não pode ser encenado em tempo real:
//   - `turnos.inicio/fim` recuados para o dia a que o turno se refere;
//   - `horarios.criado_em` recuado para antes do primeiro turno (a fila de
//     pendências ignora slot anterior à criação do horário, por construção).
//
// Nota de fuso: America/Sao_Paulo é UTC-3 fixo (sem horário de verão desde
// 2019); o offset -03:00 abaixo é exato e evita dependência de biblioteca.

import { cuidadores as cuidadoresSeed } from './seed-data.js'

const OFFSET_CASA = '-03:00'
const FUSO_CASA = 'America/Sao_Paulo'

// Deslocamentos (minutos, relativos ao now() da execução) dos horários criados
// para a demonstração. Negativo = já venceu; positivo = vence durante a
// conversa. Os <= -50 nascem já tratados (uma casa real tem dose dada e dose a
// dar); -38 e -25 ficam sem tratativa e aparecem ATRASADAS; -18 a -4 aparecem
// NA HORA; os positivos entram na ronda ao longo da próxima ~1h50.
const DESLOCAMENTOS = [-85, -70, -50, -38, -25, -18, -10, -4, 6, 14, 28, 40, 55, 75, 95, 110]
const TRATADA_ATE = -50

// Dia da lacuna de turno que gera as pendências entre turnos (dentro do teto de
// 5 dias da DEC-033).
const DIA_DA_LACUNA = 3

function criarRandom(semente) {
  let a = semente
  return function () {
    a |= 0
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

function diaLocal(desloc) {
  const d = new Date(Date.now() - desloc * 86400000)
  return d.toLocaleDateString('en-CA', { timeZone: FUSO_CASA })
}

// HH:MM no fuso da casa para um instante qualquer.
function horaLocal(data) {
  return data.toLocaleTimeString('en-GB', {
    timeZone: FUSO_CASA,
    hour: '2-digit',
    minute: '2-digit'
  })
}

function instante(dia, hora) {
  return new Date(`${dia}T${hora.length === 5 ? hora : hora.slice(0, 5)}${OFFSET_CASA}`)
}

function maisMinutos(data, minutos) {
  return new Date(data.getTime() + minutos * 60000)
}

function sortearStatus(rand, { nomeIdoso, hora }) {
  if (nomeIdoso === 'Iracema Barros' && hora >= '19:00' && rand() < 0.5) return 'recusado'
  const r = rand()
  if (r < 0.82) return 'tomado_no_horario'
  if (r < 0.9) return 'tomado_atrasado'
  if (r < 0.96) return 'recusado'
  return 'nao_tomado'
}

function registradoEm(rand, status, prevista) {
  switch (status) {
    case 'tomado_no_horario':
      return rand() < 0.3 ? prevista : maisMinutos(prevista, Math.round(rand() * 20))
    case 'tomado_atrasado':
      return maisMinutos(prevista, 40 + Math.round(rand() * 90))
    case 'recusado':
      return maisMinutos(prevista, 5 + Math.round(rand() * 20))
    default:
      return maisMinutos(prevista, 35 + Math.round(rand() * 60))
  }
}

export async function gerarDemo(supabase, falhar) {
  const rand = criarRandom(20260721)
  const agora = new Date()

  async function rpc(nome, params, etapa) {
    const { data, error } = await supabase.rpc(nome, params)
    if (error) falhar(etapa, error)
    if (data && data.ok === false) falhar(etapa, new Error(JSON.stringify(data)))
    return data
  }

  // --- referência ----------------------------------------------------------
  const { data: cuidadores, error: e1 } = await supabase.from('cuidadores').select('id, nome')
  if (e1) falhar('demo: ler cuidadores', e1)
  const pinPorNome = Object.fromEntries(cuidadoresSeed.map((c) => [c.nome, c.pin]))
  const porNome = Object.fromEntries(cuidadores.map((c) => [c.nome, c]))

  const { data: medicamentos, error: e2 } = await supabase
    .from('medicamentos')
    .select('id, nome, tipo, idoso_id, idosos (nome)')
  if (e2) falhar('demo: ler medicamentos', e2)
  const medPorChave = Object.fromEntries(medicamentos.map((m) => [`${m.idosos.nome}|${m.nome}`, m]))
  const continuos = medicamentos.filter((m) => m.tipo === 'continuo')

  async function gradeAtiva() {
    const { data, error } = await supabase
      .from('horarios')
      .select(
        'id, medicamento_id, hora, qtd_dose, medicamentos!inner (nome, ativo, idoso_id, idosos!inner (nome, ativo))'
      )
      .eq('ativo', true)
      .eq('medicamentos.ativo', true)
      .eq('medicamentos.idosos.ativo', true)
    if (error) falhar('demo: ler grade de horários', error)
    return data.map((h) => ({
      horario_id: h.id,
      medicamento_id: h.medicamento_id,
      hora: h.hora.slice(0, 5),
      qtd_dose: h.qtd_dose,
      nomeIdoso: h.medicamentos.idosos.nome
    }))
  }

  // Abre turno por RPC, executa o corpo, fecha (ou mantém aberto).
  const turnosParaRecuar = []
  async function comTurno(cuidador, corpo, { manterAberto = false, span = null } = {}) {
    const abertura = await rpc(
      'abrir_turno',
      { p_cuidador_id: cuidador.id, p_pin: pinPorNome[cuidador.nome] },
      `demo: abrir turno de ${cuidador.nome}`
    )
    await corpo(cuidador, abertura.turno.id)
    if (!manterAberto) {
      await rpc(
        'fechar_turno',
        { p_turno_id: abertura.turno.id },
        `demo: fechar turno de ${cuidador.nome}`
      )
    }
    if (span) turnosParaRecuar.push({ id: abertura.turno.id, ...span })
    return abertura.turno.id
  }

  // -------------------------------------------------------------------------
  // 1) Turno de preparo: cria os horários da janela de AGORA (DEC-038 — gestão
  //    de prescrição autorizada pelo turno aberto) e reforça o estoque pelo
  //    ledger, para 7 dias de histórico + a janela não zerarem nenhum saldo.
  //    Este turno é recuado depois para D-7: ele passa a ser o primeiro turno
  //    da casa, e a fila de pendências só enxerga o que veio depois dele.
  // -------------------------------------------------------------------------
  const rotacao = ['Beatriz Lima', 'Carlos Pereira', 'Débora Santos', 'Ana Souza']
  const cuidadoraDaDemo = porNome['Débora Santos']

  // Um horário novo por medicamento contínuo, intercalando residentes para a
  // ronda da janela não ficar concentrada em uma pessoa só.
  const porResidente = {}
  for (const m of continuos) (porResidente[m.idosos.nome] ??= []).push(m)
  const filas = Object.keys(porResidente).sort().map((n) => porResidente[n])
  const intercalados = []
  for (let i = 0; filas.some((f) => f.length > i); i++) {
    for (const f of filas) if (f[i]) intercalados.push(f[i])
  }

  const horasDaJanela = DESLOCAMENTOS.map((min) => ({
    min,
    hora: horaLocal(maisMinutos(agora, min))
  }))
  const janela = [] // { medicamento_id, hora, min, nomeIdoso, nomeMed }

  await comTurno(
    porNome['Ana Souza'],
    async () => {
      for (const m of continuos) {
        await rpc(
          'registrar_entrada_estoque',
          {
            p_medicamento_id: m.id,
            p_quantidade: 120,
            p_observacao: 'Reposição (cenário de demonstração)'
          },
          `demo: reforçar estoque de ${m.nome}`
        )
      }
      for (let i = 0; i < horasDaJanela.length && i < intercalados.length; i++) {
        const m = intercalados[i]
        const { min, hora } = horasDaJanela[i]
        await rpc(
          'criar_horario',
          { p_medicamento_id: m.id, p_hora: hora, p_qtd_dose: 1 },
          `demo: criar horário ${hora} de ${m.nome} (${m.idosos.nome})`
        )
        janela.push({
          medicamento_id: m.id,
          hora,
          min,
          nomeIdoso: m.idosos.nome,
          nomeMed: m.nome
        })
      }
    },
    // Cobre D-7 inteiro de propósito: é o primeiro turno da casa e, sem ele
    // cobrir o dia todo, os slots de D-7 (que existem, porque os horários são
    // recuados para antes dele) virariam pendências ALÉM do teto de 5 dias —
    // um aviso de dado perdido que não faz parte do cenário da demonstração.
    { span: { inicio: instante(diaLocal(7), '06:00'), fim: instante(diaLocal(7), '23:50') } }
  )

  const grade = await gradeAtiva()
  const slotPorHorarioId = Object.fromEntries(grade.map((s) => [s.horario_id, s]))
  const horarioIdDaJanela = {} // `${medicamento_id}|${hora}` -> horario_id
  for (const s of grade) horarioIdDaJanela[`${s.medicamento_id}|${s.hora}`] = s.horario_id
  for (const j of janela) j.horario_id = horarioIdDaJanela[`${j.medicamento_id}|${j.hora}`]

  const contagem = {
    tomado_no_horario: 0,
    tomado_atrasado: 0,
    recusado: 0,
    nao_tomado: 0,
    sos: 0
  }

  // Insere as doses de um dia. `pularApartirDe` (HH:MM) recorta o dia da lacuna.
  async function inserirDia(desloc, cuidador, { ateInstante = null, pularApartirDe = null } = {}) {
    const dia = diaLocal(desloc)
    const linhas = []
    for (const slot of grade) {
      if (pularApartirDe && slot.hora >= pularApartirDe) continue
      const prevista = instante(dia, slot.hora)
      if (ateInstante && prevista > ateInstante) continue
      const status = sortearStatus(rand, slot)
      contagem[status] += 1
      linhas.push({
        medicamento_id: slot.medicamento_id,
        horario_id: slot.horario_id,
        cuidador_id: cuidador.id,
        qtd: slot.qtd_dose,
        status,
        prevista_em: prevista.toISOString(),
        registrado_em: registradoEm(rand, status, prevista).toISOString(),
        observacao:
          status === 'recusado' && slot.nomeIdoso === 'Iracema Barros'
            ? 'Recusou; nova tentativa com suco não aceita'
            : null
      })
    }
    if (linhas.length > 0) {
      const { error } = await supabase.from('administracoes').insert(linhas)
      if (error) falhar(`demo: doses de ${dia}`, error)
    }
    return linhas.length
  }

  // Doses SOS espalhadas (contagem absoluta no relatório — DEC-014/DEC-030).
  const dosesSos = [
    [5, 'Cecília Prado', 'Paracetamol', '14:30'],
    [4, 'Firmino Duarte', 'Dipirona', '10:15'],
    [2, 'Cecília Prado', 'Paracetamol', '22:10'],
    [1, 'Iracema Barros', 'Simeticona', '16:00']
  ]
  async function inserirSos(desloc, cuidador) {
    const dia = diaLocal(desloc)
    for (const [d, idoso, med, hora] of dosesSos) {
      if (d !== desloc) continue
      const m = medPorChave[`${idoso}|${med}`]
      const { error } = await supabase.from('administracoes').insert({
        medicamento_id: m.id,
        cuidador_id: cuidador.id,
        qtd: 1,
        status: 'tomado_no_horario',
        registrado_em: instante(dia, hora).toISOString(),
        observacao: 'Dose SOS'
      })
      if (error) falhar(`demo: SOS de ${dia}`, error)
      contagem.sos += 1
    }
  }

  // -------------------------------------------------------------------------
  // 2) D-6..D-1: um turno por dia, doses do dia, turno fechado.
  //    Em D-3 o turno termina cedo e as doses do fim do dia NÃO são lançadas —
  //    é a lacuna que alimenta a faixa "Pendências entre turnos".
  // -------------------------------------------------------------------------
  // A lacuna começa ~2 h antes da hora atual, para que os horários da janela
  // daquele dia (que existem em todos os dias) também fiquem descobertos.
  const inicioDaLacuna = (() => {
    const h = horaLocal(maisMinutos(agora, -120))
    return h < '08:00' ? '14:00' : h
  })()

  let totalRonda = 0
  for (let i = 0; i < 6; i++) {
    const desloc = 6 - i
    const cuidador = porNome[rotacao[i % rotacao.length]]
    const ehLacuna = desloc === DIA_DA_LACUNA
    const dia = diaLocal(desloc)
    await comTurno(
      cuidador,
      async (c) => {
        totalRonda += await inserirDia(desloc, c, {
          pularApartirDe: ehLacuna ? inicioDaLacuna : null
        })
        await inserirSos(desloc, c)
      },
      {
        span: {
          inicio: instante(dia, '06:00'),
          fim: ehLacuna ? instante(dia, inicioDaLacuna) : instante(dia, '23:50')
        }
      }
    )
  }

  // -------------------------------------------------------------------------
  // 3) Hoje: turno da cuidadora da demonstração, ABERTO.
  //    Tudo que venceu até ~90 min atrás já está tratado; na janela de agora,
  //    as doses mais antigas nascem tratadas e o restante fica para a ronda.
  // -------------------------------------------------------------------------
  const hoje = diaLocal(0)
  const corteTratado = maisMinutos(agora, -90)
  const jaTratadas = new Set(
    janela.filter((j) => j.min <= TRATADA_ATE).map((j) => j.horario_id)
  )

  await comTurno(
    cuidadoraDaDemo,
    async (c) => {
      // Doses de hoje anteriores à janela.
      totalRonda += await inserirDia(0, c, { ateInstante: corteTratado })
      await inserirSos(0, c)

      // Doses da janela que a casa "já deu".
      const linhas = []
      for (const j of janela) {
        if (!jaTratadas.has(j.horario_id)) continue
        const slot = slotPorHorarioId[j.horario_id]
        const prevista = instante(hoje, j.hora)
        const status = rand() < 0.7 ? 'tomado_no_horario' : 'tomado_atrasado'
        contagem[status] += 1
        linhas.push({
          medicamento_id: j.medicamento_id,
          horario_id: j.horario_id,
          cuidador_id: c.id,
          qtd: slot.qtd_dose,
          status,
          prevista_em: prevista.toISOString(),
          registrado_em: registradoEm(rand, status, prevista).toISOString(),
          observacao: null
        })
      }
      if (linhas.length > 0) {
        const { error } = await supabase.from('administracoes').insert(linhas)
        if (error) falhar('demo: doses já tratadas da janela', error)
      }
      totalRonda += linhas.length
    },
    { manterAberto: true, span: { inicio: instante(hoje, '06:00'), fim: null } }
  )

  // -------------------------------------------------------------------------
  // 4) Ajustes de data (service role) — ver cabeçalho.
  //    Feitos só DEPOIS de todos os turnos fecharem: recuar antes faria o
  //    fechar_turno enxergar as pendências que estamos criando de propósito.
  // -------------------------------------------------------------------------
  for (const t of turnosParaRecuar) {
    const patch = { inicio: t.inicio.toISOString() }
    if (t.fim) patch.fim = t.fim.toISOString()
    const { error } = await supabase.from('turnos').update(patch).eq('id', t.id)
    if (error) falhar('demo: recuar turnos', error)
  }

  const { error: eHorarios } = await supabase
    .from('horarios')
    .update({ criado_em: instante(diaLocal(7), '05:00').toISOString() })
    .not('id', 'is', null)
  if (eHorarios) falhar('demo: recuar criado_em dos horários', eHorarios)

  // --- conferência ---------------------------------------------------------
  const pendencias = await rpc('listar_pendencias_entre_turnos', {}, 'demo: conferir pendências')

  const atrasadas = janela.filter((j) => !jaTratadas.has(j.horario_id) && j.min < -30).length
  const naHora = janela.filter((j) => !jaTratadas.has(j.horario_id) && j.min >= -30 && j.min <= 0)
    .length
  const aVir = janela.filter((j) => j.min > 0).length

  console.log('\nCenário de demonstração pronto:')
  console.log(`  ${totalRonda} doses de ronda (D-6 a hoje) + ${contagem.sos} SOS`)
  console.log(
    `  status — no horário: ${contagem.tomado_no_horario}, atrasada: ${contagem.tomado_atrasado}, recusada: ${contagem.recusado}, não tomada: ${contagem.nao_tomado}`
  )
  console.log(
    `  janela de agora (${horasDaJanela[0].hora}–${horasDaJanela.at(-1).hora}): ${jaTratadas.size} já tratadas, ${atrasadas} atrasadas, ${naHora} na hora, ${aVir} a vencer nas próximas ~2 h`
  )
  console.log(
    `  pendências entre turnos: ${pendencias.total} doses (lacuna em ${diaLocal(DIA_DA_LACUNA)}, a partir de ${inicioDaLacuna})`
  )
  console.log(
    `  turno ABERTO de ${cuidadoraDaDemo.nome} (PIN ${pinPorNome[cuidadoraDaDemo.nome]}) desde 06:00 de hoje`
  )
}
