class Vector2 {
  constructor(x = 0, y = 0) {
    this.x = Number.isFinite(Number(x)) ? Number(x) : 0;
    this.y = Number.isFinite(Number(y)) ? Number(y) : 0;
  }

  add(other) { return new Vector2(this.x + other.x, this.y + other.y); }
  subtract(other) { return new Vector2(this.x - other.x, this.y - other.y); }
  scale(value) { return new Vector2(this.x * value, this.y * value); }
  distanceTo(other) { return Math.hypot(this.x - other.x, this.y - other.y); }
  length() { return Math.hypot(this.x, this.y); }

  normalized() {
    const length = this.length();
    return length > 0 ? new Vector2(this.x / length, this.y / length) : new Vector2();
  }

  clamp(maxLength = 1) {
    const length = this.length();
    return length > maxLength ? this.normalized().scale(maxLength) : new Vector2(this.x, this.y);
  }

  rotated(angle) {
    const cosine = Math.cos(angle);
    const sine = Math.sin(angle);
    return new Vector2(this.x * cosine - this.y * sine, this.x * sine + this.y * cosine);
  }

  toJSON() {
    return { x: Number(this.x.toFixed(3)), y: Number(this.y.toFixed(3)) };
  }
}

module.exports = Vector2;
