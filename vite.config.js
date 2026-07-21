import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['icons/apple-touch-icon.png', 'icons/favicon.png'],
      workbox: {
        // O logo horizontal fica no repositório como fonte dos ícones
        // (scripts/gerar-icones.js) e não é usado por nenhuma tela — não faz
        // sentido baixá-lo no precache do celular da casa.
        globIgnores: ['**/logo-serenissima.png']
      },
      manifest: {
        name: 'Residencial Senior Sereníssima',
        short_name: 'Sereníssima',
        description: 'Gestão de medicação — Residencial Senior Sereníssima',
        lang: 'pt-BR',
        start_url: '/',
        scope: '/',
        display: 'standalone',
        orientation: 'portrait',
        background_color: '#faf6ee',
        theme_color: '#8f7038',
        icons: [
          {
            src: '/icons/icon-192.png',
            sizes: '192x192',
            type: 'image/png',
            purpose: 'any'
          },
          {
            src: '/icons/icon-512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'any'
          },
          {
            src: '/icons/icon-maskable-192.png',
            sizes: '192x192',
            type: 'image/png',
            purpose: 'maskable'
          },
          {
            src: '/icons/icon-maskable-512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'maskable'
          }
        ]
      }
    })
  ]
})
