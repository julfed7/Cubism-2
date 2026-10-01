const WebSocket = require('ws');

const PORT = 9090;
const TICK_RATE = 20;
const MAX_PLAYERS = 20;

const wss = new WebSocket.Server({ port: PORT, host: '0.0.0.0' });
console.log(`[SERVER] Запущен на ws://0.0.0.0:${PORT}`);

const clients = new Map();
const players = new Map();
const rooms = new Map();
let nextPlayerId = 1;
let nextRoomId = 1;

function send(playerId, data) {
  const ws = clients.get(playerId);
  if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(data));
}

function sendError(playerId, message) {
  send(playerId, { type: 'error', message });
}

function cleanText(value, fallback, maxLength = 32) {
  const result = String(value ?? '').trim().slice(0, maxLength);
  return result || fallback;
}

function mapSpawn(mapName) {
  return mapName === 'City' ? { x: 100, y: 100 } : { x: 200, y: 0 };
}

function roomPlayers(room) {
  const result = {};
  for (const playerId of room.players) {
    const player = players.get(playerId);
    if (player) result[playerId] = player;
  }
  return result;
}

function roomData(room) {
  return {
    id: room.id,
    name: room.name,
    mode: room.mode,
    map: room.map,
    host_id: room.hostId,
    started: room.started,
    players: roomPlayers(room),
  };
}

function broadcastRoom(room, data) {
  const message = JSON.stringify(data);
  for (const playerId of room.players) {
    const ws = clients.get(playerId);
    if (ws && ws.readyState === WebSocket.OPEN) ws.send(message);
  }
}

function sendLobbyState(room) {
  broadcastRoom(room, { type: 'lobby_state', room: roomData(room) });
}

function leaveRoom(playerId, notify = true) {
  const player = players.get(playerId);
  if (!player || !player.roomId) return;
  const room = rooms.get(player.roomId);
  player.roomId = '';
  if (!room) return;
  room.players.delete(playerId);
  if (room.players.size === 0) {
    rooms.delete(room.id);
    console.log(`[ROOM ${room.id}] Удалена: игроков не осталось`);
    return;
  }
  if (room.hostId === playerId) room.hostId = room.players.values().next().value;
  if (notify) {
    broadcastRoom(room, { type: 'player_left', id: playerId });
    sendLobbyState(room);
  }
}

function createRoom(playerId, request, automatic = false) {
  leaveRoom(playerId, true);
  const player = players.get(playerId);
  const id = `R${String(nextRoomId++).padStart(4, '0')}`;
  const room = {
    id,
    name: cleanText(request.room_name, automatic ? `Быстрая игра ${id}` : `Комната ${id}`),
    mode: cleanText(request.game_mode, 'Королевская битва'),
    map: ['Island', 'City'].includes(request.map_name) ? request.map_name : 'Island',
    hostId: playerId,
    started: false,
    zombies: null,
    players: new Set([playerId]),
  };
  const spawn = mapSpawn(room.map);
  player.x = spawn.x;
  player.y = spawn.y;
  rooms.set(id, room);
  player.roomId = id;
  console.log(`[ROOM ${id}] Создана: host=#${playerId} nickname="${player.nickname}" map=${room.map} mode="${room.mode}"`);
  send(playerId, { type: 'room_joined', room: roomData(room) });
  sendLobbyState(room);
  return room;
}

function joinRoom(playerId, room) {
  if (!room || room.players.size >= MAX_PLAYERS) {
    sendError(playerId, 'Комната недоступна или заполнена');
    return false;
  }
  leaveRoom(playerId, true);
  const player = players.get(playerId);
  player.roomId = room.id;
  const spawn = mapSpawn(room.map);
  player.x = spawn.x;
  player.y = spawn.y;
  room.players.add(playerId);
  console.log(`[ROOM ${room.id}] Подключился #${playerId} nickname="${player.nickname}" (${room.players.size}/${MAX_PLAYERS})`);
  send(playerId, { type: 'room_joined', room: roomData(room) });
  sendLobbyState(room);
  return true;
}

wss.on('connection', (ws, request) => {
  const playerId = nextPlayerId++;
  const player = {
    id: playerId, x: 2500, y: 2500, hp: 100, maxHp: 100,
    weapon: '', ammo: 0, reserve: 0, alive: true,
    nickname: `Player${playerId}`, roomId: '',
  };

  clients.set(playerId, ws);
  players.set(playerId, player);
  const remoteAddress = request.socket.remoteAddress || 'unknown';
  console.log(`[SOCKET] Подключение #${playerId} с ${remoteAddress}. Соединений: ${clients.size}`);
  send(playerId, { type: 'welcome', your_id: playerId, players: {} });

  ws.on('message', (message) => {
    let data;
    try {
      data = JSON.parse(message.toString());
    } catch (_error) {
      sendError(playerId, 'Некорректный JSON');
      return;
    }
    const currentPlayer = players.get(playerId);
    if (!currentPlayer) return;
    if (data.nickname !== undefined) currentPlayer.nickname = cleanText(data.nickname, currentPlayer.nickname);

    switch (data.type) {
      case 'join':
        console.log(`[PLAYER] Представился #${playerId}: nickname="${currentPlayer.nickname}"`);
        break;
      case 'create_room':
        createRoom(playerId, data);
        break;
      case 'join_room': {
        const requestedRoom = rooms.get(cleanText(data.room_id, '', 16));
        if (!requestedRoom) sendError(playerId, `Комната ${data.room_id || ''} не найдена`);
        else joinRoom(playerId, requestedRoom);
        break;
      }
      case 'quick_play': {
        const requestedMap = ['Island', 'City'].includes(data.map_name) ? data.map_name : 'Island';
        const room = [...rooms.values()].find((candidate) =>
          candidate.map === requestedMap && candidate.players.size < MAX_PLAYERS
        );
        if (room) joinRoom(playerId, room);
        else createRoom(playerId, {
          room_name: `Быстрая игра: ${requestedMap}`,
          game_mode: 'Королевская битва',
          map_name: requestedMap,
        }, true);
        break;
      }
      case 'start_game': {
        const room = rooms.get(currentPlayer.roomId);
        if (!room || room.hostId !== playerId) {
          sendError(playerId, 'Только хозяин комнаты может начать игру');
          break;
        }
        room.started = true;
        console.log(`[ROOM ${room.id}] Матч начат: map=${room.map}, players=${room.players.size}`);
        broadcastRoom(room, { type: 'game_started', map_name: room.map, game_mode: room.mode });
        break;
      }
      case 'leave_room':
        leaveRoom(playerId);
        break;
      case 'move':
        if (Number.isFinite(data.x) && Number.isFinite(data.y)) {
          currentPlayer.x = data.x;
          currentPlayer.y = data.y;
        }
        break;
      case 'zombie_state': {
        const room = rooms.get(currentPlayer.roomId);
        if (!room || room.hostId !== playerId || !Array.isArray(data.zombies)) break;
        room.zombies = data.zombies.slice(0, 256).filter((zombie) =>
          zombie && typeof zombie.id === 'string' &&
          Number.isFinite(zombie.x) && Number.isFinite(zombie.y) &&
          Number.isFinite(zombie.hp)
        );
        break;
      }
      case 'shoot': {
        const room = rooms.get(currentPlayer.roomId);
        if (room && Array.isArray(data.dir) && data.dir.length >= 2) {
          broadcastRoom(room, {
            type: 'shot_fired', id: playerId,
            origin: [currentPlayer.x, currentPlayer.y],
            dir: [Number(data.dir[0]) || 0, Number(data.dir[1]) || 0],
            weapon: currentPlayer.weapon,
          });
        }
        break;
      }
      case 'select_weapon':
        currentPlayer.weapon = cleanText(data.weapon, '', 32);
        break;
      default:
        break;
    }
  });

  ws.on('close', () => {
    const disconnected = players.get(playerId);
    const nickname = disconnected ? disconnected.nickname : `Player${playerId}`;
    const roomId = disconnected ? disconnected.roomId : '';
    console.log(`[SOCKET] Отключение #${playerId} nickname="${nickname}" room=${roomId || '—'}`);
    leaveRoom(playerId);
    clients.delete(playerId);
    players.delete(playerId);
  });

  ws.on('error', (error) => {
    console.error(`[SOCKET] Ошибка #${playerId} nickname="${player.nickname}": ${error.message}`);
  });
});

setInterval(() => {
  for (const room of rooms.values()) {
    if (room.started && room.players.size > 0) {
      const state = { type: 'state', players: roomPlayers(room) };
      if (room.zombies !== null) state.zombies = room.zombies;
      broadcastRoom(room, state);
    }
  }
}, 1000 / TICK_RATE);
