const { spawn } = require('child_process');
const path = require('path');

const proxy = spawn(process.execPath, [path.join(__dirname, 'godot-mcp-proxy.js')], {
  stdio: ['ignore', 'pipe', 'pipe'],
});

proxy.stdout.on('data', (d) => process.stderr.write('[proxy] ' + d));
proxy.stderr.on('data', (d) => process.stderr.write('[proxy] ' + d));

proxy.stdout.on('data', function onReady(d) {
  if (d.toString().includes('running')) {
    proxy.stdout.off('data', onReady);
    const mcp = spawn(process.execPath, [
      path.join(path.dirname(process.execPath), 'node_modules', 'npm', 'bin', 'npx-cli.js'),
      '-y', 'mcp-remote',
      'http://127.0.0.1:8081',
      '--transport', 'http-only'
    ], { stdio: ['inherit', 'inherit', 'inherit'] });

    mcp.on('exit', () => { proxy.kill(); process.exit(); });
    proxy.on('exit', () => { mcp.kill(); process.exit(); });
  }
});

process.on('SIGINT', () => { proxy.kill(); process.exit(); });
process.on('SIGTERM', () => { proxy.kill(); process.exit(); });
