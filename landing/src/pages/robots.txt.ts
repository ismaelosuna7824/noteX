import type { APIRoute } from 'astro';

/*
 * Generated rather than kept in public/, so the sitemap URL follows whatever
 * `site` is set to. The static version survived a hosting change still
 * pointing at the old origin, which is a broken sitemap reference nobody would
 * notice until traffic did.
 */
export const GET: APIRoute = ({ site }) => {
  const sitemap = new URL('sitemap-index.xml', site).href;

  return new Response(
    `User-agent: *\nAllow: /\n\nSitemap: ${sitemap}\n`,
    { headers: { 'Content-Type': 'text/plain; charset=utf-8' } },
  );
};
