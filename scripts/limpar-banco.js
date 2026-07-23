// Apaga TODOS os dados operacionais do banco, sem repopular (Sessão #7).
//
// Existe para o go-live: o `npm run seed -- --reset` limpa e volta a inserir os
// dados FICTÍCIOS de teste — o que não pode acontecer no banco de produção. Este
// script só limpa, para que os dados reais entrem num banco vazio, sem mistura
// de teste e produção.
//
// Uso:
//   npm run limpar-banco          — mostra as contagens e pede confirmação
//   npm run limpar-banco -- --sim — pula a confirmação (use com cuidado)
//
// Não toca no usuário Supabase da casa (auth.users): o login da casa continua
// válido; só o conteúdo do schema public é apagado.
//
// Requer em .env.local: VITE_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from '@supabase/supabase-js'
import { createInterface } from 'node:readline/promises'
import { stdin, stdout } from 'node:process'

const url = process.env.VITE_SUPABASE_URL
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!url || !serviceKey) {
  console.error('Defina VITE_SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY em .env.local.')
  process.exit(1)
}

const supabase = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false }
})

// Ordem inversa das dependências (FKs) — a mesma do seed.
const TABELAS = [
  'movimentacoes_estoque',
  'lotes_estoque',
  'administracoes',
  'horarios',
  'medicamentos',
  'catalogo_medicamentos',
  'idosos',
  'tentativas_pin',
  'turnos',
  'cuidadores'
]

async function contar() {
  const contagens = {}
  for (const tabela of TABELAS) {
    const { count, error } = await supabase
      .from(tabela)
      .select('id', { count: 'exact', head: true })
    if (error) {
      console.error(`Erro ao contar ${tabela}:`, error.message)
      process.exit(1)
    }
    contagens[tabela] = count
  }
  return contagens
}

const antes = await contar()
const total = Object.values(antes).reduce((a, b) => a + b, 0)

console.log(`Projeto: ${url}`)
console.log('Conteúdo atual:')
for (const [tabela, n] of Object.entries(antes)) console.log(`  ${tabela.padEnd(24)} ${n}`)

if (total === 0) {
  console.log('\nO banco já está vazio. Nada a fazer.')
  process.exit(0)
}

if (!process.argv.includes('--sim')) {
  const rl = createInterface({ input: stdin, output: stdout })
  const resposta = await rl.question(
    `\nIsto apaga as ${total} linhas acima, sem volta. Digite APAGAR para confirmar: `
  )
  rl.close()
  if (resposta.trim() !== 'APAGAR') {
    console.log('Cancelado — nada foi apagado.')
    process.exit(1)
  }
}

for (const tabela of TABELAS) {
  const { error } = await supabase.from(tabela).delete().not('id', 'is', null)
  if (error) {
    console.error(`Erro ao limpar ${tabela}:`, error.message)
    process.exit(1)
  }
}

const depois = await contar()
const restante = Object.values(depois).reduce((a, b) => a + b, 0)
console.log(restante === 0 ? '\nBanco limpo.' : `\nAINDA HÁ ${restante} linhas — verifique.`)
process.exit(restante === 0 ? 0 : 1)
