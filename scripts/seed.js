// Seed de dados de teste do Nami Care.
//
// Uso:
//   npm run seed             — popula um banco vazio (aborta se já houver dados)
//   npm run seed -- --reset  — apaga TODOS os dados e repopula
//
// Requer em .env.local (carregado via --env-file no script npm):
//   VITE_SUPABASE_URL            — URL do projeto
//   SUPABASE_SERVICE_ROLE_KEY    — service role key (ignora RLS; nunca no frontend)

import { createClient } from '@supabase/supabase-js'
import { cuidadores, idosos, medicamentos, hashPin } from './seed-data.js'

const url = process.env.VITE_SUPABASE_URL
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!url || !serviceKey) {
  console.error(
    'Defina VITE_SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY em .env.local (ver .env.example).'
  )
  process.exit(1)
}

const supabase = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false }
})

function falhar(etapa, error) {
  console.error(`Erro em "${etapa}":`, error.message)
  process.exit(1)
}

async function resetar() {
  console.log('Apagando dados existentes (--reset)…')
  // Ordem inversa das dependências (FKs).
  for (const tabela of [
    'movimentacoes_estoque',
    'administracoes',
    'horarios',
    'medicamentos',
    'idosos',
    'turnos',
    'cuidadores'
  ]) {
    const { error } = await supabase.from(tabela).delete().not('id', 'is', null)
    if (error) falhar(`limpar ${tabela}`, error)
  }
}

async function bancoTemDados() {
  const { count, error } = await supabase
    .from('cuidadores')
    .select('id', { count: 'exact', head: true })
  if (error) falhar('verificar banco', error)
  return count > 0
}

async function main() {
  if (process.argv.includes('--reset')) {
    await resetar()
  } else if (await bancoTemDados()) {
    console.error('O banco já tem dados. Use `npm run seed -- --reset` para repopular.')
    process.exit(1)
  }

  // Cuidadores
  const { data: cuidadoresInseridos, error: erroCuidadores } = await supabase
    .from('cuidadores')
    .insert(cuidadores.map((c) => ({ nome: c.nome, pin_hash: hashPin(c.pin) })))
    .select('id, nome')
  if (erroCuidadores) falhar('inserir cuidadores', erroCuidadores)
  const cuidadorSeed = cuidadoresInseridos[0]

  // Idosos
  const { data: idososInseridos, error: erroIdosos } = await supabase
    .from('idosos')
    .insert(idosos)
    .select('id, nome')
  if (erroIdosos) falhar('inserir idosos', erroIdosos)
  const idosoPorNome = Object.fromEntries(idososInseridos.map((i) => [i.nome, i.id]))

  // Medicamentos + horários + estoque inicial
  let totalHorarios = 0
  for (const med of medicamentos) {
    const { data: medInserido, error: erroMed } = await supabase
      .from('medicamentos')
      .insert({
        idoso_id: idosoPorNome[med.idoso],
        nome: med.nome,
        dosagem: med.dosagem,
        forma_farmaceutica: med.forma,
        posologia: med.posologia,
        tipo: med.tipo
      })
      .select('id')
      .single()
    if (erroMed) falhar(`inserir medicamento ${med.nome} (${med.idoso})`, erroMed)

    if (med.horarios.length > 0) {
      const { error: erroHorarios } = await supabase.from('horarios').insert(
        med.horarios.map(([hora, qtd]) => ({
          medicamento_id: medInserido.id,
          hora,
          qtd_dose: qtd
        }))
      )
      if (erroHorarios) falhar(`inserir horários de ${med.nome} (${med.idoso})`, erroHorarios)
      totalHorarios += med.horarios.length
    }

    const { error: erroEstoque } = await supabase.from('movimentacoes_estoque').insert({
      medicamento_id: medInserido.id,
      cuidador_id: cuidadorSeed.id,
      tipo: 'entrada_compra',
      quantidade: med.estoqueInicial,
      motivo: 'Estoque inicial (seed)'
    })
    if (erroEstoque) falhar(`estoque inicial de ${med.nome} (${med.idoso})`, erroEstoque)
  }

  console.log('Seed concluído:')
  console.log(`  ${cuidadoresInseridos.length} cuidadores (PINs de teste: ${cuidadores.map((c) => c.pin).join(', ')})`)
  console.log(`  ${idososInseridos.length} idosos`)
  console.log(`  ${medicamentos.length} medicamentos (${medicamentos.filter((m) => m.tipo === 'sos').length} SOS)`)
  console.log(`  ${totalHorarios} horários, ${medicamentos.length} entradas de estoque`)
}

main()
