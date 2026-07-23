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
    'Medicamento com administrações registradas: não dá para trocar o remédio. Desative-o e cadastre a nova versão.',
  catalogo_nao_encontrado: 'Item do catálogo não encontrado. Recarregue e tente de novo.',
  medicamento_sos: 'Medicamento SOS não tem horários fixos.',
  // Medicamento da casa e dose SOS reestruturada (Sessão #12 — DEC-044/047).
  residente_da_casa_fixo:
    'O estoque da casa não pode ser desativado — a caixa comum continua na prateleira.',
  medicamento_nao_sos: 'Só medicamento SOS pode ser dado como dose avulsa.',
  medicamento_de_outro_residente:
    'Este medicamento é da caixa de outro residente. Use um SOS dele ou um da casa.',
  possui_horarios_ativos:
    'Desative os horários antes de tornar o medicamento SOS.',
  tipo_invalido: 'Tipo de medicamento inválido.',
  hora_obrigatoria: 'Informe o horário.',
  qtd_invalida: 'A dose deve ser maior que zero, em passos de 0,5.',
  horario_duplicado: 'Já existe um horário ativo nesse instante para este medicamento.',
  horario_nao_encontrado: 'Horário não encontrado.',
  horario_inativo: 'Horário desativado — reative-o ou cadastre um novo.',
  // Vale para estoque (Sessão #4) e, desde a DEC-038, para os cadastros de
  // residentes, medicamentos e prescrições.
  sem_turno_aberto: 'Abra um turno antes de registrar esta alteração.',
  medicamento_inativo: 'Medicamento desativado — reative-o antes de registrar compra.',
  data_futura: 'A data da compra não pode estar no futuro.',
  validade_obrigatoria: 'Informe a validade do lote.',
  motivo_obrigatorio: 'Informe o motivo da perda.',
  estoque_minimo_invalido: 'O estoque mínimo deve ser zero ou mais, em passos de 0,5.',
  periodo_invalido: 'Período inválido: a data final vem antes da inicial.',
  // Extrato de adesão por categoria (Sessão #13 — DEC-048). Os dois só
  // aparecem se a tela chamar errado; a cuidadora não chega neles pelo uso.
  residente_obrigatorio: 'Escolha um residente para ver as doses.',
  categoria_invalida: 'Categoria desconhecida. Recarregue a tela.',
  turno_nao_encontrado: 'Turno não encontrado. Recarregue a tela.',
  turno_ja_fechado: 'Este turno já foi encerrado. Recarregue a tela.'
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
