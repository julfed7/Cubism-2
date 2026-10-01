const RoomManager = require('./game/RoomManager');
const { send } = require('./protocol');
const { generateId } = require('./utils/id');
const config = require('./config');

const text = (value, fallback, maxLength) => {
  const result = String(value ?? '').trim().slice(0, maxLength);
  return result || fallback;
};

class GameServer {
  constructor({ tickRate = config.tickRate } = {}) {
    this.tickRate = tickRate;
    this.clients = new Map();
    this.sessions = new Map();
    this.rooms = new RoomManager({
      maxRooms: config.maxRooms,
      maxPlayersPerRoom: config.maxPlayersPerRoom,
    });
    this.tickInterval = setInterval(() => this.tick(), 1000 / this.tickRate);
  }

  generateId() { return generateId('user'); }

  onConnect(userId, socket) {
    this.clients.set(userId, socket);
    this.sessions.set(userId, { userId, roomId: null, nickname: 'Player', packets: [] });
    this.send(userId, { type: 'welcome', userId, tickRate: this.tickRate });
  }

  onMessage(userId, packet) {
    const session = this.sessions.get(userId);
    if (!session) throw new Error('Unknown connection');
    this._checkRateLimit(session);
    switch (packet.type) {
      case 'create_room': return this._createRoom(session, packet);
      case 'list_rooms': return this._listRooms(userId);
      case 'join': return this._joinRoom(session, packet);
      case 'ready': return this._setReady(session, packet);
      case 'start_game': return this._startGame(session, packet);
      case 'input': return this._input(session, packet);
      case 'action': return this._action(session, packet);
      case 'leave': return this._leave(session);
      case 'ping': return this.send(userId, { type: 'pong', nonce: packet.nonce ?? null });
      default: throw new Error(`Unknown message type: ${packet.type}`);
    }
  }

  onDisconnect(userId) {
    const session = this.sessions.get(userId);
    if (session) this._leave(session, true);
    this.sessions.delete(userId);
    this.clients.delete(userId);
  }

  send(userId, message) {
    return send(this.clients.get(userId), message);
  }

  tick() {
    this.rooms.update(1 / this.tickRate, Date.now());
  }

  stop() {
    clearInterval(this.tickInterval);
    for (const socket of this.clients.values()) socket.close?.();
  }

  _checkRateLimit(session) {
    const now = Date.now();
    session.packets = session.packets.filter((timestamp) => now - timestamp < 1000);
    session.packets.push(now);
    if (session.packets.length > config.maxPacketsPerSecond) throw new Error('Rate limit exceeded');
  }

  _createRoom(session, packet) {
    this._leave(session);
    const room = this.rooms.createRoom(
      text(packet.roomName, 'Quick Match', 32),
      text(packet.mode, 'co-op', 24),
      packet.maxPlayers,
    );
    session.nickname = text(packet.nickname, 'Player', 24);
    room.addPlayer({ userId: session.userId, name: session.nickname, socket: this.clients.get(session.userId) });
    session.roomId = room.id;
    this.send(session.userId, { type: 'room_created', roomId: room.id });
    room.broadcastRoomState();
  }

  _listRooms(userId) {
    this.send(userId, { type: 'room_list', rooms: this.rooms.list() });
  }

  _joinRoom(session, packet) {
    const roomId = text(packet.roomId, '', 64);
    const room = this.rooms.get(roomId);
    if (!room) throw new Error('Room not found');
    session.nickname = text(packet.nickname, session.nickname, 24);
    this._leave(session);
    room.addPlayer({ userId: session.userId, name: session.nickname, socket: this.clients.get(session.userId) });
    session.roomId = room.id;
    room.broadcastRoomState();
  }

  _setReady(session, packet) {
    const room = this._room(session);
    if (!room || !room.setReady(session.userId, Boolean(packet.ready))) throw new Error('Cannot change ready state');
    room.broadcastRoomState();
  }

  _startGame(session, packet) {
    const room = this._room(session);
    if (!room || !room.start(text(packet.mapId, 'map1', 16), session.userId)) {
      throw new Error('Only the room owner can start after everyone is ready');
    }
    room.broadcast({ type: 'game_started', roomId: room.id, mapId: room.mapId });
    room.sendState();
  }

  _input(session, packet) {
    const room = this._room(session);
    if (!room) return;
    room.updateInput(session.userId, packet.move || packet, packet.aimAngle);
  }

  _action(session, packet) {
    const room = this._room(session);
    if (!room) return;
    const action = packet.action;
    if (!action || typeof action !== 'object' || Array.isArray(action)) throw new Error('Invalid action');
    const result = room.handleAction(session.userId, action);
    this.send(session.userId, { type: 'action_result', requestId: packet.requestId ?? null, action: action.type, ...result });
    room.sendState();
  }

  _leave(session, notify = true) {
    if (!session.roomId) return;
    const room = this.rooms.get(session.roomId);
    session.roomId = null;
    if (!room) return;
    room.removePlayer(session.userId);
    if (room.players.size === 0) this.rooms.remove(room.id);
    else if (notify) room.broadcastRoomState();
  }

  _room(session) {
    return session.roomId ? this.rooms.get(session.roomId) : null;
  }
}

module.exports = GameServer;
