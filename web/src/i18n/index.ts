import en from './en.json';
import es from './es.json';

const translations = { en, es };

export function useTranslations(lang) {
  return translations[lang] || translations.es;
}
