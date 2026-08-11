/**
 * Everything about the product that is the same in every language.
 *
 * All reader-facing copy moved to src/i18n/. What is left here is identity and
 * structure: URLs, the version, asset filenames, icon paths. Those are shared
 * by every locale, and a second copy of an SVG path is a second thing to
 * forget — one of them ends up a year out of date.
 */

import type { FeatureKey, PlatformKey, ShotKey } from '../i18n/types';

export const site = {
  name: 'NoteX',
  // The origin deliberately does NOT live here. It is set once as `site` in
  // astro.config.mjs and read through Astro.site, because a second copy is a
  // second thing to forget: this one still pointed at GitHub Pages after the
  // move to Firebase, quietly telling search engines the wrong canonical URL.
  repo: 'https://github.com/ismaelosuna7824/noteX',
  releases: 'https://github.com/ismaelosuna7824/noteX/releases/latest',
  author: 'ismaelosuna7824',
  version: '1.56.0',
  license: 'MIT',
} as const;

/*
  Deliberately not in `social` below: that array renders as icon-only circles
  for profiles someone might want to follow. A tip jar is an action, and an
  unlabelled cup in a row of logos is a button nobody presses.
*/
export const support = {
  href: 'https://buymeacoffee.com/ismaelosuna',
} as const;

/** Where to find the person who builds this. */
export const social = [
  {
    label: 'LinkedIn',
    href: 'https://www.linkedin.com/in/ismael-osuna/',
    icon: 'M4.98 3.5C4.98 4.88 3.87 6 2.5 6S0 4.88 0 3.5 1.12 1 2.5 1s2.48 1.12 2.48 2.5ZM.24 8h4.52v12H.24V8Zm7.2 0h4.34v1.64h.06c.6-1.14 2.08-2.34 4.28-2.34 4.58 0 5.42 3.01 5.42 6.93V20h-4.52v-5.13c0-1.22-.02-2.8-1.7-2.8-1.7 0-1.96 1.33-1.96 2.71V20H8.84V8h-1.4Z',
  },
  {
    label: 'X',
    href: 'https://x.com/IsmaelosunaCa',
    icon: 'M18.24 2.25h3.31l-7.23 8.26 8.5 11.24h-6.66l-5.21-6.82-5.97 6.82H1.66l7.73-8.83L1.24 2.25h6.83l4.71 6.23 5.46-6.23Zm-1.16 17.52h1.83L7.01 4.13H5.05l12.03 15.64Z',
  },
] as const;

/** Download targets. Order here is the order shown; copy comes from the locale. */
export const downloads: { key: PlatformKey; file: string; icon: string }[] = [
  {
    key: 'macos',
    file: 'NoteX-macos.zip',
    icon: 'M16.365 1.43c0 1.14-.47 2.22-1.24 3.01-.85.9-2.25 1.6-3.4 1.5-.14-1.1.44-2.28 1.2-3.03.85-.86 2.32-1.5 3.44-1.48ZM20.5 17.2c-.6 1.38-.89 2-1.66 3.22-1.07 1.7-2.58 3.81-4.45 3.83-1.66.01-2.09-1.08-4.35-1.07-2.26.01-2.73 1.09-4.4 1.08-1.87-.02-3.3-1.93-4.37-3.62C-1.7 16.9-2 10.3.9 6.86 2.2 5.28 4.1 4.3 5.9 4.3c1.83 0 2.98 1.09 4.5 1.09 1.47 0 2.36-1.09 4.48-1.09 1.6 0 3.3.87 4.5 2.38-3.96 2.17-3.32 7.83.62 9.36-.5 1.4-.75 1.9-1.5 3.16Z',
  },
  {
    key: 'windows',
    file: 'NoteX-windows-setup.exe',
    icon: 'M0 3.45 9.75 2.1v9.45H0V3.45Zm10.95-1.5L24 0v11.55H10.95V1.95ZM0 12.75h9.75v9.45L0 20.85v-8.1Zm10.95 0H24V24l-13.05-1.8v-9.45Z',
  },
  {
    key: 'linux',
    file: 'NoteX-linux.deb',
    icon: 'M12 0a5.5 5.5 0 0 0-5.5 5.5c0 1.9-.3 3.4-1 4.9-.9 2-2.1 3.6-2.1 5.6 0 1 .4 1.7 1.1 2.1.5.3.8.8.9 1.4.2 1.3 1.3 2.3 2.6 2.3.8 0 1.5-.4 2-1 .6.2 1.3.3 2 .3s1.4-.1 2-.3c.5.6 1.2 1 2 1 1.3 0 2.4-1 2.6-2.3.1-.6.4-1.1.9-1.4.7-.4 1.1-1.1 1.1-2.1 0-2-1.2-3.6-2.1-5.6-.7-1.5-1-3-1-4.9A5.5 5.5 0 0 0 12 0Zm-2.2 5.1c.5 0 .9.6.9 1.3s-.4 1.3-.9 1.3-.9-.6-.9-1.3.4-1.3.9-1.3Zm4.4 0c.5 0 .9.6.9 1.3s-.4 1.3-.9 1.3-.9-.6-.9-1.3.4-1.3.9-1.3ZM12 9.2c1.1 0 2.1.5 2.1 1s-1 1.4-2.1 1.4-2.1-.9-2.1-1.4 1-1 2.1-1Z',
  },
];

/**
 * Feature order and icons. Heroicons-style path data, drawn inline to avoid an
 * icon dependency. Titles and bodies live in the locale files, keyed to these.
 */
export const featureOrder: { key: FeatureKey; icon: string }[] = [
  {
    key: 'markdown',
    icon: 'M17.25 6.75 22.5 12l-5.25 5.25m-10.5 0L1.5 12l5.25-5.25m7.5-3-4.5 16.5',
  },
  {
    key: 'links',
    icon: 'M13.19 8.688a4.5 4.5 0 0 1 1.242 7.244l-4.5 4.5a4.5 4.5 0 0 1-6.364-6.364l1.757-1.757m13.35-.622 1.757-1.757a4.5 4.5 0 0 0-6.364-6.364l-4.5 4.5a4.5 4.5 0 0 0 1.242 7.244',
  },
  {
    key: 'graph',
    icon: 'M12 4.5a2.25 2.25 0 1 0 0 4.5 2.25 2.25 0 0 0 0-4.5Zm-6.75 10.5a2.25 2.25 0 1 0 0 4.5 2.25 2.25 0 0 0 0-4.5Zm13.5 0a2.25 2.25 0 1 0 0 4.5 2.25 2.25 0 0 0 0-4.5ZM10.4 8.85l-3.55 5.3m6.75-5.3 3.55 5.3m-9.65 2.6h9.1',
  },
  {
    key: 'daily',
    icon: 'M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 0 1 2.25-2.25h13.5A2.25 2.25 0 0 1 21 7.5v11.25m-18 0A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75m-18 0v-7.5A2.25 2.25 0 0 1 5.25 9h13.5A2.25 2.25 0 0 1 21 11.25v7.5',
  },
  {
    key: 'search',
    icon: 'm21 21-5.197-5.197m0 0A7.5 7.5 0 1 0 5.196 5.196a7.5 7.5 0 0 0 10.607 10.607Z',
  },
  {
    key: 'folders',
    icon: 'M2.25 12.75V12A2.25 2.25 0 0 1 4.5 9.75h15A2.25 2.25 0 0 1 21.75 12v.75m-8.69-6.44-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 5.25v13.5A2.25 2.25 0 0 0 4.5 21h15a2.25 2.25 0 0 0 2.25-2.25V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44Z',
  },
  {
    key: 'tiling',
    icon: 'M3.75 6A2.25 2.25 0 0 1 6 3.75h2.25A2.25 2.25 0 0 1 10.5 6v2.25a2.25 2.25 0 0 1-2.25 2.25H6a2.25 2.25 0 0 1-2.25-2.25V6ZM3.75 15.75A2.25 2.25 0 0 1 6 13.5h2.25a2.25 2.25 0 0 1 2.25 2.25V18a2.25 2.25 0 0 1-2.25 2.25H6A2.25 2.25 0 0 1 3.75 18v-2.25ZM13.5 6a2.25 2.25 0 0 1 2.25-2.25H18A2.25 2.25 0 0 1 20.25 6v2.25A2.25 2.25 0 0 1 18 10.5h-2.25a2.25 2.25 0 0 1-2.25-2.25V6ZM13.5 15.75a2.25 2.25 0 0 1 2.25-2.25H18a2.25 2.25 0 0 1 2.25 2.25V18A2.25 2.25 0 0 1 18 20.25h-2.25A2.25 2.25 0 0 1 13.5 18v-2.25Z',
  },
  { key: 'focus', icon: 'M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z' },
  {
    key: 'export',
    icon: 'M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3',
  },
  {
    key: 'sync',
    icon: 'M2.25 15a4.5 4.5 0 0 0 4.5 4.5H18a3.75 3.75 0 0 0 1.332-7.257 3 3 0 0 0-3.758-3.848 5.25 5.25 0 0 0-10.233 2.33A4.502 4.502 0 0 0 2.25 15Z',
  },
  {
    key: 'personalise',
    icon: 'M4.098 19.902a3.75 3.75 0 0 0 5.304 0l6.401-6.402M6.75 21A3.75 3.75 0 0 1 3 17.25V4.125C3 3.504 3.504 3 4.125 3h5.25c.621 0 1.125.504 1.125 1.125v4.5m0 0 3.712 3.712M10.5 8.625a1.875 1.875 0 1 1-3.75 0 1.875 1.875 0 0 1 3.75 0Z',
  },
];

/** Tour order. The images are imported in the component; the copy is keyed. */
export const shotOrder: ShotKey[] = ['home', 'editor', 'calendar', 'timer', 'tiling', 'settings'];

/*
  Which platforms get first-run instructions. The wording each OS shows is NOT
  here: an operating system speaks the reader's language, so the quote is part
  of the translation, not of the product data.
*/
export const firstRunPlatforms = [{ key: 'macos' }, { key: 'windows' }] as const;
