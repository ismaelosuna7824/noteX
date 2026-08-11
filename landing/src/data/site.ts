/**
 * Single source of truth for everything the page says about the product.
 *
 * Keeping copy here rather than inline in markup means a feature can be added
 * or a version bumped without touching layout, and the JSON-LD stays in step
 * with the visible page — search engines penalise the two disagreeing.
 */

export const site = {
  name: 'NoteX',
  tagline: 'Immerse in your notes',
  description:
    'A beautiful desktop notes app for Windows, macOS and Linux. Markdown editing with live preview, linked notes, daily notes, focus timer and optional cloud sync — with your notes exportable as plain Markdown, always.',
  shortDescription:
    'Markdown notes that feel like a place you want to write. Free and open source.',
  // The origin deliberately does NOT live here. It is set once as `site` in
  // astro.config.mjs and read through Astro.site, because a second copy is a
  // second thing to forget: this one still pointed at GitHub Pages after the
  // move to Firebase, quietly telling search engines the wrong canonical URL.
  repo: 'https://github.com/ismaelosuna7824/noteX',
  releases: 'https://github.com/ismaelosuna7824/noteX/releases/latest',
  author: 'ismaelosuna7824',
  version: '1.55.0',
  license: 'MIT',
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

export type Download = {
  platform: string;
  file: string;
  note: string;
  icon: 'apple' | 'windows' | 'linux';
};

export const downloads: Download[] = [
  {
    platform: 'macOS',
    file: 'NoteX-macos.zip',
    note: 'Apple silicon & Intel',
    icon: 'apple',
  },
  {
    platform: 'Windows',
    file: 'NoteX-windows-setup.exe',
    note: 'Installer, 64-bit',
    icon: 'windows',
  },
  {
    platform: 'Linux',
    file: 'NoteX-linux.deb',
    note: 'Debian & Ubuntu',
    icon: 'linux',
  },
];

export type Feature = {
  title: string;
  body: string;
  /** Heroicons-style path data, drawn inline to avoid an icon dependency. */
  icon: string;
};

export const features: Feature[] = [
  {
    title: 'Markdown, all the way down',
    body: 'Write in plain Markdown with a live preview beside you, or split the view and watch both at once. What you type is exactly what gets stored — no proprietary format standing between you and your words.',
    icon: 'M17.25 6.75 22.5 12l-5.25 5.25m-10.5 0L1.5 12l5.25-5.25m7.5-3-4.5 16.5',
  },
  {
    title: 'Notes that link to notes',
    body: 'Type @ and pick a note to drop a link right into your text. Follow it with a click and your thinking starts forming a shape instead of a pile.',
    icon: 'M13.19 8.688a4.5 4.5 0 0 1 1.242 7.244l-4.5 4.5a4.5 4.5 0 0 1-6.364-6.364l1.757-1.757m13.35-.622 1.757-1.757a4.5 4.5 0 0 0-6.364-6.364l-4.5 4.5a4.5 4.5 0 0 0 1.242 7.244',
  },
  {
    title: 'A note for every day',
    body: 'Today\'s note is waiting when you open the app, titled and ready. Browse the whole month on a calendar and find the day you are looking for.',
    icon: 'M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 0 1 2.25-2.25h13.5A2.25 2.25 0 0 1 21 7.5v11.25m-18 0A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75m-18 0v-7.5A2.25 2.25 0 0 1 5.25 9h13.5A2.25 2.25 0 0 1 21 11.25v7.5',
  },
  {
    title: 'One search, everything',
    body: 'Search once and reach your notes and your Markdown files together, each result labelled and opened where it lives. No remembering which side you filed it under.',
    icon: 'm21 21-5.197-5.197m0 0A7.5 7.5 0 1 0 5.196 5.196a7.5 7.5 0 0 0 10.607 10.607Z',
  },
  {
    title: 'Folders that nest',
    body: 'Group notes into colour-coded projects, nest them as deep as your thinking needs, and filter the sidebar down to just the branch you care about.',
    icon: 'M2.25 12.75V12A2.25 2.25 0 0 1 4.5 9.75h15A2.25 2.25 0 0 1 21.75 12v.75m-8.69-6.44-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 5.25v13.5A2.25 2.25 0 0 0 4.5 21h15a2.25 2.25 0 0 0 2.25-2.25V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44Z',
  },
  {
    title: 'Several notes at once',
    body: 'Tile the window into a grid and work across notes side by side. Every pane keeps its own toolbar, preview toggle and auto-save, so drafting one note out of three others stops meaning constant tab-switching.',
    icon: 'M3.75 6A2.25 2.25 0 0 1 6 3.75h2.25A2.25 2.25 0 0 1 10.5 6v2.25a2.25 2.25 0 0 1-2.25 2.25H6a2.25 2.25 0 0 1-2.25-2.25V6ZM3.75 15.75A2.25 2.25 0 0 1 6 13.5h2.25a2.25 2.25 0 0 1 2.25 2.25V18a2.25 2.25 0 0 1-2.25 2.25H6A2.25 2.25 0 0 1 3.75 18v-2.25ZM13.5 6a2.25 2.25 0 0 1 2.25-2.25H18A2.25 2.25 0 0 1 20.25 6v2.25A2.25 2.25 0 0 1 18 10.5h-2.25a2.25 2.25 0 0 1-2.25-2.25V6ZM13.5 15.75a2.25 2.25 0 0 1 2.25-2.25H18a2.25 2.25 0 0 1 2.25 2.25V18A2.25 2.25 0 0 1 18 20.25h-2.25A2.25 2.25 0 0 1 13.5 18v-2.25Z',
  },
  {
    title: 'Focus time, tracked',
    body: 'Start a timer against a project and see the week add up. Writing stats keep a streak from the days you actually wrote, not the days you happened to open the app.',
    icon: 'M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z',
  },
  {
    title: 'Yours to take',
    body: 'Export the whole library to a folder of .md files, folders and all, or save one note wherever you like. Import a folder back just as easily. Your notes outlive the app.',
    icon: 'M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3',
  },
  {
    title: 'Sync if you want it',
    body: 'Sign in and your notes follow you across devices. Skip it and everything stays on your machine, in a local database. The choice is yours, and it is reversible.',
    icon: 'M2.25 15a4.5 4.5 0 0 0 4.5 4.5H18a3.75 3.75 0 0 0 1.332-7.257 3 3 0 0 0-3.758-3.848 5.25 5.25 0 0 0-10.233 2.33A4.502 4.502 0 0 0 2.25 15Z',
  },
  {
    title: 'Make it yours',
    body: 'Thirteen accent colours, your own wallpaper or a looping video behind the glass, seven fonts, and type sizing that stays out of your way. The accent even adapts itself to your background.',
    icon: 'M4.098 19.902a3.75 3.75 0 0 0 5.304 0l6.401-6.402M6.75 21A3.75 3.75 0 0 1 3 17.25V4.125C3 3.504 3.504 3 4.125 3h5.25c.621 0 1.125.504 1.125 1.125v4.5m0 0 3.712 3.712M10.5 8.625a1.875 1.875 0 1 1-3.75 0 1.875 1.875 0 0 1 3.75 0Z',
  },
];

/** Answers the questions people actually ask before downloading. */
export const faqs = [
  {
    q: 'Is NoteX free?',
    a: 'Yes. NoteX is free and open source under the MIT licence. There is no account required, no subscription and no paid tier.',
  },
  {
    q: 'Where are my notes stored?',
    a: 'In a local SQLite database on your own machine. If you sign in, notes also sync to your Supabase project so they follow you across devices — but signing in is entirely optional.',
  },
  {
    q: 'Can I get my notes out?',
    a: 'Any time. Export the whole library to a folder of Markdown files, keeping your folder structure, or save a single note wherever you like. Notes are stored as Markdown already, so nothing is converted on the way out.',
  },
  {
    q: 'Which platforms does it run on?',
    a: 'Windows, macOS and Linux. Every release ships all three, built from the same source.',
  },
  {
    q: 'Does it work offline?',
    a: 'Completely. NoteX is a local-first desktop app: everything works with no connection, and sync catches up when you are back online.',
  },
];
