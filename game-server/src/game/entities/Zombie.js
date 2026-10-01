const Entity = require('./Entity');
const game = require('../../config/game');

class Zombie extends Entity {
  constructor(position) {
    super('zombie', position, game.zombie.radius);
    this.hp = game.zombie.hp;
    this.alive = true;
    this.lastAttackAt = 0;
  }

  takeDamage(amount) {
    if (!this.alive) return false;
    this.hp = Math.max(0, this.hp - Math.max(0, Number(amount) || 0));
    if (this.hp <= 0) this.alive = false;
    return true;
  }

  serialize() { return { ...super.serialize(), hp: this.hp, alive: this.alive }; }
}

module.exports = Zombie;
