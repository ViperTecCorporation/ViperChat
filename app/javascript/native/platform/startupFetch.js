// Only discovery and session validation use this bounded startup request.
// Uploads and media transfers must not inherit this timeout.
export const startupFetch = async (url, options = {}) => {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
};
