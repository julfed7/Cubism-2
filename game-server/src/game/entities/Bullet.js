const Entity = require('./Entity');

class Bullet extends Entity {
  constructor({ position, direction, speed, damage, ownerId }) {
    super('bullet', position, 4);
    this.direction = direction.normalized();
    this.speed = speed;
    this.damage = damage;
    this.ownerId = ownerId;
    this.age = 0;
    this.lifetime = 2;
  }

  update(deltaSeconds) {
    this.position = this.position.add(this.direction.scale(this.speed * deltaSeconds));
    this.age += deltaSeconds;
    if (this.age >= this.lifetime) this.removed = true;
  }

  serialize() { return { ...super.serialize(), direction: this.direction, ownerId: this.ownerId }; }
}

module.exports = Bullet;
