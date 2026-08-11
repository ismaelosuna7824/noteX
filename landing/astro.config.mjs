// @ts-check
import { defineConfig } from 'astro/config';
import tailwindcss from '@tailwindcss/vite';
import sitemap from '@astrojs/sitemap';

// https://astro.build/config
export default defineConfig({
  // Absolute URLs for canonical links, Open Graph tags and the sitemap. Search
  // engines and social crawlers need the full origin, not a relative path.
  site: 'https://ismaelosuna7824.github.io',
  base: '/noteX',
  trailingSlash: 'ignore',

  integrations: [
    sitemap({
      // The hero comparison page is a scratch pad, not a destination.
      filter: (page) => !page.includes('/alt'),
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
