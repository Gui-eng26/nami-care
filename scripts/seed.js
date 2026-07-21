// Seed de dados de teste do Nami Care.
//
// Uso:
//   npm run seed                     — popula um banco vazio (aborta se já houver dados)
//   npm run seed -- --reset          — apaga TODOS os dados e repopula (banco limpo)
//   npm run seed -- --com-historico  — reset + ~7 dias de histórico de administrações
//                                      para testar o relatório de adesão (Sessão #5);
//                                      deixa um turno ABERTO com doses pendentes
//   npm run seed-demo                — reset + cenário de DEMONSTRAÇÃO (Sessão #9):
//                                      histórico de adesão, lacuna de turno que
//                                      acende as "Pendências entre turnos" e doses
//                                      na janela do horário em que o script rodar
//
// Requer em .env.local (carregado via --env-file no script npm):
//   VITE_SUPABASE_URL            — URL do projeto
//   SUPABASE_SERVICE_ROLE_KEY    — service role key (ignora RLS; nunca no frontend)

import { createClient } from '@supabase/supabase-js'
import { cuidadores, idosos, medicamentos } from './seed-data.js'
import { gerarHistorico } from './seed-historico.js'
import { gerarDemo } from './seed-demo.js'

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
    'catalogo_medicamentos',
    'idosos',
    'tentativas_pin',
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
  // --com-historico sempre parte do zero: o histórico referencia horários e
  // turnos específicos e não pode ser sobreposto a dados existentes.
  const comHistorico = process.argv.includes('--com-historico')
  // --demo (npm run seed-demo) também parte do zero e é REEXECUTÁVEL: rodar de
  // novo recompõe o cenário com a janela recalculada para o novo horário.
  const demo = process.argv.includes('--demo')
  if (process.argv.includes('--reset') || comHistorico || demo) {
    await resetar()
  } else if (await bancoTemDados()) {
    console.error('O banco já tem dados. Use `npm run seed -- --reset` para repopular.')
    process.exit(1)
  }

  // Cuidadores — o hash de PIN é sempre gerado no banco (bcrypt via
  // fn_hash_pin, DEC-020); o seed nunca calcula hash localmente.
  const linhasCuidadores = []
  for (const c of cuidadores) {
    const { data: pinHash, error: erroHash } = await supabase.rpc('fn_hash_pin', {
      p_pin: c.pin
    })
    if (erroHash) falhar(`gerar hash do PIN de ${c.nome}`, erroHash)
    linhasCuidadores.push({ nome: c.nome, pin_hash: pinHash, eh_admin: Boolean(c.admin) })
  }

  const { data: cuidadoresInseridos, error: erroCuidadores } = await supabase
    .from('cuidadores')
    .insert(linhasCuidadores)
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

  // Catálogo de medicamentos (DEC-035): um item por combinação exata de
  // (nome, dosagem, forma) — o mesmo remédio de dois residentes aponta para o
  // mesmo item. Construído a partir do seed, como faz o backfill da migration.
  const catalogoPorChave = {}
  async function catalogoId(nome, dosagem, forma) {
    const chave = `${nome}|${dosagem ?? ''}|${forma ?? ''}`
    if (catalogoPorChave[chave]) return catalogoPorChave[chave]
    const { data, error } = await supabase
      .from('catalogo_medicamentos')
      .insert({ nome, dosagem: dosagem ?? null, forma_farmaceutica: forma ?? null })
      .select('id')
      .single()
    if (error) falhar(`inserir item de catálogo ${nome}`, error)
    catalogoPorChave[chave] = data.id
    return data.id
  }

  // Medicamentos + horários + estoque inicial
  let totalHorarios = 0
  for (const med of medicamentos) {
    const catId = await catalogoId(med.nome, med.dosagem, med.forma)
    const { data: medInserido, error: erroMed } = await supabase
      .from('medicamentos')
      .insert({
        idoso_id: idosoPorNome[med.idoso],
        catalogo_id: catId,
        nome: med.nome,
        dosagem: med.dosagem,
        forma_farmaceutica: med.forma,
        posologia: med.posologia,
        tipo: med.tipo,
        estoque_minimo: med.estoqueMinimo ?? null
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

  if (comHistorico) {
    await gerarHistorico(supabase, falhar)
  }

  if (demo) {
    await gerarDemo(supabase, falhar)
  }
}

main()
