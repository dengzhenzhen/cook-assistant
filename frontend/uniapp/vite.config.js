import { defineConfig } from 'vite'
import uniPlugin from '@dcloudio/vite-plugin-uni'
import { createRequire } from 'node:module'
const require = createRequire(import.meta.url)

const uni = typeof uniPlugin === 'function' ? uniPlugin : uniPlugin.default
export default defineConfig({ plugins: [uni(), {
  name: 'kaifan-current-i18n-runtime',
  configResolved(config) {
    // DCloud aliases vue-i18n to its embedded v9 runtime. Keep the resolved
    // runtime aligned with the patched v11 packages selected by overrides.
    config.resolve.alias.unshift({ find: /^vue-i18n(?:\/runtime)?$/, replacement: require.resolve('vue-i18n/dist/vue-i18n.runtime.esm-bundler.js') })
  }
}] })
