// Bootstrap da PRIMEIRA administradora da casa (Sessão #7).
//
// Por que existe: toda RPC de gestão valida o PIN de uma administradora que já
// exista no banco (DEC-024). Num banco de produção vazio não há ninguém — a
// primeira admin precisa nascer fora do fluxo normal "gestão cria cuidadora".
// Este é o ÚNICO cadastro fora do app: a partir dele, as outras cuidadoras, os
// residentes e as prescrições entram pela tela de gestão.
//
// Uso:
//   npm run criar-admin
//
// O nome é perguntado no terminal e o PIN é digitado pela própria pessoa, com a
// tela apagada (não aparece no terminal, não vai para o histórico do shell, não
// fica em arquivo nenhum). O hash é gerado NO BANCO pela `fn_hash_pin`
// (bcrypt, DEC-020) — este script nunca vê nem calcula hash, e nunca imprime o
// PIN.
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

const rl = createInterface({ input: stdin, output: stdout })

// Pergunta sem ecoar o que é digitado — o PIN não pode aparecer na tela.
// Silencia a saída do readline enquanto a resposta é digitada, deixando passar
// apenas a impressão inicial do próprio rótulo.
async function perguntarOculto(rotulo) {
  const escrever = rl._writeToOutput
  rl._writeToOutput = function (texto) {
    if (texto.includes(rotulo)) escrever.call(rl, texto)
  }
  try {
    return (await rl.question(rotulo)).trim()
  } finally {
    rl._writeToOutput = escrever
    stdout.write('\n')
  }
}

function sair(mensagem, codigo = 1) {
  rl.close()
  console.error(mensagem)
  process.exit(codigo)
}

// Guarda: o bootstrap é para banco limpo. Se já há cuidadoras, ou o seed de
// teste ainda está lá (e precisa ser limpo antes dos dados reais), ou a admin
// já existe — e aí o caminho certo é a tela de gestão, não este script.
const { data: existentes, error: erroConsulta } = await supabase
  .from('cuidadores')
  .select('nome, eh_admin, ativo')
if (erroConsulta) sair(`Erro ao consultar cuidadores: ${erroConsulta.message}`)

if (existentes.length > 0) {
  console.error(`O banco já tem ${existentes.length} cuidadora(s):`)
  for (const c of existentes) {
    console.error(`  ${c.nome}${c.eh_admin ? ' (admin)' : ''}${c.ativo ? '' : ' — inativa'}`)
  }
  console.error(
    '\nEste script só cria a PRIMEIRA administradora, em banco vazio.\n' +
      'Para novas cuidadoras use a tela de gestão do app.\n' +
      'Se estas são as cuidadoras do seed de teste, rode `npm run limpar-banco` antes.'
  )
  sair('')
}

console.log(`Projeto: ${url}`)
console.log('Bootstrap da primeira administradora da casa.\n')

const nome = (await rl.question('Nome completo da administradora: ')).trim()
if (!nome) sair('Nome obrigatório.')

console.log(
  '\nO PIN é de 4 a 6 dígitos e deve ser digitado pela própria administradora.\n' +
    'Ele não aparece na tela e não é gravado em lugar nenhum além do hash no banco.'
)
const pin = await perguntarOculto('PIN: ')
if (!/^[0-9]{4,6}$/.test(pin)) sair('PIN inválido — use de 4 a 6 dígitos numéricos.')
const pinConfirma = await perguntarOculto('Repita o PIN: ')
if (pin !== pinConfirma) sair('Os PINs não conferem — nada foi criado.')

// O hash é sempre gerado no banco (DEC-020); o script não calcula hash local.
const { data: pinHash, error: erroHash } = await supabase.rpc('fn_hash_pin', { p_pin: pin })
if (erroHash) sair(`Erro ao gerar o hash do PIN: ${erroHash.message}`)

const { data: criada, error: erroInsert } = await supabase
  .from('cuidadores')
  .insert({ nome, pin_hash: pinHash, eh_admin: true })
  .select('id, nome, eh_admin')
  .single()
if (erroInsert) sair(`Erro ao criar a administradora: ${erroInsert.message}`)

rl.close()
console.log(`\nAdministradora criada: ${criada.nome} (id ${criada.id}, admin)`)
console.log('A partir daqui, todo o resto é pela tela de gestão do app.')
