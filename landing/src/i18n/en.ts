import type { Content } from './types';

export const en: Content = {
  htmlLang: 'en',
  hreflang: 'en',
  languageName: 'English',
  switchLanguageLabel: 'Ver en español',

  meta: {
    tagline: 'Immerse in your notes',
    description:
      'A beautiful desktop notes app for Windows, macOS and Linux. Markdown editing with live preview, linked notes, a graph view, daily notes, focus timer and optional cloud sync — with your notes exportable as plain Markdown, always.',
    shortDescription:
      'Markdown notes that feel like a place you want to write. Free and open source.',
  },

  nav: {
    features: 'Features',
    graph: 'Graph',
    tour: 'Tour',
    faq: 'FAQ',
    download: 'Download',
    skipToContent: 'Skip to content',
    footerLabel: 'Footer',
    sourceCode: 'Source code',
    releases: 'Releases',
    githubLabel: 'GitHub',
  },

  hero: {
    windowLabel: 'NoteX',
    videoLabel:
      'Screen recording of NoteX: writing a note, switching to split view and browsing the calendar',
    starsSuffix: 'on GitHub',
    starsFallback: 'Open source on GitHub',
    licensed: 'MIT licensed',
    noAccount: 'No account required',
    headlineLead: 'Writing should',
    headlineAccent: 'feel like this.',
    subheading:
      'Markdown notes with live preview, links between your pages, a note for every day and a focus timer — kept as plain files you can take with you.',
    ctaPrimary: 'Download free',
    ctaSecondary: 'See it in action',
    platforms: 'Windows · macOS · Linux',
  },

  values: {
    ariaLabel: 'At a glance',
    items: [
      { label: 'Live preview', detail: 'See it as you type' },
      { label: 'Linked notes', detail: 'Type @ to connect' },
      { label: 'Daily pages', detail: 'Ready when you open' },
      { label: 'Mermaid diagrams', detail: 'Rendered as you write' },
    ],
  },

  features: {
    heading: 'Everything a notes app should have.',
    headingMuted: "Nothing it shouldn't.",
    body: 'Built for people who write every day and want their words to stay theirs — plain Markdown on disk, no lock-in, no subscription.',
    items: {
      markdown: {
        title: 'Markdown, all the way down',
        body: 'The full GitHub flavour: tables, task lists, footnotes, callouts, syntax-highlighted code and emoji shortcodes. Live preview beside you, or split the view and watch both at once. What you type is exactly what gets stored — no proprietary format between you and your words.',
      },
      diagrams: {
        title: 'Diagrams from plain text',
        body: 'Write a mermaid block and watch it become a flowchart, a sequence diagram, a state machine, a gantt chart, a pie or a mindmap. Click any diagram to open it full screen and zoom in. It renders inside the app — no browser, no export step, no account with a diagram service.',
      },
      links: {
        title: 'Notes that link to notes',
        body: 'Type @ and pick a note to drop a link right into your text. Follow it with a click and your thinking starts forming a shape instead of a pile.',
      },
      graph: {
        title: 'The graph of it all',
        body: 'Every link draws an edge. Open the graph to see your whole library laid out, or toggle the panel beside the editor to see just what the note in front of you connects to. Drag notes around, focus one to dim the rest, click through to open it.',
      },
      daily: {
        title: 'A note for every day',
        body: "Today's note is waiting when you open the app, titled and ready. Browse the whole month on a calendar and find the day you are looking for.",
      },
      search: {
        title: 'One search, everything',
        body: 'Search once and reach your notes and your Markdown files together, each result labelled and opened where it lives. No remembering which side you filed it under.',
      },
      folders: {
        title: 'Folders that nest',
        body: 'Group notes into colour-coded projects, nest them as deep as your thinking needs, and filter the sidebar down to just the branch you care about.',
      },
      tiling: {
        title: 'Several notes at once',
        body: 'Tile the window into a grid and work across notes side by side. Every pane keeps its own toolbar, preview toggle and auto-save, so drafting one note out of three others stops meaning constant tab-switching.',
      },
      focus: {
        title: 'Focus time, tracked',
        body: 'Start a timer against a project and see the week add up. Writing stats keep a streak from the days you actually wrote, not the days you happened to open the app.',
      },
      export: {
        title: 'Yours to take',
        body: 'Export the whole library to a folder of .md files, folders and all, or save one note wherever you like. Import a folder back just as easily. Your notes outlive the app.',
      },
      sync: {
        title: 'Sync if you want it',
        body: 'Sign in and your notes follow you across devices. Skip it and everything stays on your machine, in a local database. The choice is yours, and it is reversible.',
      },
      personalise: {
        title: 'Make it yours',
        body: 'Thirteen accent colours, your own wallpaper or a looping video behind the glass, seven fonts, and type sizing that stays out of your way. The accent even adapts itself to your background.',
      },
    },
  },

  graph: {
    eyebrow: 'Graph',
    heading: 'See the shape of what you know',
    body: 'Every link you make draws an edge. Notes you keep returning to grow larger and brighter than the ones you wrote once — so the structure you have been building without noticing becomes something you can actually look at.',
    points: [
      'Type @ anywhere in a note and pick another to link them.',
      'Open the graph to see the whole library at once, or toggle the panel beside the editor to see just what this note touches.',
      'Drag a note to move it, click to focus it and dim everything unrelated, click again to open it.',
    ],
    svgTitle: 'A NoteX link graph',
    svgDesc:
      'Eleven notes drawn as circles joined by curved lines. A central note titled Research is the largest and connects to Ideas, Reading, Daily notes, Projects and Weekly review; those in turn link on to smaller notes, so the most-linked notes are the biggest and brightest.',
    nodeLabels: {
      research: 'Research',
      ideas: 'Ideas',
      reading: 'Reading',
      daily: 'Daily notes',
      projects: 'Projects',
      weekly: 'Weekly review',
    },
  },

  tour: {
    heading: 'A look around',
    body: 'Six screens, six things it does well.',
    shots: {
      home: {
        eyebrow: 'Home',
        title: 'Open to a room, not a form',
        body: "Today's note, your writing streak, what you were last editing and anything still pending — all against a backdrop you chose. Everything one click away, nothing demanding attention.",
        alt: 'NoteX home screen showing the daily note, total notes, a writing streak chart and pending reminders over a full-bleed wallpaper',
      },
      editor: {
        eyebrow: 'Editor',
        title: 'Source on the left, result on the right',
        body: 'Full Markdown: headings, task lists, tables, footnotes, code blocks with syntax highlighting. Split the view to see both, or press Cmd/Ctrl+E to flip between them.',
        alt: 'The NoteX editor in split view, raw Markdown on the left and the rendered document on the right, with a formatting toolbar above',
      },
      calendar: {
        eyebrow: 'Calendar',
        title: 'Find the day, find the note',
        body: 'Every daily note lands on the calendar. Dots mark the days you wrote, so a month of work is legible at a glance and any day is one click away.',
        alt: "Monthly calendar view in NoteX with markers on days that have notes, and the selected day's notes listed beside it",
      },
      timer: {
        eyebrow: 'Focus timer',
        title: 'Time what you are working on',
        body: 'Start a timer against a project, let it run while you write, and watch the week total build. Your focus sessions live in the same app as the work itself.',
        alt: "The NoteX focus timer with a task input, project selector, running clock and this week's tracked total",
      },
      tiling: {
        eyebrow: 'Tiling',
        title: 'Four notes, one screen',
        body: 'Split the window into a grid and edit several notes side by side. Each pane keeps its own toolbar, its own preview toggle and its own auto-save — useful when you are drafting one note out of three others.',
        alt: 'NoteX in tiling mode with four Markdown notes open in a two-by-two grid, each with its own toolbar and cursor',
      },
      settings: {
        eyebrow: 'Personalise',
        title: 'Make it somewhere you want to be',
        body: 'Thirteen accent colours that can adapt themselves to your background, your own image or looping video behind the glass, seven fonts, and type sizing tuned to your eyes.',
        alt: 'NoteX settings showing accent colour swatches, theme backgrounds, sidebar icon colours, background video picker and font family list',
      },
    },
  },

  download: {
    heading: 'Start writing tonight',
    body: 'Free, open source and installed in a minute. No account, no trial, nothing to cancel later.',
    cta: 'Download',
    platforms: {
      macos: { platform: 'macOS', note: 'Apple silicon & Intel' },
      windows: { platform: 'Windows', note: 'Installer, 64-bit' },
      linux: { platform: 'Linux', note: 'Debian & Ubuntu' },
    },
    versionLine: (version) => `Version ${version} · MIT licensed ·`,
    allReleases: 'All releases and changelog',
    firstRun: {
      summary: 'Your Mac or PC warns you the first time you open it — here is why',
      body: 'The releases are not signed with a developer certificate. Both Apple and Microsoft charge a yearly subscription for one, and NoteX is free, so the builds go out unsigned and the operating system says it cannot vouch for them. It is a statement about a receipt, not about the code — which you can read, and build yourself, in full.',
      says: 'It says',
      macos: {
        warning: '"Apple could not verify NoteX.app is free of malware."',
        steps: [
          'Open System Settings → Privacy & Security.',
          'Scroll to the Security section — it will name NoteX as blocked.',
          'Click Open Anyway, then confirm.',
        ],
        note: 'On macOS 15 and later, right-clicking the app and choosing Open no longer works — Apple removed that route. The Privacy & Security panel is the way.',
      },
      windows: {
        warning: '"Windows protected your PC."',
        steps: ['Click More info.', 'Click Run anyway.'],
      },
    },
  },

  faq: {
    heading: 'Questions',
    items: [
      {
        q: 'Is NoteX free?',
        a: 'Yes. NoteX is free and open source under the MIT licence. There is no account required, no subscription and no paid tier. If it earns a place in your day, there is a Buy me a coffee link in the footer — entirely optional, and nothing is held back without it.',
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
        q: 'Why does my Mac say NoteX cannot be verified?',
        a: 'Because the build is not signed with a paid developer certificate, so macOS cannot check a receipt for it — it is not a finding about the code. To open it: System Settings → Privacy & Security → scroll to Security → Open Anyway. Note that on macOS 15 and later, right-clicking the app and choosing Open no longer works; Apple removed that route. Windows shows a comparable "Windows protected your PC" notice, where More info → Run anyway gets past it. The full source is public if you would rather read it or build it yourself.',
      },
      {
        q: 'Which Markdown does it support?',
        a: 'GitHub Flavored Markdown, rendered natively in the app: headings, tables, task lists, footnotes, strikethrough, autolinks, alert callouts (> [!NOTE] and friends), emoji shortcodes and fenced code with syntax highlighting. A ```mermaid block is drawn as a diagram — flowcharts, sequence diagrams, state machines, gantt charts, pies and mindmaps — which you can open full screen and zoom. Nothing is converted or uploaded: the file on disk stays the Markdown you typed.',
      },
      {
        q: 'Which platforms does it run on?',
        a: 'Windows, macOS and Linux. Every release ships all three, built from the same source.',
      },
      {
        q: 'Does it work offline?',
        a: 'Completely. NoteX is a local-first desktop app: everything works with no connection, and sync catches up when you are back online.',
      },
    ],
  },

  footer: {
    support: 'Buy me a coffee',
    legal: (year, author) => `© ${year} ${author} · MIT licensed · Built with Flutter`,
    socialLabel: (author, network) => `${author} on ${network}`,
  },
};
