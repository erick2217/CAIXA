const SUPABASE_READ_CACHE_PREFIX = "pax-supabase-read-";

export function isSupabaseTableRead({ url, request }) {
  return (
    request.method === "GET" &&
    url.pathname.startsWith("/rest/v1/") &&
    !url.pathname.startsWith("/rest/v1/rpc/")
  );
}

export async function clearSupabaseReadCaches(cacheStorage = globalThis.caches) {
  if (!cacheStorage) return;

  const names = await cacheStorage.keys();
  await Promise.all(
    names
      .filter((name) => name.startsWith(SUPABASE_READ_CACHE_PREFIX))
      .map((name) => cacheStorage.delete(name)),
  );
}
