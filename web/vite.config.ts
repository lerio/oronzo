import { cloudflare } from '@cloudflare/vite-plugin'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// The Cloudflare plugin was added by `wrangler deploy` itself, for the static-assets
// deployment target. It is not needed to build or run the app locally — `npm run dev`
// works the same either way — but it is what makes `npm run deploy` a single command.
export default defineConfig({
  plugins: [react(), cloudflare()],
})
