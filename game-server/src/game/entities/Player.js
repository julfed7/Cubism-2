const Entity = require('./Entity');
const Vector2 = require('../../utils/vector2');
const game = require('../../config/game');

class Player extends Entity {
  constructor({ userId, name, socket }) {
    super('player', new Vector2(), game.player.radius);
    this.userId = userId;
    this.name = name;
    this.socket = socket;
    this.ready = false;
    this.input = new Vector2();
    this.aimAngle = 0;
    this.hp = game.player.maxHp;
    this.alive = true;
    this.deadAt = 0;
    this.lastShotAt = 0;
    this.inventory = Array.from({ length: game.maxInventorySlots }, () => null);
    this.selectedSlot = -1;
    this.magazine = {};
    this.ammoReserve = {};
    this.coins = 0;
  }

  itemConfig(itemId) { return game.items[itemId] || game.weapons[itemId]; }

  addItem(itemId, amount = 1) {
    const config = this.itemConfig(itemId);
    if (!config || !Number.isInteger(amount) || amount <= 0) return false;
    if (game.weapons[itemId]) {
      if (this.inventory.some((item) => item?.id === itemId)) return false;
      const slot = this.inventory.findIndex((item) => item === null);
      if (slot < 0) return false;
      this.inventory[slot] = { id: itemId, amount: 1 };
      this.magazine[itemId] = config.magazineSize;
      this.ammoReserve[itemId] = config.startingAmmo;
      if (this.selectedSlot < 0) this.selectedSlot = slot;
      return true;
    }

    const maxStack = config.maxStack || amount;
    const freeCapacity = this.inventory.reduce((total, item) => (
      item?.id === itemId ? total + Math.max(0, maxStack - item.amount) : total
    ), 0) + this.inventory.filter((item) => item === null).length * maxStack;
    if (freeCapacity < amount) return false;

    let remaining = amount;
    for (const item of this.inventory) {
      if (!item || item.id !== itemId || remaining <= 0) continue;
      const added = Math.min(remaining, maxStack - item.amount);
      item.amount += added;
      remaining -= added;
    }
    while (remaining > 0) {
      const slot = this.inventory.findIndex((item) => item === null);
      const added = Math.min(remaining, maxStack);
      this.inventory[slot] = { id: itemId, amount: added };
      remaining -= added;
    }
    return true;
  }

  selectWeapon(slotIndex) {
    const item = this.inventory[slotIndex];
    if (!item || !game.weapons[item.id]) return false;
    this.selectedSlot = slotIndex;
    return true;
  }

  selectedWeapon() {
    const item = this.inventory[this.selectedSlot];
    return item && game.weapons[item.id] ? { id: item.id, ...game.weapons[item.id] } : null;
  }

  reload() {
    const weapon = this.selectedWeapon();
    if (!weapon) return false;
    const current = this.magazine[weapon.id] || 0;
    const reserve = this.ammoReserve[weapon.id] || 0;
    const amount = Math.min(weapon.magazineSize - current, reserve);
    if (amount <= 0) return false;
    this.magazine[weapon.id] = current + amount;
    this.ammoReserve[weapon.id] = reserve - amount;
    return true;
  }

  useItem(slotIndex) {
    const item = this.inventory[slotIndex];
    const config = item && game.items[item.id];
    if (!item || !config || !this.alive) return { ok: false, reason: 'Item cannot be used' };
    if (config.type === 'healing') {
      if (this.hp >= game.player.maxHp) return { ok: false, reason: 'Health is full' };
      this.hp = Math.min(game.player.maxHp, this.hp + config.heal);
      item.amount -= 1;
    } else if (config.type === 'ammo') {
      this.ammoReserve[config.ammoFor] = (this.ammoReserve[config.ammoFor] || 0) + item.amount;
      item.amount = 0;
    } else if (config.type === 'currency') {
      this.coins += item.amount;
      item.amount = 0;
    } else {
      return { ok: false, reason: 'Item cannot be used' };
    }
    if (item.amount <= 0) this.inventory[slotIndex] = null;
    return { ok: true };
  }

  takeDamage(amount, now) {
    if (!this.alive) return false;
    this.hp = Math.max(0, this.hp - Math.max(0, Number(amount) || 0));
    if (this.hp <= 0) {
      this.alive = false;
      this.deadAt = now;
    }
    return true;
  }

  respawn(position) {
    this.position = position;
    this.hp = game.player.maxHp;
    this.alive = true;
    this.deadAt = 0;
  }

  serialize() {
    return {
      ...super.serialize(),
      userId: this.userId,
      name: this.name,
      ready: this.ready,
      hp: this.hp,
      alive: this.alive,
      aimAngle: this.aimAngle,
      selectedSlot: this.selectedSlot,
      weaponId: this.selectedWeapon()?.id || '',
      magazine: { ...this.magazine },
      ammoReserve: { ...this.ammoReserve },
      inventory: this.inventory.map((item) => (item ? { ...item } : null)),
      coins: this.coins,
    };
  }
}

module.exports = Player;
