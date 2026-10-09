/**
 * ZV Suite · Notion proxy v3 (Cloudflare Worker "zv-notion-proxy")
 * Keeps the Notion token on the server. The app sends { method, path, body }.
 *
 * Variables (Worker → Settings → Variables and Secrets):
 *   NOTION_TOKEN     secret  — token of the Notion integration connected to the HQ page
 *   APP_KEY          secret  — long random password; type the same one in the app
 *
 * v3: CORS reflects the request Origin (works from localhost and GitHub Pages); read-only routes used by
 * the app's schema preflight and diagnostics, no body on GET, JSON errors.
 */
const ROUTES = [
  ['GET', /^\/v1\/users\/me$/],                        // diagnostics: token check
  ['GET', /^\/v1\/data_sources\/[\w-]+$/],             // schema preflight
  ['POST', /^\/v1\/data_sources\/[\w-]+\/query$/],     // pull / entity lookup
  ['POST', /^\/v1\/search$/],                          // find data sources by name
  ['POST', /^\/v1\/pages$/],                           // create
  ['PATCH', /^\/v1\/pages\/[\w-]+$/]                   // update / move to trash
];

export default {
  async fetch(req, env) {
    // CORS: reflect the caller's origin (localhost in development, GitHub Pages in production).
    // Access is still protected by APP_KEY below, so an open origin does not expose Notion.
    const origin = req.headers.get('Origin') || '*';
    const cors = {
      'Access-Control-Allow-Origin': origin,
      'Access-Control-Allow-Headers': 'content-type, authorization',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS, PATCH',
      'Access-Control-Max-Age': '86400',
      'Vary': 'Origin'
    };
    const json = (status, obj) => new Response(JSON.stringify(obj), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    if (req.method !== 'POST') return json(405, { object: 'proxy_error', code: 'method_not_allowed', message: 'Use POST' });
    if (!env.APP_KEY || req.headers.get('Authorization') !== 'Bearer ' + env.APP_KEY) return json(401, { object: 'proxy_error', code: 'proxy_unauthorized', message: 'Invalid app key' });
    if (!env.NOTION_TOKEN) return json(500, { object: 'proxy_error', code: 'proxy_misconfigured', message: 'NOTION_TOKEN is not set' });

    let payload;
    try { payload = await req.json(); } catch (e) { return json(400, { object: 'proxy_error', code: 'bad_json', message: 'Body must be JSON { method, path, body }' }); }
    const { method, path, body } = payload || {};
    if (!ROUTES.some(([m, re]) => m === method && re.test(path || ''))) return json(403, { object: 'proxy_error', code: 'proxy_forbidden', message: `Route not allowed: ${method} ${path}` });

    try {
      const r = await fetch('https://api.notion.com' + path, {
        method,
        headers: { Authorization: 'Bearer ' + env.NOTION_TOKEN, 'Notion-Version': '2025-09-03', 'Content-Type': 'application/json' },
        body: method === 'GET' ? undefined : JSON.stringify(body || {})
      });
      const headers = { ...cors, 'Content-Type': 'application/json' };
      const ra = r.headers.get('Retry-After'); if (ra) headers['Retry-After'] = ra;
      return new Response(await r.text(), { status: r.status, headers });   // Notion's own error JSON passes through untouched
    } catch (e) {
      return json(502, { object: 'proxy_error', code: 'upstream_unreachable', message: String(e && e.message || e) });
    }
  }
};
