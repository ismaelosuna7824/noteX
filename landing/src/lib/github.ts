/**
 * Repository stats, fetched once at build time.
 *
 * Deliberately not a client-side fetch: a star count is not worth a request
 * on every visit, and doing it at build keeps the page fully static. The
 * number goes stale between deploys, which is the right trade for a figure
 * nobody checks twice.
 */

const REPO_API = 'https://api.github.com/repos/ismaelosuna7824/noteX';

export type RepoStats = {
  stars: number | null;
};

export async function getRepoStats(): Promise<RepoStats> {
  try {
    const response = await fetch(REPO_API, {
      headers: { Accept: 'application/vnd.github+json' },
      signal: AbortSignal.timeout(5000),
    });

    if (!response.ok) return { stars: null };

    const data = (await response.json()) as { stargazers_count?: number };
    return { stars: typeof data.stargazers_count === 'number' ? data.stargazers_count : null };
  } catch {
    // Offline builds, rate limits and API hiccups must not fail a deploy.
    // A null count simply renders the link without a number.
    return { stars: null };
  }
}

/** 1200 → "1.2k", so a wide number never reflows the nav. */
export function formatCount(value: number): string {
  if (value < 1000) return String(value);
  return `${(value / 1000).toFixed(value < 10_000 ? 1 : 0)}k`.replace('.0', '');
}
