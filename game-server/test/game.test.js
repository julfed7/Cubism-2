const assert = require('node:assert/strict');
const Room = require('../src/game/Room');
const Vector2 = require('../src/utils/vector2');

function socket() {
  return { readyState: 1, messages: [], send(value) { this.messages.push(JSON.parse(value)); } };
}

function testRoomStartsOnlyAfterEveryPlayerIsReady() {
  const room = new Room({ name: 'Test', maxPlayers: 2 });
  const first = socket();
  const second = socket();
  room.addPlayer({ userId: 'one', name: 'One', socket: first });
  room.addPlayer({ userId: 'two', name: 'Two', socket: second });
  assert.equal(room.start('map1'), false);
  room.setReady('one', true);
  assert.equal(room.start('map1'), false);
  room.setReady('two', true);
  assert.equal(room.start('map1'), true);
  assert.equal(room.phase, 'playing');
  assert.equal(room.mapId, 'map1');
}

function testMovementIsAuthoritativeAndClampedToWorldBounds() {
  const room = new Room({ name: 'Test', maxPlayers: 1 });
  const player = room.addPlayer({ userId: 'one', name: 'One', socket: socket() });
  player.ready = true;
  room.start('map1');
  room.updateInput('one', { x: 100, y: 0 });
  room.update(10, Date.now());
  assert.equal(player.position.x, 1309);
  assert.equal(player.position.y, 150);
}

function testShootingCreatesServerSideBullet() {
  const room = new Room({ name: 'Test', maxPlayers: 1 });
  const player = room.addPlayer({ userId: 'one', name: 'One', socket: socket() });
  player.addItem('pistol');
  player.ready = true;
  room.start('map1');
  const before = player.magazine.pistol;
  const result = room.handleAction('one', { type: 'shoot', direction: { x: 1, y: 0 } });
  assert.equal(result.ok, true);
  assert.equal(player.magazine.pistol, before - 1);
  assert.equal([...room.entities.values()].some((entity) => entity.type === 'bullet'), true);
}

function testPickupRequiresRangeAndAddsItem() {
  const room = new Room({ name: 'Test', maxPlayers: 1 });
  const player = room.addPlayer({ userId: 'one', name: 'One', socket: socket() });
  player.ready = true;
  room.start('map1');
  const pickup = room.addEntity(new (require('../src/game/entities/Pickup'))({ itemId: 'medkit', amount: 2, position: new Vector2(180, 150) }));
  player.position = new Vector2(180, 150);
  assert.equal(room.collectPickup(player, pickup.id), true);
  assert.equal(player.inventory.some((item) => item?.id === 'medkit' && item.amount === 2), true);
}

const tests = [
  ['room starts only after every player is ready', testRoomStartsOnlyAfterEveryPlayerIsReady],
  ['movement is authoritative and clamped to world bounds', testMovementIsAuthoritativeAndClampedToWorldBounds],
  ['shooting creates a server-side bullet and consumes magazine ammo', testShootingCreatesServerSideBullet],
  ['pickup requires range and adds item to inventory', testPickupRequiresRangeAndAddsItem],
];

for (const [name, run] of tests) {
  try {
    run();
    console.log(`PASS ${name}`);
  } catch (error) {
    console.error(`FAIL ${name}`);
    throw error;
  }
}

console.log(`${tests.length} game tests passed`);
