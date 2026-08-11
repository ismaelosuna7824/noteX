/*
  The shape every language must fill.

  Copy is keyed, never positional. A locale file cannot silently drift out of
  order from another, and a missing key is a type error at build time rather
  than an English sentence appearing on the Spanish page.

  Anything that is not language — the repo URL, version, asset filenames, icon
  paths, the graph's geometry — stays in data/site.ts. Duplicating an SVG path
  across two locales is how one of them ends up a year out of date.
*/

export const languages = ['en', 'es'] as const;
export type Lang = (typeof languages)[number];

export const defaultLang: Lang = 'en';

/** Keys shared by the locale files and the language-independent data. */
export type FeatureKey =
  | 'markdown'
  | 'links'
  | 'graph'
  | 'daily'
  | 'search'
  | 'folders'
  | 'tiling'
  | 'focus'
  | 'export'
  | 'sync'
  | 'personalise';

export type ShotKey = 'home' | 'editor' | 'calendar' | 'timer' | 'tiling' | 'settings';
export type PlatformKey = 'macos' | 'windows' | 'linux';
export type GraphNodeKey = 'research' | 'ideas' | 'reading' | 'daily' | 'projects' | 'weekly';

export type Content = {
  /** Written into <html lang> and the structured data. */
  htmlLang: string;
  /** BCP-47 tag for the sitemap's hreflang alternates. */
  hreflang: string;
  /** How this language names itself in the switcher. */
  languageName: string;
  switchLanguageLabel: string;

  meta: {
    tagline: string;
    description: string;
    shortDescription: string;
  };

  nav: {
    features: string;
    graph: string;
    tour: string;
    faq: string;
    download: string;
    skipToContent: string;
    footerLabel: string;
    sourceCode: string;
    releases: string;
    githubLabel: string;
  };

  hero: {
    windowLabel: string;
    videoLabel: string;
    starsSuffix: string;
    starsFallback: string;
    licensed: string;
    noAccount: string;
    headlineLead: string;
    headlineAccent: string;
    subheading: string;
    ctaPrimary: string;
    ctaSecondary: string;
    platforms: string;
  };

  values: {
    ariaLabel: string;
    items: { label: string; detail: string }[];
  };

  features: {
    heading: string;
    headingMuted: string;
    body: string;
    items: Record<FeatureKey, { title: string; body: string }>;
  };

  graph: {
    eyebrow: string;
    heading: string;
    body: string;
    points: string[];
    svgTitle: string;
    svgDesc: string;
    nodeLabels: Record<GraphNodeKey, string>;
  };

  tour: {
    heading: string;
    body: string;
    shots: Record<ShotKey, { eyebrow: string; title: string; body: string; alt: string }>;
  };

  download: {
    heading: string;
    body: string;
    cta: string;
    platforms: Record<PlatformKey, { platform: string; note: string }>;
    versionLine: (version: string) => string;
    allReleases: string;
    firstRun: {
      summary: string;
      body: string;
      says: string;
      macos: { warning: string; steps: string[]; note: string };
      windows: { warning: string; steps: string[] };
    };
  };

  faq: {
    heading: string;
    items: { q: string; a: string }[];
  };

  footer: {
    support: string;
    /** Takes the year so the sentence can be ordered however the language wants. */
    legal: (year: number, author: string) => string;
    socialLabel: (author: string, network: string) => string;
  };
};
