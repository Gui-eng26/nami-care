import { supabase } from './supabase.js'
import { mensagemErro } from './erros.js'

// Horários no cadastro de medicamento contínuo (Sessão #10). Não existe caminho
// de escrita novo: encadeia a RPC `criar_horario` que a tela de gestão já usa
// desde a Sessão #3 — mesma validação, mesma autorização por turno aberto
// (DEC-038) e mesmo versionamento da DEC-026 regendo alterações posteriores.
//
// Antes disso, o formulário compartilhado só gravava posologia (texto livre) e
// tipo: um contínuo cadastrado por ele não gerava dose nenhuma na ronda — o
// cadastro nascia incompleto. Os horários estruturados são o que de fato
// materializa os slots (DEC-023).
//
// Retorna null em caso de sucesso (ou quando não há horário a criar) e uma
// mensagem quando o medicamento foi criado mas algum horário falhou — o
// cadastro não é desfeito; a cuidadora completa pela gestão de residentes.
export async function criarHorariosIniciais(medicamentoId, horarios) {
  if (!horarios || horarios.length === 0) return null

  const falhas = []
  for (const horario of horarios) {
    const { data, error } = await supabase.rpc('criar_horario', {
      p_medicamento_id: medicamentoId,
      p_hora: horario.hora,
      p_qtd_dose: horario.qtdDose
    })
    if (error) falhas.push(`${horario.hora} (falha de conexão)`)
    else if (!data.ok) falhas.push(`${horario.hora} (${mensagemErro(data)})`)
  }

  if (falhas.length === 0) return null
  return `Medicamento cadastrado, mas ${falhas.length} horário(s) não foram criados: ${falhas.join('; ')}. Complete pela gestão de residentes.`
}
