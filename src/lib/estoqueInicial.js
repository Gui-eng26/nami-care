import { supabase } from './supabase.js'
import { mensagemErro } from './erros.js'

// Estoque inicial no cadastro de medicamento (Sessão #8). Não existe caminho de
// escrita novo: encadeia as RPCs do ledger que já existem (DEC-004/016),
// escolhendo a que conta a verdade sobre a ORIGEM do saldo —
//   compra       → registrar_entrada_estoque (entrada_compra);
//   remanescente → registrar_ajuste_estoque (ajuste_contagem), o registro
//                  honesto para o que já estava na prateleira, de origem não
//                  apurada (mesmo racional do go-live da Sessão #7).
// Ambas já são autorizadas por turno aberto e gravam o cuidador do turno.
//
// Retorna null em caso de sucesso (ou quando não há estoque a lançar) e uma
// mensagem quando o medicamento foi criado mas a movimentação falhou — o
// cadastro não é desfeito; a cuidadora lança pela aba Estoque.
export async function lancarEstoqueInicial(medicamentoId, inicial) {
  if (!inicial || !(inicial.quantidade > 0)) return null

  // Lote + validade acompanham o estoque inicial (DEC-041): a compra cria um
  // lote via registrar_entrada_estoque; o remanescente entra como recontagem
  // para cima (registrar_ajuste_estoque), que também cria o lote do excedente.
  const { data, error } =
    inicial.origem === 'compra'
      ? await supabase.rpc('registrar_entrada_estoque', {
          p_medicamento_id: medicamentoId,
          p_quantidade: inicial.quantidade,
          p_validade: inicial.validade,
          p_lote: inicial.lote || null,
          p_data: inicial.data || null,
          p_observacao: 'Estoque inicial (cadastro do medicamento)'
        })
      : await supabase.rpc('registrar_ajuste_estoque', {
          p_medicamento_id: medicamentoId,
          p_quantidade_contada: inicial.quantidade,
          p_observacao: 'Estoque inicial (remanescente na prateleira)',
          p_lote: inicial.lote || null,
          p_validade: inicial.validade
        })

  if (error) {
    return 'Medicamento cadastrado, mas o estoque inicial não foi lançado (falha de conexão). Registre pela aba Estoque.'
  }
  if (!data.ok) {
    return `Medicamento cadastrado, mas o estoque inicial não foi lançado: ${mensagemErro(data)}`
  }
  return null
}
