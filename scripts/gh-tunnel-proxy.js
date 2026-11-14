/**
 * Minimal HTTPS CONNECT tunnel for git when github.com:443 is unreachable at
 * the DNS-resolved address but reachable at an alternate GitHub IP.
 *
 * Usage:
 *   node scripts/gh-tunnel-proxy.js [port] [upstreamIp]
 *   git -c http.proxy=http://127.0.0.1:8899 push origin main
 *
 * Only tunnels to github.com:443 (and optionally a target host override), so
 * it is safe to leave running for the duration of a push.
 */
const net = require('net');

const port = Number(process.argv[2] || 8899);
const upstreamIp = process.argv[3] || '140.82.121.4';
const upstreamPort = 443;

const server = net.createServer(client => {
	client.once('data', chunk => {
		const header = chunk.toString('latin1');
		const firstLine = header.split('\r\n')[0] || '';
		if (!/^CONNECT\s+/i.test(firstLine)) {
			client.end('HTTP/1.1 405 Method Not Allowed\r\n\r\n');
			return;
		}

		const upstream = net.connect(upstreamPort, upstreamIp, () => {
			client.write('HTTP/1.1 200 Connection Established\r\n\r\n');
			upstream.pipe(client);
			client.pipe(upstream);
		});

		upstream.on('error', () => {
			client.destroy();
		});
		client.on('error', () => {
			upstream.destroy();
		});
	});
});

server.on('error', error => {
	console.error('proxy error: ' + error.message);
	process.exit(1);
});

server.listen(port, '127.0.0.1', () => {
	console.log(`tunnel ready on 127.0.0.1:${port} -> ${upstreamIp}:${upstreamPort}`);
});