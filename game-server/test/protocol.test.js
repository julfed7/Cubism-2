const assert = require('node:assert/strict');
const GameServer = require('../src/GameServer');
const { encode, read, VERSION } = require('../src/protocol');

function socket() {
  return {
    readyState: 1,
    packets: [],
    send(value) { this.packets.push(JSON.parse(value)); },
    close() {},
  };
}

function testProtocolAndRoomLifecycle() {
  const server = new GameServer({ tickRate: 20 });
  const firstSocket = socket();
  const secondSocket = socket();
  server.onConnect('user-a', firstSocket);
  server.onConnect('user-b', secondSocket);

  server.onMessage('user-a', {
    v: VERSION, type: 'create_room', nickname: 'Alice', roomName: 'Test', maxPlayers: 2,
  });
  const roomId = firstSocket.packets.find((packet) => packet.type === 'room_created').roomId;
  server.onMessage('user-b', { v: VERSION, type: 'join', nickname: 'Bob', roomId });
  server.onMessage('user-a', { v: VERSION, type: 'ready', ready: true });
  server.onMessage('user-b', { v: VERSION, type: 'ready', ready: true });
  server.onMessage('user-a', { v: VERSION, type: 'start_game', mapId: 'map1' });

  const room = server.rooms.get(roomId);
  assert.equal(room.phase, 'playing');
  assert.ok(firstSocket.packets.some((packet) => packet.type === 'state'));

  server.onMessage('user-a', {
    v: VERSION, type: 'input', move: { x: 1, y: 0 }, aimAngle: 0,
  });
  const initialX = room.player('user-a').position.x;
  server.tick();
  assert.ok(room.player('user-a').position.x > initialX);
  server.stop();
}

assert.deepEqual(read(encode({ type: 'ping', nonce: 7 })), { v: VERSION, type: 'ping', nonce: 7 });
testProtocolAndRoomLifecycle();
console.log('protocol integration passed');
