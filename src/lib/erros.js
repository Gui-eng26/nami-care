// Mensagens amigáveis para os códigos de erro das RPCs (contrato do banco).
// A regra de negócio mora no banco; aqui é só apresentação (DEC-024/025/026).

const MENSAGENS = {
  pin_invalido: 'O PIN deve ter de 4 a 6 dígitos.',
  pin_invalido_novo: 'O novo PIN deve ter de 4 a 6 dígitos.',
  cuidador_nao_encontrado: 'Cuidadora não encontrada ou desativada.',
  nao_administradora: 'Esta cuidadora não é administradora.',
  nome_obrigatorio: 'Informe o nome.',
  nome_duplicado: 'Já existe um cadastro ativo com esse nome.',
  turno_aberto: 'Ela está com um turno aberto — encerre o turno antes de desativar.',
  ultima_administradora: 'A casa precisa de ao menos uma administradora ativa.',
  residente_nao_encontrado: 'Residente não encontrado ou desativado.',
  nascimento_invalido: 'A data de nascimento precisa estar no passado.',
  medicamento_nao_encontrado: 'Medicamento não encontrado.',
  medicamento_duplicado: 'Este residente já tem esse medicamento ativo.',
  medicamento_com_historico:
    'Medicamento com administrações registradas: nome, dosagem e forma não mudam. Desative-o e cadastre a nova versão.',
  medicamento_sos: 'Medicamento SOS não tem horários fixos.',
  possui_horarios_ativos:
    'Desative os horários antes de tornar o medicamento SOS.',
  tipo_invalido: 'Tipo de medicamento inválido.',
  hora_obrigatoria: 'Informe o horário.',
  qtd_invalida: 'A dose deve ser maior que zero, em passos de 0,5.',
  horario_duplicado: 'Já existe um horário ativo nesse instante para este medicamento.',
  horario_nao_encontrado: 'Horário não encontrado.',
  horario_inativo: 'Horário desativado — reative-o ou cadastre um novo.',
  sem_turno_aberto: 'Abra um turno antes de registrar movimentações de estoque.',
  medicamento_inativo: 'Medicamento desativado — reative-o antes de registrar compra.',
  data_futura: 'A data da compra não pode estar no futuro.',
  motivo_obrigatorio: 'Informe o motivo da perda.',
  estoque_minimo_invalido: 'O estoque mínimo deve ser zero ou mais, em passos de 0,5.',
  periodo_invalido: 'Período inválido: a data final vem antes da inicial.'
}

export function mensagemErro(resposta) {
  if (!resposta || !resposta.erro) return 'Não foi possível concluir. Tente novamente.'
  if (resposta.erro === 'pin_incorreto') {
    return resposta.tentativas_restantes > 0
      ? `PIN incorreto. ${resposta.tentativas_restantes} tentativa(s) antes do bloqueio.`
      : 'PIN incorreto. Próxima tentativa só após o desbloqueio.'
  }
  if (resposta.erro === 'pin_bloqueado') {
    const hora = new Date(resposta.desbloqueia_em).toLocaleTimeString('pt-BR', {
      hour: '2-digit',
      minute: '2-digit',
      timeZone: 'America/Sao_Paulo'
    })
    return `Muitas tentativas erradas. Bloqueado até ${hora}.`
  }
  return MENSAGENS[resposta.erro] || 'Não foi possível concluir. Tente novamente.'
}
