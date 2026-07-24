// @ts-check
import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://buschfranco.github.io',
  base: '/1of1',
  i18n: {
    defaultLocale: 'es',
    locales: ['es', 'en'],
    routing: {
      prefixDefaultLocale: false,
    },
  },
});
