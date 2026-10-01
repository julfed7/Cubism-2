const MAX_PACKET_BYTES = 64 * 1024;
const VERSION = 1;

function encode(message) {
  if (!message || typeof message !== 'object' || Array.isArray(message)) {
    throw new Error('Message must be an object');
  }
  const packet = { ...message, v: VERSION };
  if (typeof packet.type !== 'string' || packet.type.length === 0 || packet.type.length > 64) {
    throw new Error('Invalid message type');
  }
  return JSON.stringify(packet);
}

function send(socket, message) {
  if (!socket || socket.readyState !== 1) return false;
  socket.send(encode(message));
  return true;
}

function read(raw) {
  const buffer = Buffer.isBuffer(raw) ? raw : Buffer.from(String(raw));
  if (buffer.byteLength > MAX_PACKET_BYTES) throw new Error('Packet is too large');
  const packet = JSON.parse(buffer.toString('utf8'));
  if (!packet || typeof packet !== 'object' || Array.isArray(packet)) throw new Error('Invalid packet');
  if (packet.v !== VERSION) throw new Error(`Unsupported protocol version: ${packet.v}`);
  if (typeof packet.type !== 'string' || packet.type.length === 0 || packet.type.length > 64) {
    throw new Error('Invalid message type');
  }
  return packet;
}

module.exports = { VERSION, MAX_PACKET_BYTES, encode, read, send };
