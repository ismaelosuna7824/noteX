import { en } from './en';
import { es } from './es';
import { defaultLang, languages, type Content, type Lang } from './types';

export { defaultLang, languages };
export type { Content, Lang };

const content: Record<Lang, Content> = { en, es };

/** Narrow whatever Astro hands us — currentLocale is typed as a loose string. */
export const toLang = (value: string | undefined): Lang =>
  languages.includes(value as Lang) ? (value as Lang) : defaultLang;

export const getContent = (value: string | undefined): Content => content[toLang(value)];

/*
  The default locale is not prefixed — English lives at `/`, Spanish at `/es`.

  Prefixing both would mean the bare domain has to redirect somewhere, which
  costs a round trip on the most-linked URL there is and makes every existing
  link to notex.fun a redirect. The default language earns the root.

  No trailing slash, and that is not cosmetic. Firebase Hosting is configured
  with trailingSlash:false, so it redirects `/es/` to `/es`. Astro's default
  canonical is built from Astro.url.pathname, which IS `/es/` — pointing the
  canonical and every hreflang at a URL that 301s.

  So canonical does not come from the pathname: it comes from here, like every
  other URL on the page. One function, one answer, nothing to keep in sync.
*/
export const pathFor = (lang: Lang): string => (lang === defaultLang ? '/' : `/${lang}`);

/** The other languages, for the switcher. */
export const alternatesFor = (lang: Lang) => languages.filter((l) => l !== lang);

/**
 * Absolute URL of this page in a given language, for hreflang and canonical.
 * Search engines need the full origin; a relative path is ignored.
 */
export const urlFor = (lang: Lang, site: URL | undefined): string =>
  new URL(pathFor(lang), site ?? 'https://notex.fun').href;
