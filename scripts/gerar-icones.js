// Gera os ícones PNG do PWA a partir do logo da casa (Sessão #7).
//
// Uso:
//   npm run icones
//
// Entrada:  public/icons/logo-serenissima.png — logo horizontal da casa
//           (símbolo da casinha + casal + coração, ao lado do texto).
// Saída:    public/icons/icon-192.png, icon-512.png,
//           icon-maskable-192.png, icon-maskable-512.png,
//           apple-touch-icon.png, favicon.png
//
// O ícone de PWA é quadrado e renderiza pequeno: a 192px o texto do logo
// horizontal fica ilegível. Por isso o ícone usa apenas o SÍMBOLO recortado
// (bounding box detectada no logo), centralizado sobre o creme da identidade
// Sereníssima. O logo horizontal completo continua servindo para cabeçalho e
// tela de login, onde há largura.
//
// A composição usa blend "multiply": o fundo branco do recorte vira o creme
// (branco × creme = creme) sem deixar emenda visível, e o traço dourado é
// preservado.

import sharp from 'sharp'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..')
const origem = join(raiz, 'public/icons/logo-serenissima.png')
const destino = join(raiz, 'public/icons')

// Bounding box do símbolo dentro do logo (detectada por varredura de tinta
// dentro do círculo branco, à esquerda do texto). Se o arquivo do logo for
// trocado, recalcular estes valores.
const SIMBOLO = { left: 250, top: 443, width: 147, height: 147 }

const CREME = { r: 0xfa, g: 0xf6, b: 0xee }

// Proporção do símbolo dentro do canvas.
//   any      — 78%: o ícone é recortado em círculo/squircle pelo sistema
//   maskable — 55%: cabe folgado na zona segura (80% central) de qualquer
//              máscara do Android
const PROPORCAO = { any: 0.78, maskable: 0.55 }

async function gerar(tamanho, proporcao, arquivo) {
  const lado = Math.round(tamanho * proporcao)
  const simbolo = await sharp(origem)
    .extract(SIMBOLO)
    .resize(lado, lado, { kernel: 'lanczos3' })
    .removeAlpha()
    .toBuffer()

  const deslocamento = Math.round((tamanho - lado) / 2)
  await sharp({
    create: { width: tamanho, height: tamanho, channels: 3, background: CREME }
  })
    .composite([{ input: simbolo, top: deslocamento, left: deslocamento, blend: 'multiply' }])
    // Traço fino sobre fundo chapado: paleta de 256 cores corta o arquivo em
    // ~20× sem diferença visível, e o ícone entra no precache do service worker.
    .png({ palette: true, compressionLevel: 9 })
    .toFile(join(destino, arquivo))

  console.log(`  ${arquivo} (${tamanho}×${tamanho}, símbolo ${lado}px)`)
}

console.log('Gerando ícones a partir de logo-serenissima.png:')
await gerar(192, PROPORCAO.any, 'icon-192.png')
await gerar(512, PROPORCAO.any, 'icon-512.png')
await gerar(192, PROPORCAO.maskable, 'icon-maskable-192.png')
await gerar(512, PROPORCAO.maskable, 'icon-maskable-512.png')
await gerar(180, PROPORCAO.any, 'apple-touch-icon.png')
await gerar(64, PROPORCAO.any, 'favicon.png')
console.log('OK')
