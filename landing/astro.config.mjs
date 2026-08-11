// @ts-check
import { defineConfig } from 'astro/config';
import tailwindcss from '@tailwindcss/vite';
import sitemap from '@astrojs/sitemap';

// https://astro.build/config
export default defineConfig({
  // Absolute URLs for canonical links, Open Graph tags and the sitemap. Search
  // engines and social crawlers need the full origin, not a relative path.
  //
  // Firebase Hosting serves at the domain root, so there is no base path.
  // This is the only place the origin is written down: canonical, Open Graph,
  // the JSON-LD, robots.txt and the sitemap all read from it.
  site: 'https://notex.fun',
  trailingSlash: 'ignore',

  // English at `/`, Spanish at `/es`. The default locale is not prefixed so
  // the bare domain serves a page directly: prefixing both would turn the
  // most-linked URL there is into a redirect.
  i18n: {
    defaultLocale: 'en',
    locales: ['en', 'es'],
    routing: { prefixDefaultLocale: false },
  },

  // Passing the locales here is what makes the sitemap emit <xhtml:link
  // rel="alternate"> for each page. Without it the two languages look like
  // unrelated URLs to a crawler, and one of them gets treated as duplicate.
  integrations: [
    sitemap({
      i18n: {
        defaultLocale: 'en',
        locales: { en: 'en', es: 'es' },
      },

      // The sitemap builds its URLs from the built file paths, so it emits
      // `/es/` while the pages declare `/es` as canonical — and a sitemap
      // listing a URL whose canonical points elsewhere is exactly what gets
      // reported as a duplicate. Strip the trailing slash from both the loc
      // and its alternates so every URL this site publishes agrees.
      serialize(item) {
        /** @param {string} url */
        const trim = (url) => url.replace(/(.+)\/$/, '$1');

        item.url = trim(item.url);
        item.links = item.links?.map((link) => ({ ...link, url: trim(link.url) }));

        return item;
      },
    }),
  ],

  vite: {
    plugins: [tailwindcss()],
  },

  image: {
    // The screenshots are 2.6-6.4 MB PNGs straight off a Retina display.
    // Astro re-encodes them at build time; these are the widths actually
    // requested by the layout, so nothing larger is ever generated.
    responsiveStyles: true,
  },
});
