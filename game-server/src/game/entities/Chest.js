const Entity = require('./Entity');

class Chest extends Entity {
  constructor(position) {
    super('chest', position, 18);
    this.opened = false;
  }

  serialize() { return { ...super.serialize(), opened: this.opened }; }
}

module.exports = Chest;
