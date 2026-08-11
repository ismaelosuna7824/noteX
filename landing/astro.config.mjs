// @ts-check
import { defineConfig } from 'astro/config';
import tailwindcss from '@tailwindcss/vite';
import sitemap from '@astrojs/sitemap';

// https://astro.build/config
export default defineConfig({
  // Absolute URLs for canonical links, Open Graph tags and the sitemap. Search
  // engines and social crawlers need the full origin, not a relative path.
  //
  // Firebase Hosting serves at the domain root, so there is no base path. Swap
  // `site` for the custom domain once one is registered — it is the only place
  // the origin is written down.
  site: 'https://notex-b95a8.web.app',
  trailingSlash: 'ignore',

  integrations: [sitemap()],

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
