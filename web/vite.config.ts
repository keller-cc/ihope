import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

export default defineConfig({
  plugins: [react()],
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
