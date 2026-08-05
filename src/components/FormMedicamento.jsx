import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase.js'
import { fmtForma } from '../lib/formato.js'
import CampoRecorrencia, { erroRecorrencia } from './CampoRecorrencia.jsx'
import { proximosDias, geraDoseNoDia, fmtDiaCurto, fmtDiaSemanaCurto } from '../lib/recorrencia.js'

const FUSO = 'America/Sao_Paulo'

function hojeLocal() {
  return new Date().toLocaleDateString('en-CA', { timeZone: FUSO })
}

// Formata "Nome dosagem — forma" para exibir um item do catálogo.
function rotuloCatalogo(item) {
  const dose = item.dosagem ? ` ${item.dosagem}` : ''
  const forma = item.forma_farmaceutica ? ` — ${item.forma_farmaceutica}` : ''
  return `${item.nome}${dose}${forma}`
}

// Sem acento/caixa, para comparar o texto livre de "Outra" com a lista
// fechada (BUG-012): "Comprimido" e "comprimido" são o mesmo rótulo.
function normalizarForma(texto) {
  return texto
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .trim()
    .toLowerCase()
}

// Cadastro/edição de medicamento (DEC-035): nome/dosagem/forma vêm do CATÁLOGO
// da casa (entidade compartilhada), nunca de texto livre na tela do residente —
// editar por texto mudaria o remédio de todos os residentes vinculados ao item.
// O medicamento é a) selecionar um item existente (busca por nome) ou b) criar
// um item novo do catálogo. criterio_uso/observacoes/tipo/estoque_minimo continuam por
// residente e sempre editáveis.
//
// No CADASTRO (não na edição) há ainda o estoque inicial opcional da Sessão #8
// e, desde a Sessão #10, os HORÁRIOS do medicamento contínuo — sem eles o
// cadastro nascia incompleto: um contínuo sem horário não gera dose na ronda.
// SOS continua sem horários (dose avulsa, DEC-014), então o bloco só aparece
// para o tipo contínuo.
//
// Na EDIÇÃO os horários não aparecem aqui de propósito: alterar horário de um
// medicamento com histórico é ato versionado (DEC-026, via `atualizar_horario`)
// e tem tela própria na ficha do medicamento, que mostra a versão desativada e
// a nova. Duplicar isso no modal esconderia o versionamento.
//
// Componente compartilhado pelas duas portas de cadastro: a gestão de
// residentes e o atalho "+ Medicamento" da aba Estoque.
// `daCasa`: o medicamento é do estoque compartilhado da casa (DEC-044). Nesse
// caso o tipo é SOS e ponto — a casa não tem contínuo compartilhado (contínuo
// tem horário, e horário é de alguém). O banco também recusa qualquer outra
// coisa; aqui o seletor só não oferece o que seria rejeitado.
export default function FormMedicamento({
  medicamento,
  daCasa = false,
  subtitulo,
  ocupado,
  erroServidor,
  onFechar,
  onSalvar
}) {
  // catalogo escolhido: { id, nome, dosagem, forma_farmaceutica, unidade_dose,
  // gotas_por_ml, volume_frasco_ml } | null. unidade_dose e companhia (DEC-051)
  // vêm do embed `catalogo:catalogo_medicamentos(...)` que a tela de gestão
  // passa em `medicamento`, ou direto do resultado da busca.
  const [catalogo, setCatalogo] = useState(
    medicamento
      ? {
          id: medicamento.catalogo_id,
          nome: medicamento.nome,
          dosagem: medicamento.dosagem,
          forma_farmaceutica: medicamento.forma_farmaceutica,
          unidade_dose: medicamento.catalogo?.unidade_dose ?? null,
          gotas_por_ml: medicamento.catalogo?.gotas_por_ml ?? null,
          volume_frasco_ml: medicamento.catalogo?.volume_frasco_ml ?? null
        }
      : null
  )
  // 'escolhido' (item definido) | 'buscar' (procurando) | 'novo' (criando item).
  const [modo, setModo] = useState(medicamento ? 'escolhido' : 'buscar')
  const [termo, setTermo] = useState('')
  const [resultados, setResultados] = useState([])
  // Lista fechada de forma farmacêutica (DEC-054): vem do banco
  // (formas_farmaceuticas), não mais de uma constante no cliente — só assim o
  // catálogo e a tela nunca divergem sobre o que é "Comprimido" ou "Xarope".
  const [formas, setFormas] = useState([])
  useEffect(() => {
    supabase
      .from('formas_farmaceuticas')
      .select('id, nome, unidade_dose')
      .eq('ativo', true)
      .order('ordem')
      .then(({ data, error }) => setFormas(error ? [] : data))
  }, [])
  // Forma farmacêutica de item novo: lista fechada (formaEscolha = id de
  // formas_farmaceuticas) + "Outra" (texto livre, formaEscolha = 'outra').
  const [novo, setNovo] = useState({
    nome: '',
    dosagem: '',
    formaEscolha: '',
    formaLivre: '',
    gotasPorMl: '20',
    volumeFrascoMl: ''
  })
  const [erroCatalogo, setErroCatalogo] = useState(null)

  // Derivados da escolha de forma no modo 'novo'.
  const formaFechadaNovo = formas.find((f) => f.id === novo.formaEscolha)
  const unidadeDoseNovo = novo.formaEscolha === '' ? null : formaFechadaNovo ? formaFechadaNovo.unidade_dose : 'unidade'
  const formaFinalNovo = novo.formaEscolha === 'outra' ? novo.formaLivre.trim() : (formaFechadaNovo?.nome ?? '')
  const precisaGotasNovo = unidadeDoseNovo === 'gota'
  const precisaVolumeNovo = unidadeDoseNovo === 'gota' || unidadeDoseNovo === 'ml'

  // Unidade/fator "em vigor" para os rótulos e a conversão de estoque mínimo
  // em frascos (Parte 5): do item novo sendo criado, ou do catálogo escolhido.
  const unidadeAtual = modo === 'novo' ? unidadeDoseNovo : catalogo?.unidade_dose ?? null
  const formaAtual = modo === 'novo' ? formaFinalNovo : catalogo?.forma_farmaceutica ?? null
  const gotasPorMlAtual = modo === 'novo' ? novo.gotasPorMl : catalogo?.gotas_por_ml
  const volumeFrascoMlAtual = modo === 'novo' ? novo.volumeFrascoMl : catalogo?.volume_frasco_ml
  const rotuloUnidadePlural = fmtForma(2, formaAtual, unidadeAtual)
  const liquidoAtual = unidadeAtual === 'gota' || unidadeAtual === 'ml'
  // Só converte estoque mínimo pra frascos se o fator estiver completo —
  // senão o campo cai para a unidade da dose mesmo (gotas/ml crus).
  const podeConverterFrascos =
    liquidoAtual &&
    Number(volumeFrascoMlAtual) > 0 &&
    (unidadeAtual !== 'gota' || Number(gotasPorMlAtual) > 0)
  const fatorMlPorFrasco = () =>
    Number(volumeFrascoMlAtual) * (unidadeAtual === 'gota' ? Number(gotasPorMlAtual) : 1)

  // Posologia estruturada (DEC-057): criterio_uso é exclusivo de SOS
  // ("Quando administrar" — o que decide a dose avulsa); observacoes é livre,
  // para os dois tipos.
  const [criterioUso, setCriterioUso] = useState(medicamento?.criterio_uso ?? '')
  const [observacoes, setObservacoes] = useState(medicamento?.observacoes ?? '')
  const [tipo, setTipo] = useState(daCasa ? 'sos' : medicamento?.tipo ?? 'continuo')
  // Sempre canônico (unidade da dose — DEC-027), igual ao que a RPC espera. Em
  // líquido com fator completo, o CAMPO exibe frascos (Parte 5); a conversão é
  // só de exibição, feita em onChangeEstoqueMinimo/estoqueMinimoDisplay abaixo.
  const [estoqueMinimo, setEstoqueMinimo] = useState(
    medicamento?.estoque_minimo != null ? String(Number(medicamento.estoque_minimo)) : ''
  )
  const estoqueMinimoDisplay =
    podeConverterFrascos && estoqueMinimo !== ''
      ? String(Number(estoqueMinimo) / fatorMlPorFrasco())
      : estoqueMinimo
  function onChangeEstoqueMinimo(valor) {
    if (valor === '') {
      setEstoqueMinimo('')
      return
    }
    setEstoqueMinimo(podeConverterFrascos ? String(Number(valor) * fatorMlPorFrasco()) : valor)
  }

  // Estoque inicial (Sessão #8) — só no cadastro; em branco = sem movimentação.
  // Desde a Sessão #11 leva lote (opcional) e validade (obrigatória — DEC-041).
  const [qtdInicial, setQtdInicial] = useState('')
  const [origemInicial, setOrigemInicial] = useState('compra')
  const [dataInicial, setDataInicial] = useState(hojeLocal())
  const [loteInicial, setLoteInicial] = useState('')
  const [validadeInicial, setValidadeInicial] = useState('')

  // Horários (Sessão #10) — só no cadastro de contínuo. Começa com um cartão
  // em branco: a grade é o que faz o medicamento existir na ronda. Desde a
  // Sessão #17 (BUG-013) cada cartão carrega sua própria recorrência
  // (DEC-055) — a recorrência é por horário, não única para o medicamento (o
  // caso do omeprazol em ciclos diferentes na mesma hora não cabe num padrão
  // só).
  const [horarios, setHorarios] = useState([novoHorario()])
  const [erroHorarios, setErroHorarios] = useState(null)

  function novoHorario() {
    return {
      hora: '',
      qtdDose: '1',
      recorrenciaTipo: 'diario',
      diasSemana: [],
      intervaloDias: '2',
      dataReferencia: hojeLocal()
    }
  }

  function atualizarHorario(i, patch) {
    setErroHorarios(null)
    setHorarios((lista) => lista.map((item, j) => (j === i ? { ...item, ...patch } : item)))
  }

  // Para diasSemana especificamente: CampoRecorrencia manda uma função
  // atualizadora, não o array pronto (ver comentário em alternarDiaSemana),
  // porque dois toques em botões diferentes podem cair no mesmo lote do
  // React antes do primeiro re-render.
  function atualizarDiasSemanaHorario(i, fn) {
    setErroHorarios(null)
    setHorarios((lista) =>
      lista.map((item, j) => (j === i ? { ...item, diasSemana: fn(item.diasSemana) } : item))
    )
  }

  useEffect(() => {
    if (modo !== 'buscar') return
    const t = termo.trim()
    if (t.length < 2) {
      setResultados([])
      return
    }
    let cancelado = false
    supabase
      .from('catalogo_medicamentos')
      .select('id, nome, dosagem, forma_farmaceutica, unidade_dose, gotas_por_ml, volume_frasco_ml')
      .eq('ativo', true)
      .ilike('nome', `%${t}%`)
      .order('nome')
      .limit(15)
      .then(({ data }) => {
        if (!cancelado) setResultados(data ?? [])
      })
    return () => {
      cancelado = true
    }
  }, [termo, modo])

  // Horários informados, sem linha em branco. Só valem no cadastro de contínuo.
  const horariosInformados =
    !medicamento && tipo === 'continuo' ? horarios.filter((h) => h.hora !== '') : []

  // Calendário de conferência do cadastro (Parte 4, Sessão #17): próximos 14
  // dias, considerando TODOS os horários do formulário juntos — é a visão que
  // corresponde ao modelo mental da cuidadora ("neste dia, duas doses"), não
  // um calendário por cartão. Mesmo padrão do FormHorario (`previewPorDia`).
  // Prévia pura: não persiste nada.
  const diasPreview = proximosDias(14)
  const previewPorDia = diasPreview.map((dia) => ({
    dia,
    horas: horariosInformados
      .filter((h) => geraDoseNoDia(h, dia))
      .map((h) => h.hora)
      .sort()
  }))

  function submeter(e) {
    e.preventDefault()
    setErroCatalogo(null)
    setErroHorarios(null)
    let catalogoId = null
    let nome = ''
    let dosagem = ''
    let forma = ''
    let formaId = null
    let gotasPorMl = null
    let volumeFrascoMl = null
    if (modo === 'escolhido' && catalogo?.id) {
      catalogoId = catalogo.id
    } else if (modo === 'novo') {
      nome = novo.nome.trim()
      dosagem = novo.dosagem.trim()
      forma = formaFinalNovo
      formaId = novo.formaEscolha === 'outra' ? null : (formaFechadaNovo?.id ?? null)
      if (nome === '') {
        setErroCatalogo('Informe o nome do medicamento.')
        return
      }
      if (novo.formaEscolha === 'outra' && forma === '') {
        setErroCatalogo('Informe a forma farmacêutica, ou volte e escolha uma da lista.')
        return
      }
      if (
        novo.formaEscolha === 'outra' &&
        formas.some((f) => normalizarForma(f.nome) === normalizarForma(forma))
      ) {
        setErroCatalogo('Esta forma já está na lista — volte e selecione-a em vez de digitar.')
        return
      }
      if (precisaGotasNovo && !(Number(novo.gotasPorMl) > 0)) {
        setErroCatalogo('Informe quantas gotas tem 1 ml (confira na bula — 20 é só sugestão).')
        return
      }
      if (precisaVolumeNovo && !(Number(novo.volumeFrascoMl) > 0)) {
        setErroCatalogo('Informe o volume do frasco, em ml.')
        return
      }
      gotasPorMl = precisaGotasNovo ? Number(novo.gotasPorMl) : null
      volumeFrascoMl = precisaVolumeNovo ? Number(novo.volumeFrascoMl) : null
    } else {
      setErroCatalogo('Selecione um medicamento do catálogo ou crie um novo item.')
      return
    }

    // Contínuo sem horário não entra em ronda nenhuma — era exatamente o
    // cadastro incompleto que esta tela passou a resolver (Sessão #10).
    if (!medicamento && tipo === 'continuo') {
      if (horariosInformados.length === 0) {
        setErroHorarios(
          'Informe ao menos um horário: sem horário, o medicamento contínuo não gera doses na ronda.'
        )
        return
      }
      const horas = horariosInformados.map((h) => h.hora)
      if (new Set(horas).size !== horas.length) {
        setErroHorarios('Há horários repetidos — cada horário do medicamento deve ser único.')
        return
      }
      if (horariosInformados.some((h) => !(Number(h.qtdDose) > 0))) {
        setErroHorarios('A dose de cada horário deve ser maior que zero, em passos de 0,5.')
        return
      }
      // Recorrência por cartão (DEC-055, Sessão #17): com vários horários na
      // tela, um erro genérico não diz qual corrigir — aponta pelo horário.
      for (const h of horariosInformados) {
        const erroRec = erroRecorrencia(h)
        if (erroRec) {
          setErroHorarios(`Horário ${h.hora}: ${erroRec}`)
          return
        }
      }
    }

    // Critério de uso é obrigatório em SOS (DEC-057) — é o que decide a dose
    // avulsa; sem ele a tela de dose SOS fica sem a informação mais importante.
    if (tipo === 'sos' && criterioUso.trim() === '') {
      setErroCatalogo('Informe quando administrar (ex.: "Se dor ou febre").')
      return
    }

    onSalvar({
      catalogoId,
      nome,
      dosagem,
      forma,
      // Só usados quando catalogoId é null (item novo de catálogo — DEC-054).
      formaId,
      gotasPorMl,
      volumeFrascoMl,
      criterioUso: tipo === 'sos' ? criterioUso.trim() : null,
      observacoes: observacoes.trim(),
      tipo,
      // Estoque mínimo só faz sentido para SOS (DEC-027).
      estoqueMinimo: tipo === 'sos' && estoqueMinimo !== '' ? Number(estoqueMinimo) : null,
      // Criados logo após o medicamento, pela RPC criar_horario (Sessão #10).
      // Recorrência por horário desde a Sessão #17 (DEC-055, BUG-013).
      horarios: horariosInformados.map((h) => ({
        hora: h.hora,
        qtdDose: Number(h.qtdDose),
        recorrenciaTipo: h.recorrenciaTipo,
        diasSemana: h.recorrenciaTipo === 'dias_semana' ? h.diasSemana : null,
        intervaloDias: h.recorrenciaTipo === 'intervalo' ? Number(h.intervaloDias) : null,
        dataReferencia: h.recorrenciaTipo === 'intervalo' ? h.dataReferencia : null
      })),
      estoqueInicial:
        !medicamento && qtdInicial !== '' && Number(qtdInicial) > 0
          ? {
              quantidade: Number(qtdInicial),
              origem: origemInicial,
              data: origemInicial === 'compra' ? dataInicial : null,
              lote: loteInicial.trim(),
              validade: validadeInicial,
              // Fator congelado no lote (DEC-053), quando o item é líquido.
              gotasPorMl: liquidoAtual && unidadeAtual === 'gota' ? Number(gotasPorMlAtual) : null
            }
          : null
    })
  }

  return (
    <div className="modal-fundo" onClick={onFechar}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>{medicamento ? `Editar ${medicamento.nome}` : 'Novo medicamento'}</h3>
        {subtitulo && <p className="modal-subtitulo">{subtitulo}</p>}
        <form className="formulario" onSubmit={submeter}>
          <div className="catalogo-bloco">
            <span className="catalogo-rotulo">Medicamento (catálogo da casa)</span>

            {modo === 'escolhido' && (
              <div className="catalogo-escolhido">
                <span className="catalogo-escolhido-nome">
                  {catalogo ? rotuloCatalogo(catalogo) : '—'}
                </span>
                <button
                  type="button"
                  className="botao-mini"
                  onClick={() => {
                    setModo('buscar')
                    setTermo('')
                    setResultados([])
                  }}
                >
                  Trocar
                </button>
              </div>
            )}

            {modo === 'buscar' && (
              <>
                <input
                  autoFocus
                  value={termo}
                  placeholder="Buscar por nome (ex.: Losartana)"
                  onChange={(e) => setTermo(e.target.value)}
                />
                {termo.trim().length >= 2 && (
                  <ul className="catalogo-resultados">
                    {resultados.map((item) => (
                      <li key={item.id}>
                        <button
                          type="button"
                          className="catalogo-opcao"
                          onClick={() => {
                            setCatalogo(item)
                            setModo('escolhido')
                            setErroCatalogo(null)
                          }}
                        >
                          {rotuloCatalogo(item)}
                        </button>
                      </li>
                    ))}
                    {resultados.length === 0 && (
                      <li className="catalogo-vazio">Nada encontrado no catálogo.</li>
                    )}
                  </ul>
                )}
                <button
                  type="button"
                  className="botao-secundario botao-catalogo-novo"
                  onClick={() => {
                    setNovo({ nome: termo.trim(), dosagem: '', formaEscolha: '', formaLivre: '', gotasPorMl: '20', volumeFrascoMl: '' })
                    setModo('novo')
                    setErroCatalogo(null)
                  }}
                >
                  + Criar novo item do catálogo
                </button>
                {medicamento && (
                  <button
                    type="button"
                    className="botao-mini catalogo-cancelar-troca"
                    onClick={() => setModo('escolhido')}
                  >
                    Cancelar troca
                  </button>
                )}
              </>
            )}

            {modo === 'novo' && (
              <>
                <label>
                  Nome
                  <input
                    autoFocus
                    value={novo.nome}
                    onChange={(e) => setNovo((n) => ({ ...n, nome: e.target.value }))}
                    required
                  />
                </label>
                <div className="formulario-linha">
                  <label>
                    Dosagem
                    <input
                      value={novo.dosagem}
                      placeholder="ex.: 50 mg"
                      onChange={(e) => setNovo((n) => ({ ...n, dosagem: e.target.value }))}
                    />
                  </label>
                  <label>
                    Forma farmacêutica
                    <select
                      value={novo.formaEscolha}
                      onChange={(e) => setNovo((n) => ({ ...n, formaEscolha: e.target.value }))}
                    >
                      <option value="">— selecione —</option>
                      {formas.map((f) => (
                        <option key={f.id} value={f.id}>
                          {f.nome}
                        </option>
                      ))}
                      <option value="outra">Outra (especificar)</option>
                    </select>
                  </label>
                </div>
                {novo.formaEscolha === 'outra' && (
                  <label>
                    Qual forma?
                    <input
                      value={novo.formaLivre}
                      placeholder="ex.: creme, spray nasal"
                      onChange={(e) => setNovo((n) => ({ ...n, formaLivre: e.target.value }))}
                    />
                  </label>
                )}
                {precisaGotasNovo && (
                  <label>
                    Gotas por ml
                    <input
                      type="number"
                      min="1"
                      step="1"
                      inputMode="decimal"
                      value={novo.gotasPorMl}
                      onChange={(e) => setNovo((n) => ({ ...n, gotasPorMl: e.target.value }))}
                    />
                    <span className="bloco-explicacao">
                      20 é a referência usual, mas varia com o conta-gotas e a viscosidade —
                      confira na bula deste medicamento.
                    </span>
                  </label>
                )}
                {precisaVolumeNovo && (
                  <label>
                    Volume do frasco (ml)
                    <input
                      type="number"
                      min="1"
                      step="1"
                      inputMode="decimal"
                      placeholder="ex.: 10"
                      value={novo.volumeFrascoMl}
                      onChange={(e) => setNovo((n) => ({ ...n, volumeFrascoMl: e.target.value }))}
                    />
                  </label>
                )}
                <button
                  type="button"
                  className="botao-mini"
                  onClick={() => {
                    setModo('buscar')
                    setErroCatalogo(null)
                  }}
                >
                  ‹ Voltar à busca
                </button>
              </>
            )}

            {erroCatalogo && <p className="aviso aviso-erro">{erroCatalogo}</p>}
          </div>

          {daCasa ? (
            <p className="card-sos">
              Medicamento da casa é sempre <strong>SOS</strong> (dose avulsa):
              contínuo tem horário de ronda, e horário é de um residente.
            </p>
          ) : (
            <label>
              Tipo
              <select value={tipo} onChange={(e) => setTipo(e.target.value)}>
                <option value="continuo">Contínuo (com horários de ronda)</option>
                <option value="sos">SOS (dose avulsa, sem horários)</option>
              </select>
            </label>
          )}
          {tipo === 'sos' && (
            <label>
              Quando administrar
              <textarea
                rows={2}
                placeholder="ex.: Se dor ou febre"
                value={criterioUso}
                onChange={(e) => setCriterioUso(e.target.value)}
                required
              />
              <span className="bloco-explicacao">
                O critério que decide a dose avulsa — aparece em destaque na tela de dose SOS.
              </span>
            </label>
          )}
          {tipo === 'sos' && (
            <label>
              {/* Frasco na entrada/exibição (Parte 5); o valor gravado continua
                  na unidade da dose (DEC-027) — só a conversão muda. */}
              Estoque mínimo de segurança em {podeConverterFrascos ? 'frascos' : rotuloUnidadePlural} (opcional)
              <input
                type="number"
                min="0"
                step={podeConverterFrascos ? '0.1' : '0.5'}
                inputMode="decimal"
                placeholder="alerta de recompra abaixo desta quantidade"
                value={estoqueMinimoDisplay}
                onChange={(e) => onChangeEstoqueMinimo(e.target.value)}
              />
            </label>
          )}

          {/* Horários da ronda (Sessão #10) — só no cadastro de contínuo. Cada
              horário é um cartão (Sessão #17, BUG-013): a 375px hora + dose +
              recorrência não cabem numa linha só, e a recorrência é por
              horário, nunca única para o medicamento (DEC-055). */}
          {!medicamento && tipo === 'continuo' && (
            <div className="catalogo-bloco">
              <span className="catalogo-rotulo">Horários das rondas</span>
              <p className="bloco-explicacao">
                É o que gera as doses na ronda. Um cartão por horário, com a
                dose e a repetição daquele horário.
              </p>
              {horarios.map((h, i) => (
                <div className="catalogo-bloco horario-cartao" key={i}>
                  <div className="formulario-linha">
                    <label>
                      Horário
                      <input
                        type="time"
                        value={h.hora}
                        onChange={(e) => atualizarHorario(i, { hora: e.target.value })}
                      />
                    </label>
                    <label>
                      Dose ({rotuloUnidadePlural}, passos de 0,5)
                      <input
                        type="number"
                        min="0.5"
                        step="0.5"
                        inputMode="decimal"
                        value={h.qtdDose}
                        onChange={(e) => atualizarHorario(i, { qtdDose: e.target.value })}
                      />
                    </label>
                  </div>
                  <CampoRecorrencia
                    recorrenciaTipo={h.recorrenciaTipo}
                    onChangeRecorrenciaTipo={(v) => atualizarHorario(i, { recorrenciaTipo: v })}
                    diasSemana={h.diasSemana}
                    onChangeDiasSemana={(fn) => atualizarDiasSemanaHorario(i, fn)}
                    intervaloDias={h.intervaloDias}
                    onChangeIntervaloDias={(v) => atualizarHorario(i, { intervaloDias: v })}
                    dataReferencia={h.dataReferencia}
                    onChangeDataReferencia={(v) => atualizarHorario(i, { dataReferencia: v })}
                  />
                  {horarios.length > 1 && (
                    <button
                      type="button"
                      className="botao-mini botao-mini-perigo horario-cartao-remover"
                      aria-label={`Remover o ${i + 1}º horário`}
                      onClick={() => {
                        setErroHorarios(null)
                        setHorarios((lista) => lista.filter((_, j) => j !== i))
                      }}
                    >
                      Remover
                    </button>
                  )}
                </div>
              ))}
              <button
                type="button"
                className="botao-secundario botao-catalogo-novo"
                onClick={() => setHorarios((lista) => [...lista, novoHorario()])}
              >
                + Adicionar horário
              </button>
              {erroHorarios && <p className="aviso aviso-erro">{erroHorarios}</p>}

              {/* Calendário de conferência (Parte 4): a cuidadora não pensa
                  "8h a cada 2 dias" — pensa "dia sim dia não, num dia duas
                  doses". O calendário traduz o padrão sem exigir que ela
                  entenda o modelo. */}
              <div className="calendario-conferencia">
                <span className="catalogo-rotulo">Próximos dias (conferência)</span>
                <ul className="calendario-lista">
                  {previewPorDia.map(({ dia, horas }) => (
                    <li key={dia.toISOString()} className="calendario-dia">
                      <span className="calendario-dia-data">
                        {fmtDiaSemanaCurto(dia)} {fmtDiaCurto(dia)}
                      </span>
                      <span className="calendario-dia-horas">
                        {horas.length > 0 ? horas.join(' · ') : '—'}
                      </span>
                    </li>
                  ))}
                </ul>
              </div>
            </div>
          )}

          {!medicamento && (
            <div className="catalogo-bloco">
              <span className="catalogo-rotulo">Estoque inicial (opcional)</span>
              <label>
                Quantidade{formaAtual || unidadeAtual ? ` (${rotuloUnidadePlural})` : ''}
                <input
                  type="number"
                  min="0"
                  step="0.5"
                  inputMode="decimal"
                  placeholder="deixe em branco para não lançar nada"
                  value={qtdInicial}
                  onChange={(e) => setQtdInicial(e.target.value)}
                />
              </label>
              {qtdInicial !== '' && Number(qtdInicial) > 0 && (
                <>
                  <label>
                    De onde veio
                    <select
                      value={origemInicial}
                      onChange={(e) => setOrigemInicial(e.target.value)}
                    >
                      <option value="compra">Compra (entrada no estoque)</option>
                      <option value="remanescente">
                        Já estava na prateleira (ajuste de contagem)
                      </option>
                    </select>
                  </label>
                  <div className="formulario-linha">
                    <label>
                      Lote (opcional)
                      <input
                        value={loteInicial}
                        placeholder="código da caixa"
                        onChange={(e) => setLoteInicial(e.target.value)}
                      />
                    </label>
                    <label>
                      Validade
                      <input
                        type="date"
                        value={validadeInicial}
                        onChange={(e) => setValidadeInicial(e.target.value)}
                        required
                      />
                    </label>
                  </div>
                  {origemInicial === 'compra' && (
                    <label>
                      Data da compra
                      <input
                        type="date"
                        max={hojeLocal()}
                        value={dataInicial}
                        onChange={(e) => setDataInicial(e.target.value)}
                      />
                    </label>
                  )}
                </>
              )}
            </div>
          )}

          <label>
            Observações (opcional)
            <textarea rows={2} value={observacoes} onChange={(e) => setObservacoes(e.target.value)} />
          </label>

          {erroServidor && <p className="aviso aviso-erro">{erroServidor}</p>}
          <div className="modal-acoes">
            <button type="button" className="botao-secundario" onClick={onFechar} disabled={ocupado}>
              Cancelar
            </button>
            <button type="submit" className="botao-primario" disabled={ocupado}>
              {ocupado ? 'Salvando…' : 'Salvar'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
