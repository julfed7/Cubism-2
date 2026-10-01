const Room = require('./Room');

class RoomManager {
  constructor({ maxRooms, maxPlayersPerRoom }) {
    this.maxRooms = maxRooms;
    this.maxPlayersPerRoom = maxPlayersPerRoom;
    this.rooms = new Map();
  }

  createRoom(name, mode = 'co-op', maxPlayers = this.maxPlayersPerRoom) {
    if (this.rooms.size >= this.maxRooms) throw new Error('Room limit reached');
    const requested = Number(maxPlayers);
    const limit = Number.isInteger(requested)
      ? Math.max(1, Math.min(this.maxPlayersPerRoom, requested))
      : this.maxPlayersPerRoom;
    const room = new Room({ name, mode, maxPlayers: limit });
    this.rooms.set(room.id, room);
    return room;
  }

  get(roomId) { return this.rooms.get(roomId); }

  remove(roomId) { this.rooms.delete(roomId); }

  list() {
    return [...this.rooms.values()]
      .filter((room) => room.phase === 'lobby' && room.players.size < room.maxPlayers)
      .map((room) => room.roomInfo());
  }

  update(deltaSeconds, now) {
    for (const [id, room] of this.rooms) {
      room.update(deltaSeconds, now);
      if (room.phase === 'playing') room.sendState();
      if (room.players.size === 0) this.rooms.delete(id);
    }
  }
}

module.exports = RoomManager;
