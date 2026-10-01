const WebSocket = require('ws');
const GameServer = require('./GameServer');
const { read } = require('./protocol');
const config = require('./config');

const wss = new WebSocket.Server({
  host: config.host,
  port: config.port,
  maxPayload: 64 * 1024,
});
const server = new GameServer();

wss.on('connection', (socket) => {
  const userId = server.generateId();
  server.onConnect(userId, socket);
  socket.on('message', (raw) => {
    try {
      server.onMessage(userId, read(raw));
    } catch (error) {
      server.send(userId, { type: 'error', code: 'BAD_REQUEST', message: error.message });
    }
  });
  socket.on('close', () => server.onDisconnect(userId));
  socket.on('error', () => server.onDisconnect(userId));
});

function shutdown() {
  server.stop();
  wss.close(() => process.exit(0));
}

process.once('SIGINT', shutdown);
process.once('SIGTERM', shutdown);
console.log(`[server] listening on ws://${config.host}:${config.port}`);

module.exports = { wss, server };
