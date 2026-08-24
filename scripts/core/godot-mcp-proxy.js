const http = require('http');
const TARGET = 'http://127.0.0.1:8080';
const PORT = 8081;
const TOKEN = 't9E3IaHn1iH-jsNCLnavKfA_iaYaRVf-xF_Uozn84uc';

const server = http.createServer((req, res) => {
  // Intercept the broken OAuth discovery endpoint — return 404 so mcp-remote skips OAuth
  if (req.url === '/.well-known/oauth-authorization-server' ||
      req.url.startsWith('/.well-known/oauth-authorization-server/')) {
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'not_found' }));
    return;
  }

  // Proxy everything else to the Godot MCP server
  const url = new URL(req.url, TARGET);
  const headers = { ...req.headers, host: url.host };
  if (TOKEN) headers['authorization'] = `Bearer ${TOKEN}`;
  const opts = {
    hostname: url.hostname,
    port: url.port,
    path: url.pathname + url.search,
    method: req.method,
    headers,
  };

  const proxy = http.request(opts, (proxyRes) => {
    res.writeHead(proxyRes.statusCode, proxyRes.headers);
    proxyRes.pipe(res, { end: true });
  });

  proxy.on('error', (err) => {
    if (!res.headersSent) {
      res.writeHead(502, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'bad_gateway', detail: err.message }));
    }
  });

  req.pipe(proxy, { end: true });
});

// WebSocket upgrade support (for SSE streams)
server.on('upgrade', (req, socket, head) => {
  const url = new URL(req.url, TARGET);
  const proxyReq = http.request({
    hostname: url.hostname,
    port: url.port,
    path: url.pathname + url.search,
    method: 'GET',
    headers: req.headers,
  });

  proxyReq.on('upgrade', (proxyRes, proxySocket, proxyHead) => {
    socket.write(
      `HTTP/1.1 101 Switching Protocols\r\n` +
      Object.entries(proxyRes.headers).map(([k, v]) => `${k}: ${v}`).join('\r\n') +
      '\r\n\r\n'
    );
    if (proxyHead.length) socket.write(proxyHead);
    proxySocket.pipe(socket);
    socket.pipe(proxySocket);
  });

  proxyReq.on('error', () => socket.destroy());
  proxyReq.end(head);
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`Godot MCP proxy running on http://127.0.0.1:${PORT} → ${TARGET}`);
});
