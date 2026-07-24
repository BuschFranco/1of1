import en from './en.json';
import es from './es.json';

const translations = { en, es };

export function getLang(Astro) {
  const url = Astro.url.pathname;
  if (url.startsWith('/en')) return 'en';
  return 'es';
}

export function useTranslations(lang) {
  return translations[lang] || translations.es;
}
