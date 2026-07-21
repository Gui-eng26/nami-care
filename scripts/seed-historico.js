// Histórico de teste do relatório de adesão (Sessão #5 — DEC-030).
//
// Gera ~7 dias de administrações respeitando TODAS as regras do banco:
//   - turno aberto/fechado exclusivamente pelas RPCs abrir_turno/fechar_turno
//     (nunca INSERT direto em turnos);
//   - administração inserida só com turno aberto do cuidador (trigger);
//   - baixa de estoque acontece pelo trigger, nunca por INSERT manual;
//   - mudança de posologia no meio do período pelo caminho oficial de
//     versionamento (atualizar_horario/criar_horario, DEC-026).
//
// Cobertura do cenário:
//   - dias D-6..D-1 completos (turno aberto, doses do dia inseridas com
//     prevista_em/registrado_em históricos, turno fechado) + hoje parcial;
//   - os quatro status (tomado_no_horario/tomado_atrasado/recusado/nao_tomado)
//     distribuídos deterministicamente (PRNG com semente fixa — reprodutível);
//   - doses SOS em vários dias e residentes;
//   - mudança de posologia na Sinvastatina (Alzira) a partir de D-2:
//    20:00 → 19:00 (horário versionado, linha antiga desativada) + 08:00 novo;
//   - o último turno (hoje) fica ABERTO com o início recuado para 06:00 —
//     único ajuste direto (UPDATE de turnos.inicio, via service role), para as
//     doses de hoje ainda sem tratativa aparecerem como pendentes/atrasadas na
//     ronda e como "pendente" no relatório. O turno em si foi aberto por RPC.
//
// Nota de fuso: America/Sao_Paulo é UTC-3 fixo (sem horário de verão desde
// 2019); o offset -03:00 abaixo é exato e evita dependência de biblioteca.

import { cuidadores as cuidadoresSeed } from './seed-data.js'

const OFFSET_CASA = '-03:00'

// PRNG determinístico (mulberry32): o histórico sai igual em toda execução.
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
  // yyyy-mm-dd no fuso da casa, desloc dias atrás (0 = hoje).
  const d = new Date(Date.now() - desloc * 86400000)
  return d.toLocaleDateString('en-CA', { timeZone: 'America/Sao_Paulo' })
}

function instante(dia, hora) {
  return new Date(`${dia}T${hora}${OFFSET_CASA}`)
}

function maisMinutos(data, minutos) {
  return new Date(data.getTime() + minutos * 60000)
}

// Sorteia o status da dose. Iracema recusa com frequência à noite (observação
// do cadastro); no geral predomina "tomou no horário".
function sortearStatus(rand, { nomeIdoso, hora }) {
  if (nomeIdoso === 'Iracema Barros' && hora >= '19:00' && rand() < 0.5) {
    return 'recusado'
  }
  const r = rand()
  if (r < 0.78) return 'tomado_no_horario'
  if (r < 0.88) return 'tomado_atrasado'
  if (r < 0.94) return 'recusado'
  return 'nao_tomado'
}

// registrado_em coerente com o status. Atenção: para "tomado_no_horario" uma
// parte simula registro tardio com registrado_em = prevista_em exatamente,
// como o app faz (DEC-023) — é por isso que o relatório classifica pelo
// status, nunca por aritmética de timestamps.
function registradoEm(rand, status, prevista) {
  switch (status) {
    case 'tomado_no_horario':
      return rand() < 0.3 ? prevista : maisMinutos(prevista, Math.round(rand() * 20))
    case 'tomado_atrasado':
      return maisMinutos(prevista, 40 + Math.round(rand() * 90))
    case 'recusado':
      return maisMinutos(prevista, 5 + Math.round(rand() * 20))
    default: // nao_tomado — marcado depois de estourar a janela de 30 min
      return maisMinutos(prevista, 35 + Math.round(rand() * 60))
  }
}

export async function gerarHistorico(supabase, falhar) {
  const rand = criarRandom(20260718)

  async function rpc(nome, params, etapa) {
    const { data, error } = await supabase.rpc(nome, params)
    if (error) falhar(etapa, error)
    if (data && data.ok === false) falhar(etapa, new Error(JSON.stringify(data)))
    return data
  }

  // --- carga de referência -------------------------------------------------
  const { data: cuidadores, error: e1 } = await supabase
    .from('cuidadores')
    .select('id, nome')
  if (e1) falhar('histórico: ler cuidadores', e1)
  const pinPorNome = Object.fromEntries(cuidadoresSeed.map((c) => [c.nome, c.pin]))
  const porNome = Object.fromEntries(cuidadores.map((c) => [c.nome, c]))

  const { data: medicamentos, error: e2 } = await supabase
    .from('medicamentos')
    .select('id, nome, tipo, idoso_id, idosos (nome)')
  if (e2) falhar('histórico: ler medicamentos', e2)
  const medPorChave = Object.fromEntries(
    medicamentos.map((m) => [`${m.idosos.nome}|${m.nome}`, m])
  )

  async function gradeAtiva() {
    const { data, error } = await supabase
      .from('horarios')
      .select('id, medicamento_id, hora, qtd_dose, medicamentos!inner (nome, ativo, idoso_id, idosos!inner (nome, ativo))')
      .eq('ativo', true)
      .eq('medicamentos.ativo', true)
      .eq('medicamentos.idosos.ativo', true)
    if (error) falhar('histórico: ler grade de horários', error)
    return data.map((h) => ({
      horario_id: h.id,
      medicamento_id: h.medicamento_id,
      hora: h.hora.slice(0, 5),
      qtd_dose: h.qtd_dose,
      nomeIdoso: h.medicamentos.idosos.nome
    }))
  }

  // Doses SOS planejadas do cenário: [dias atrás, residente, medicamento, hora]
  const dosesSos = [
    [5, 'Cecília Prado', 'Paracetamol', '14:30'],
    [3, 'Firmino Duarte', 'Dipirona', '10:15'],
    [3, 'Cecília Prado', 'Paracetamol', '22:10'],
    [1, 'Iracema Barros', 'Simeticona', '16:00']
  ]

  const contagem = {
    tomado_no_horario: 0,
    tomado_atrasado: 0,
    recusado: 0,
    nao_tomado: 0,
    sos: 0
  }

  async function inserirDia(desloc, cuidador, grade, ateAgora = null) {
    const dia = diaLocal(desloc)
    const linhas = []
    for (const slot of grade) {
      const prevista = instante(dia, slot.hora)
      if (ateAgora && prevista > ateAgora) continue // hoje: só o já vencido
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
      if (error) falhar(`histórico: doses de ${dia}`, error)
    }

    for (const [d, idoso, med, hora] of dosesSos) {
      if (d !== desloc) continue
      const m = medPorChave[`${idoso}|${med}`]
      const { error } = await supabase.from('administracoes').insert({
        medicamento_id: m.id,
        cuidador_id: cuidador.id,
        qtd: 1,
        status: 'tomado_no_horario',
        registrado_em: instante(dia, hora).toISOString(),
        observacao: 'Dose SOS (histórico de teste)'
      })
      if (error) falhar(`histórico: SOS de ${dia}`, error)
      contagem.sos += 1
    }
    return linhas.length
  }

  async function comTurno(cuidador, corpo, manterAberto = false) {
    const abertura = await rpc(
      'abrir_turno',
      { p_cuidador_id: cuidador.id, p_pin: pinPorNome[cuidador.nome] },
      `histórico: abrir turno de ${cuidador.nome}`
    )
    await corpo(cuidador)
    if (!manterAberto) {
      // Se falhar com doses_pendentes, o seed rodou exatamente sobre um minuto
      // de ronda (ex.: 08:00): rode de novo um minuto depois.
      await rpc(
        'fechar_turno',
        { p_turno_id: abertura.turno.id },
        `histórico: fechar turno de ${cuidador.nome}`
      )
    }
    return abertura.turno.id
  }

  // --- fase 1: D-6..D-3 com a grade original -------------------------------
  const rotacao = ['Beatriz Lima', 'Carlos Pereira', 'Débora Santos', 'Ana Souza']
  const grade1 = await gradeAtiva()
  let totalRonda = 0
  for (let i = 0; i < 4; i++) {
    const desloc = 6 - i
    await comTurno(porNome[rotacao[i]], async (c) => {
      totalRonda += await inserirDia(desloc, c, grade1)
    })
  }

  // --- mudança de posologia (DEC-026, pelo caminho oficial) ----------------
  // Sinvastatina (Alzira): 1x/dia às 20:00 → 2x/dia (08:00 e 19:00) a partir
  // de D-2. atualizar_horario versiona (há histórico); criar_horario adiciona.
  const sinvastatina = medPorChave['Alzira Nogueira|Sinvastatina']
  const horarioAntigo = grade1.find(
    (s) => s.medicamento_id === sinvastatina.id && s.hora === '20:00'
  )
  // DEC-038: mudança de prescrição é autorizada por TURNO ABERTO (não mais por
  // PIN de admin) — daí acontecer dentro de um turno, como na casa real.
  await comTurno(porNome['Ana Souza'], async () => {
    const versao = await rpc(
      'atualizar_horario',
      {
        p_horario_id: horarioAntigo.horario_id,
        p_hora: '19:00',
        p_qtd_dose: 1
      },
      'histórico: versionar horário da Sinvastatina'
    )
    if (!versao.versionado) {
      falhar('histórico: versionamento', new Error('esperava horário versionado'))
    }
    await rpc(
      'criar_horario',
      {
        p_medicamento_id: sinvastatina.id,
        p_hora: '08:00',
        p_qtd_dose: 1
      },
      'histórico: novo horário da Sinvastatina'
    )
  })

  // --- fase 2: D-2..D-1 com a grade nova + hoje parcial --------------------
  const grade2 = await gradeAtiva()
  await comTurno(porNome['Beatriz Lima'], async (c) => {
    totalRonda += await inserirDia(2, c, grade2)
  })
  await comTurno(porNome['Carlos Pereira'], async (c) => {
    totalRonda += await inserirDia(1, c, grade2)
  })

  // Hoje: turno de Débora fica ABERTO; doses vencidas há mais de 45 min são
  // tratadas, as recentes ficam sem tratativa (pendentes no relatório).
  const corte = new Date(Date.now() - 45 * 60000)
  await comTurno(
    porNome['Débora Santos'],
    async (c) => {
      totalRonda += await inserirDia(0, c, grade2, corte)
    },
    true
  )
  const inicioHoje = instante(diaLocal(0), '06:00')
  const { error: eTurno } = await supabase
    .from('turnos')
    .update({ inicio: inicioHoje.toISOString() })
    .is('fim', null)
  if (eTurno) falhar('histórico: recuar início do turno de hoje', eTurno)

  console.log('Histórico de teste gerado:')
  console.log(`  ${totalRonda} doses de ronda em 7 dias (hoje parcial)`)
  console.log(
    `  status — no horário: ${contagem.tomado_no_horario}, atrasada: ${contagem.tomado_atrasado}, recusada: ${contagem.recusado}, não tomada: ${contagem.nao_tomado}`
  )
  console.log(`  ${contagem.sos} doses SOS`)
  console.log(
    '  posologia da Sinvastatina (Alzira) versionada em D-2: 20:00 → 08:00 + 19:00'
  )
  console.log('  turno de HOJE aberto (Débora, desde 06:00) com doses pendentes')
}
