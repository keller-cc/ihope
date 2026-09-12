import path from 'node:path'
import { fileURLToPath } from 'node:url'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'
import { VitePWA } from 'vite-plugin-pwa'

const rootDir = path.dirname(fileURLToPath(import.meta.url))

export default defineConfig({
  resolve: {
    alias: {
      '@': path.resolve(rootDir, 'src'),
    },
  },
  build: {
    // TDesign vendor alone is ~550 kB minified; routes are already lazy-split.
    chunkSizeWarningLimit: 600,
    // Skip per-chunk gzip accounting (noticeable on Docker / CI).
    reportCompressedSize: false,
    rolldownOptions: {
      output: {
        codeSplitting: {
          groups: [
            {
              name: 'react',
              test: /node_modules[\\/](react|react-dom|scheduler)[\\/]/,
              priority: 30,
            },
            {
              name: 'tdesign',
              test: /node_modules[\\/]tdesign-(react|icons-react)[\\/]/,
              priority: 20,
            },
          ],
        },
      },
    },
  },
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      injectRegister: 'auto',
      includeAssets: [
        'favicon.ico',
        'favicon-32.png',
        'apple-touch-icon-180.png',
        'icon-192.png',
        'icon-512.png',
        'icon-maskable-512.png',
      ],
      manifest: {
        name: 'IHope',
        short_name: 'IHope',
        description: 'IHope 即时通讯',
        theme_color: '#12b7f5',
        background_color: '#e6e6e6',
        display: 'standalone',
        orientation: 'any',
        start_url: '/',
        scope: '/',
        lang: 'zh-CN',
        icons: [
          {
            src: 'icon-192.png',
            sizes: '192x192',
            type: 'image/png',
          },
          {
            src: 'icon-512.png',
            sizes: '512x512',
            type: 'image/png',
          },
          {
            src: 'icon-maskable-512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'maskable',
          },
        ],
      },
      workbox: {
        navigateFallback: '/index.html',
        navigateFallbackDenylist: [/^\/api/, /^\/ws/, /^\/uploads/],
        // App shell only — game art is large and fetched on demand.
        globPatterns: ['**/*.{js,css,html,ico,woff2,webmanifest}'],
        globIgnores: ['**/games/**'],
      },
    }),
  ],
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:8090',
        changeOrigin: true,
      },
      '/uploads': {
        target: 'http://127.0.0.1:8090',
        changeOrigin: true,
      },
      '/ws': {
        target: 'ws://127.0.0.1:8090',
        ws: true,
      },
      '/health': {
        target: 'http://127.0.0.1:8090',
        changeOrigin: true,
      },
    },
  },
})
