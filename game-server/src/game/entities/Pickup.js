const Entity = require('./Entity');

class Pickup extends Entity {
  constructor({ itemId, amount, position }) {
    super('pickup', position, 12);
    this.itemId = itemId;
    this.amount = amount;
  }

  serialize() { return { ...super.serialize(), itemId: this.itemId, amount: this.amount }; }
}

module.exports = Pickup;
