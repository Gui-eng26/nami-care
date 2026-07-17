// Dados de teste do Nami Care — TODOS os nomes são fictícios (LGPD, BRIEFING.md §9).
// Fonte única para scripts/seed.js. Espelha o piloto: 4 cuidadores, 11 idosos,
// ~25 medicamentos com horários que colidem de propósito (08:00, 12:00, 20:00)
// para exercitar a rodada de medicação.

// admin: acesso à área de gestão (DEC-024). A administradora real (Thais)
// será criada no cadastro dos dados reais (Sessão #5).
export const cuidadores = [
  { nome: 'Ana Souza', pin: '1111', admin: true },
  { nome: 'Beatriz Lima', pin: '2222' },
  { nome: 'Carlos Pereira', pin: '3333' },
  { nome: 'Débora Santos', pin: '4444' }
]

export const idosos = [
  { nome: 'Alzira Nogueira', nascimento: '1938-03-12', observacoes: 'Dieta pastosa; usa espessante nos líquidos' },
  { nome: 'Benedito Farias', nascimento: '1935-07-01', observacoes: null },
  { nome: 'Cecília Prado', nascimento: '1941-11-23', observacoes: 'Alergia a dipirona' },
  { nome: 'Dorival Campos', nascimento: '1939-05-30', observacoes: null },
  { nome: 'Esther Vilela', nascimento: '1943-02-14', observacoes: null },
  { nome: 'Firmino Duarte', nascimento: '1936-09-08', observacoes: 'Cadeirante; auxílio para deglutir comprimidos grandes' },
  { nome: 'Guiomar Peixoto', nascimento: '1940-12-19', observacoes: null },
  { nome: 'Hélio Sampaio', nascimento: '1937-04-25', observacoes: null },
  { nome: 'Iracema Barros', nascimento: '1944-08-03', observacoes: 'Recusa frequente à noite; oferecer com suco' },
  { nome: 'Joaquim Teles', nascimento: '1934-10-16', observacoes: null },
  { nome: 'Lourdes Quintana', nascimento: '1942-06-27', observacoes: null }
]

// horarios: [hora, qtd_dose]; estoqueInicial: quantidade da entrada_compra do seed.
// Medicamentos tipo 'sos' não têm horários (DEC-014).
export const medicamentos = [
  { idoso: 'Alzira Nogueira', nome: 'Losartana', dosagem: '50 mg', forma: 'comprimido', posologia: '1 comprimido de 12 em 12 horas', tipo: 'continuo', horarios: [['08:00', 1], ['20:00', 1]], estoqueInicial: 60 },
  { idoso: 'Alzira Nogueira', nome: 'Sinvastatina', dosagem: '20 mg', forma: 'comprimido', posologia: '1 comprimido à noite', tipo: 'continuo', horarios: [['20:00', 1]], estoqueInicial: 12 },

  { idoso: 'Benedito Farias', nome: 'Metformina', dosagem: '850 mg', forma: 'comprimido', posologia: '1 comprimido no café, almoço e jantar', tipo: 'continuo', horarios: [['08:00', 1], ['12:00', 1], ['20:00', 1]], estoqueInicial: 90 },
  { idoso: 'Benedito Farias', nome: 'AAS', dosagem: '100 mg', forma: 'comprimido', posologia: '1 comprimido pela manhã, após o café', tipo: 'continuo', horarios: [['08:00', 1]], estoqueInicial: 30 },

  { idoso: 'Cecília Prado', nome: 'Levotiroxina', dosagem: '50 mcg', forma: 'comprimido', posologia: '1 comprimido em jejum, 30 min antes do café', tipo: 'continuo', horarios: [['07:00', 1]], estoqueInicial: 30 },
  { idoso: 'Cecília Prado', nome: 'Paracetamol', dosagem: '750 mg', forma: 'comprimido', posologia: 'Se dor ou febre, até 3x ao dia (NUNCA dipirona — alergia)', tipo: 'sos', horarios: [], estoqueInicial: 20 },

  { idoso: 'Dorival Campos', nome: 'Anlodipino', dosagem: '5 mg', forma: 'comprimido', posologia: '1 comprimido pela manhã', tipo: 'continuo', horarios: [['08:00', 1]], estoqueInicial: 30 },
  { idoso: 'Dorival Campos', nome: 'Quetiapina', dosagem: '25 mg', forma: 'comprimido', posologia: 'Meio comprimido à noite', tipo: 'continuo', horarios: [['20:00', 0.5]], estoqueInicial: 30 },

  { idoso: 'Esther Vilela', nome: 'Sertralina', dosagem: '50 mg', forma: 'comprimido', posologia: '1 comprimido pela manhã', tipo: 'continuo', horarios: [['08:00', 1]], estoqueInicial: 30 },
  { idoso: 'Esther Vilela', nome: 'Omeprazol', dosagem: '20 mg', forma: 'cápsula', posologia: '1 cápsula em jejum', tipo: 'continuo', horarios: [['07:00', 1]], estoqueInicial: 28 },

  { idoso: 'Firmino Duarte', nome: 'Furosemida', dosagem: '40 mg', forma: 'comprimido', posologia: 'Meio comprimido pela manhã', tipo: 'continuo', horarios: [['08:00', 0.5]], estoqueInicial: 30 },
  { idoso: 'Firmino Duarte', nome: 'Espironolactona', dosagem: '25 mg', forma: 'comprimido', posologia: '1 comprimido pela manhã', tipo: 'continuo', horarios: [['08:00', 1]], estoqueInicial: 30 },
  { idoso: 'Firmino Duarte', nome: 'Dipirona', dosagem: '1 g', forma: 'comprimido', posologia: 'Se dor, até 4x ao dia', tipo: 'sos', horarios: [], estoqueInicial: 20 },

  { idoso: 'Guiomar Peixoto', nome: 'Donepezila', dosagem: '10 mg', forma: 'comprimido', posologia: '1 comprimido à noite', tipo: 'continuo', horarios: [['20:00', 1]], estoqueInicial: 30 },
  { idoso: 'Guiomar Peixoto', nome: 'Cálcio + vitamina D', dosagem: '500 mg + 400 UI', forma: 'comprimido', posologia: '1 comprimido no almoço', tipo: 'continuo', horarios: [['12:00', 1]], estoqueInicial: 60 },

  { idoso: 'Hélio Sampaio', nome: 'Atenolol', dosagem: '25 mg', forma: 'comprimido', posologia: '1 comprimido de 12 em 12 horas', tipo: 'continuo', horarios: [['08:00', 1], ['20:00', 1]], estoqueInicial: 60 },
  { idoso: 'Hélio Sampaio', nome: 'Clopidogrel', dosagem: '75 mg', forma: 'comprimido', posologia: '1 comprimido no almoço', tipo: 'continuo', horarios: [['12:00', 1]], estoqueInicial: 30 },

  { idoso: 'Iracema Barros', nome: 'Risperidona', dosagem: '1 mg', forma: 'comprimido', posologia: 'Meio comprimido à noite', tipo: 'continuo', horarios: [['20:00', 0.5]], estoqueInicial: 30 },
  { idoso: 'Iracema Barros', nome: 'Escitalopram', dosagem: '10 mg', forma: 'comprimido', posologia: '1 comprimido pela manhã', tipo: 'continuo', horarios: [['08:00', 1]], estoqueInicial: 30 },
  { idoso: 'Iracema Barros', nome: 'Simeticona', dosagem: '125 mg', forma: 'cápsula', posologia: 'Se desconforto abdominal, até 3x ao dia', tipo: 'sos', horarios: [], estoqueInicial: 20 },

  { idoso: 'Joaquim Teles', nome: 'Glibenclamida', dosagem: '5 mg', forma: 'comprimido', posologia: '1 comprimido antes do café e do jantar', tipo: 'continuo', horarios: [['08:00', 1], ['20:00', 1]], estoqueInicial: 60 },
  { idoso: 'Joaquim Teles', nome: 'Tansulosina', dosagem: '0,4 mg', forma: 'cápsula', posologia: '1 cápsula à noite', tipo: 'continuo', horarios: [['20:00', 1]], estoqueInicial: 30 },

  { idoso: 'Lourdes Quintana', nome: 'Losartana', dosagem: '50 mg', forma: 'comprimido', posologia: '1 comprimido pela manhã', tipo: 'continuo', horarios: [['08:00', 1]], estoqueInicial: 30 },
  { idoso: 'Lourdes Quintana', nome: 'Hidroclorotiazida', dosagem: '25 mg', forma: 'comprimido', posologia: '1 comprimido pela manhã', tipo: 'continuo', horarios: [['08:00', 1]], estoqueInicial: 30 }
]
