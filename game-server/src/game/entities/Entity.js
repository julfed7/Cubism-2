const createId = require('../../utils/id');
const Vector2 = require('../../utils/vector2');

class Entity {
  constructor(type, position = new Vector2(), radius = 0) {
    this.id = createId(type);
    this.type = type;
    this.position = position;
    this.radius = radius;
    this.removed = false;
  }

  serialize() {
    return { id: this.id, type: this.type, position: this.position, radius: this.radius };
  }
}

module.exports = Entity;
