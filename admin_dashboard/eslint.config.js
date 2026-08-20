import js from '@eslint/js'
import globals from 'globals'
import reactHooks from 'eslint-plugin-react-hooks'
import reactRefresh from 'eslint-plugin-react-refresh'
import tseslint from 'typescript-eslint'
import { defineConfig, globalIgnores } from 'eslint/config'

export default defineConfig([
  globalIgnores(['dist']),
  {
    files: ['**/*.{ts,tsx}'],
    extends: [
      js.configs.recommended,
      tseslint.configs.recommended,
      reactHooks.configs.flat.recommended,
      reactRefresh.configs.vite,
    ],
    languageOptions: {
      ecmaVersion: 2020,
      globals: globals.browser,
    },
    rules: {
      // Supabase yanitlari her yerde `any` olarak dolasiyor; kurali hata
      // yapmak ~20 dosyada tip yazmayi gerektirir ve CI'i pesin bloklar.
      // Uyari olarak birakiyoruz: yeni kod icin gorunur, gecmis borcu
      // dogrulama kapisini kilitlemiyor.
      '@typescript-eslint/no-explicit-any': 'warn',
      // Ayni gerekce: mevcut effect'lerin bagimlilik listeleri elle
      // yonetiliyor, otomatik duzeltme sonsuz dongu riski tasiyor.
      'react-hooks/exhaustive-deps': 'warn',
    },
  },
])
