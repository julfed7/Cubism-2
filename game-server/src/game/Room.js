const Vector2 = require('../utils/vector2');
const createId = require('../utils/id');
const game = require('../config/game');
const { send } = require('../protocol');
const Player = require('./entities/Player');
const Zombie = require('./entities/Zombie');
const Bullet = require('./entities/Bullet');
const Pickup = require('./entities/Pickup');
const Chest = require('./entities/Chest');

const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
const finite = (value, fallback = 0) => Number.isFinite(Number(value)) ? Number(value) : fallback;

class Room {
  constructor({ name = 'Quick Match', mode = 'co-op', maxPlayers = 20 }) {
    this.id = createId('room');
    this.name = String(name).trim().slice(0, 32) || 'Quick Match';
    this.mode = String(mode).trim().slice(0, 24) || 'co-op';
    this.maxPlayers = maxPlayers;
    this.players = new Map();
    this.entities = new Map();
    this.phase = 'lobby';
    this.mapId = 'map1';
    this.tick = 0;
    this.spawnIndex = 0;
    this.ownerId = null;
    this.loadMap(this.mapId);
  }

  roomInfo() {
    return {
      id: this.id,
      name: this.name,
      mode: this.mode,
      players: this.players.size,
      maxPlayers: this.maxPlayers,
      phase: this.phase,
      mapId: this.mapId,
    };
  }

  addEntity(entity) {
    this.entities.set(entity.id, entity);
    return entity;
  }

  loadMap(mapId) {
    const map = game.maps[mapId] || game.maps.map1;
    this.mapId = game.maps[mapId] ? mapId : 'map1';
    this.spawnIndex = 0;
    this.entities.clear();
    for (const [x, y] of map.zombies) this.addEntity(new Zombie(new Vector2(x, y)));
    for (const [x, y] of map.chests) this.addEntity(new Chest(new Vector2(x, y)));
    for (const player of this.players.values()) {
      player.position = this.spawnPosition();
      this.addEntity(player);
    }
  }

  map() { return game.maps[this.mapId] || game.maps.map1; }

  spawnPosition() {
    const points = this.map().spawns;
    const point = points[this.spawnIndex % points.length];
    this.spawnIndex += 1;
    return new Vector2(point[0], point[1]);
  }

  addPlayer({ userId, name, socket }) {
    if (this.players.size >= this.maxPlayers) throw new Error('Room is full');
    if (this.phase !== 'lobby') throw new Error('Match already started');
    const player = new Player({ userId, name, socket });
    player.position = this.spawnPosition();
    player.addItem('pistol');
    if (!this.ownerId) this.ownerId = userId;
    this.players.set(userId, player);
    this.addEntity(player);
    return player;
  }

  removePlayer(userId) {
    const player = this.players.get(userId);
    if (!player) return;
    this.players.delete(userId);
    this.entities.delete(player.id);
    if (this.ownerId === userId) this.ownerId = this.players.keys().next().value || null;
  }

  player(userId) { return this.players.get(userId); }

  setReady(userId, ready) {
    const player = this.player(userId);
    if (!player || this.phase !== 'lobby') return false;
    player.ready = Boolean(ready);
    return true;
  }

  start(requestedMapId, requesterId) {
    if (this.phase !== 'lobby' || this.players.size === 0) return false;
    if (requesterId !== undefined && requesterId !== null && requesterId !== this.ownerId) return false;
    if (![...this.players.values()].every((player) => player.ready)) return false;
    this.loadMap(game.maps[requestedMapId] ? requestedMapId : 'map1');
    this.phase = 'playing';
    return true;
  }

  updateInput(userId, payload = {}, aimAngle = null) {
    const player = this.player(userId);
    if (!player || this.phase !== 'playing') return false;
    player.input = new Vector2(clamp(finite(payload.x), -1, 1), clamp(finite(payload.y), -1, 1)).clamp(1);
    const angle = aimAngle ?? payload.aimAngle;
    if (Number.isFinite(Number(angle))) player.aimAngle = finite(angle);
    return true;
  }

  handleAction(userId, action) {
    const player = this.player(userId);
    if (!player || this.phase !== 'playing') throw new Error('Match is not running');
    switch (String(action.type || '')) {
      case 'shoot': return this.shoot(player, action);
      case 'reload': return { ok: player.reload(), type: 'reload' };
      case 'select_weapon': return { ok: player.selectWeapon(Math.trunc(finite(action.slotIndex, -1))), type: 'select_weapon' };
      case 'use_item': return { ...player.useItem(Math.trunc(finite(action.slotIndex, -1))), type: 'use_item' };
      case 'pickup': return { ok: this.collectPickup(player, String(action.entityId || '')), type: 'pickup' };
      case 'open_chest': return { ok: this.openChest(player, String(action.entityId || '')), type: 'open_chest' };
      default: throw new Error('Unknown action');
    }
  }

  shoot(player, action) {
    const weapon = player.selectedWeapon();
    if (!weapon || !player.alive) return { ok: false, reason: 'No weapon equipped', type: 'shoot' };
    const raw = action.direction || {};
    const direction = new Vector2(finite(raw.x), finite(raw.y)).normalized();
    if (direction.length() === 0) return { ok: false, reason: 'Invalid direction', type: 'shoot' };
    const now = Date.now();
    if (now - player.lastShotAt < weapon.fireRateMs) return { ok: false, reason: 'Weapon cooldown', type: 'shoot' };
    if ((player.magazine[weapon.id] || 0) <= 0) {
      const reloaded = player.reload();
      return { ok: false, reason: reloaded ? 'Reloaded' : 'Empty magazine', type: 'shoot' };
    }
    player.lastShotAt = now;
    player.magazine[weapon.id] -= 1;
    const pellets = weapon.pellets || 1;
    const spread = (weapon.spreadDegrees || 0) * Math.PI / 180;
    for (let index = 0; index < pellets; index += 1) {
      const angle = Math.atan2(direction.y, direction.x) + (pellets > 1 ? (Math.random() * 2 - 1) * spread : 0);
      const pelletDirection = new Vector2(Math.cos(angle), Math.sin(angle));
      this.addEntity(new Bullet({
        position: player.position.add(pelletDirection.scale(player.radius + 5)),
        direction: pelletDirection,
        speed: weapon.bulletSpeed,
        damage: weapon.damage,
        ownerId: player.userId,
      }));
    }
    return { ok: true, type: 'shoot', weaponId: weapon.id, pellets, magazine: player.magazine[weapon.id] };
  }

  collectPickup(player, entityId) {
    const pickup = this.entities.get(entityId);
    if (!(pickup instanceof Pickup) || !player.alive || player.position.distanceTo(pickup.position) > game.interactionRange) return false;
    if (!player.addItem(pickup.itemId, pickup.amount)) return false;
    pickup.removed = true;
    return true;
  }

  openChest(player, entityId) {
    const chest = this.entities.get(entityId);
    if (!(chest instanceof Chest) || chest.opened || !player.alive || player.position.distanceTo(chest.position) > game.interactionRange) return false;
    chest.opened = true;
    const count = 2 + Math.floor(Math.random() * 3);
    const loot = [this.pickChestLoot(['pistol', 'smg', 'shotgun', 'rifle']), this.pickChestLoot(['medkit', 'ammo_pistol', 'ammo_smg', 'ammo_shotgun'])];
    while (loot.length < count) loot.push(this.pickChestLoot());
    for (const itemId of loot) {
      const amount = game.weapons[itemId] ? 1 : 1 + Math.floor(Math.random() * 3);
      const angle = Math.random() * Math.PI * 2;
      this.addEntity(new Pickup({ itemId, amount, position: chest.position.add(new Vector2(Math.cos(angle), Math.sin(angle)).scale(28 + Math.random() * 30)) }));
    }
    return true;
  }

  pickChestLoot(allowedIds = null) {
    const table = game.chestLootTable.filter((item) => !allowedIds || allowedIds.includes(item.id));
    const total = table.reduce((sum, item) => sum + item.weight, 0);
    let roll = Math.floor(Math.random() * total);
    for (const item of table) {
      roll -= item.weight;
      if (roll < 0) return item.id;
    }
    return table[0]?.id || 'medkit';
  }

  update(deltaSeconds, now = Date.now()) {
    if (this.phase !== 'playing') return;
    this.tick += 1;
    for (const player of this.players.values()) this.updatePlayer(player, deltaSeconds, now);
    this.updateZombies(deltaSeconds, now);
    this.updateBullets(deltaSeconds, now);
    for (const [id, entity] of this.entities) if (entity.removed) this.entities.delete(id);
  }

  updatePlayer(player, deltaSeconds, now) {
    if (!player.alive) {
      if (now - player.deadAt >= game.player.respawnMs) player.respawn(this.spawnPosition());
      return;
    }
    player.position = player.position.add(player.input.scale(game.player.speed * deltaSeconds));
    player.position.x = clamp(player.position.x, player.radius, game.world.width - player.radius);
    player.position.y = clamp(player.position.y, player.radius, game.world.height - player.radius);
  }

  updateZombies(deltaSeconds, now) {
    for (const zombie of this.entities.values()) {
      if (!(zombie instanceof Zombie)) continue;
      if (!zombie.alive) { zombie.removed = true; continue; }
      const target = [...this.players.values()].filter((player) => player.alive).sort((a, b) => zombie.position.distanceTo(a.position) - zombie.position.distanceTo(b.position))[0];
      if (!target) continue;
      const distance = zombie.position.distanceTo(target.position);
      if (distance > game.zombie.attackRange) {
        zombie.position = zombie.position.add(target.position.subtract(zombie.position).normalized().scale(game.zombie.speed * deltaSeconds));
        zombie.position.x = clamp(zombie.position.x, zombie.radius, game.world.width - zombie.radius);
        zombie.position.y = clamp(zombie.position.y, zombie.radius, game.world.height - zombie.radius);
      } else if (now - zombie.lastAttackAt >= game.zombie.attackCooldownMs) {
        zombie.lastAttackAt = now;
        target.takeDamage(game.zombie.attackDamage, now);
      }
    }
  }

  updateBullets(deltaSeconds, now) {
    for (const bullet of this.entities.values()) {
      if (!(bullet instanceof Bullet)) continue;
      bullet.update(deltaSeconds);
      if (bullet.position.x < 0 || bullet.position.x > game.world.width || bullet.position.y < 0 || bullet.position.y > game.world.height) bullet.removed = true;
      if (bullet.removed) continue;
      for (const zombie of this.entities.values()) {
        if (!(zombie instanceof Zombie) || !zombie.alive || bullet.position.distanceTo(zombie.position) > bullet.radius + zombie.radius) continue;
        zombie.takeDamage(bullet.damage);
        bullet.removed = true;
        break;
      }
      if (bullet.removed) continue;
      for (const player of this.players.values()) {
        if (!player.alive || player.userId === bullet.ownerId || bullet.position.distanceTo(player.position) > bullet.radius + player.radius) continue;
        player.takeDamage(bullet.damage, now);
        bullet.removed = true;
        break;
      }
    }
  }

  broadcast(message) {
    for (const player of this.players.values()) send(player.socket, message);
  }

  playerList() {
    return [...this.players.values()].map((player) => ({ id: player.userId, name: player.name, ready: player.ready }));
  }

  broadcastRoomState() {
    this.broadcast({ type: 'room_state', room: this.roomInfo(), ownerId: this.ownerId, players: this.playerList() });
  }

  snapshot() {
    return {
      roomId: this.id,
      name: this.name,
      mode: this.mode,
      phase: this.phase,
      mapId: this.mapId,
      tick: this.tick,
      world: game.world,
      ownerId: this.ownerId,
      players: this.playerList(),
      entities: [...this.entities.values()].filter((entity) => !entity.removed).map((entity) => entity.serialize()),
    };
  }

  sendState() {
    this.broadcast({ type: 'state', ...this.snapshot() });
  }
}

module.exports = Room;
