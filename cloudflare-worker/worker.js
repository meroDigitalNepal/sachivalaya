export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    // "sachivalaya.org" (apex) maps to pages/home/; subdomains map to pages/<mp>/
    const mp = url.hostname === 'sachivalaya.org' ? 'home' : url.hostname.split('.')[0];

    if (url.pathname.startsWith('/gunaso/')) {
      // Proxy to the Azure Container App for this MP.
      const azureFqdn = await env.MP_FQDNS.get(mp);
      if (!azureFqdn) {
        return new Response(`gunaso is not configured for ${mp}`, { status: 404 });
      }
      const target = new URL(request.url);
      target.hostname = azureFqdn;
      return fetch(new Request(target.toString(), request));
    }

    // Proxy to GitHub Pages, rewriting the path to the MP's subdirectory.
    // e.g. sasmit.sachivalaya.org/photo.jpg
    //   →  github.io/<repo>/pages/sasmit/photo.jpg
    const ghUrl = new URL(request.url);
    ghUrl.hostname = env.GITHUB_PAGES_HOST;
    ghUrl.pathname = `/${env.GITHUB_PAGES_REPO}/pages/${mp}${url.pathname === '/' ? '/index.html' : url.pathname}`;
    return fetch(ghUrl.toString(), {
      method: request.method,
      headers: request.headers,
      body: ['GET', 'HEAD'].includes(request.method) ? undefined : request.body,
      redirect: 'follow',
    });
  },
};
