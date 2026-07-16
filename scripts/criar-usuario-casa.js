// Cria o usuário Supabase único da casa de repouso (DEC-019).
// O dispositivo compartilhado faz login com este usuário uma única vez; a
// identificação individual dos cuidadores é por PIN (turno), nunca por conta.
//
// Uso:
//   npm run criar-usuario-casa
//
// Requer em .env.local (carregado via --env-file no script npm):
//   VITE_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//   CASA_EMAIL, CASA_SENHA — credenciais desejadas para o usuário da casa

import { createClient } from '@supabase/supabase-js'

const url = process.env.VITE_SUPABASE_URL
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY
const email = process.env.CASA_EMAIL
const senha = process.env.CASA_SENHA

if (!url || !serviceKey || !email || !senha) {
  console.error(
    'Defina VITE_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, CASA_EMAIL e CASA_SENHA em .env.local.'
  )
  process.exit(1)
}

const supabase = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false }
})

const { data, error } = await supabase.auth.admin.createUser({
  email,
  password: senha,
  email_confirm: true
})

if (error) {
  console.error('Erro ao criar usuário da casa:', error.message)
  process.exit(1)
}

console.log(`Usuário da casa criado: ${data.user.email} (id ${data.user.id})`)
