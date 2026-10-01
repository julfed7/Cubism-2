# Cubism D authoritative game server

The server is the only authority for network matches. Godot sends player
input and actions over WebSocket; Node.js owns rooms, readiness, movement,
combat, AI, inventory and the replicated world snapshot.

## Run

    npm install
    npm start

The listener uses HOST (default 0.0.0.0), PORT (default 9090) and
TICK_RATE (default 20).

## Protocol v1

Every packet is JSON and contains "v": 1 and a "type".

Client messages:

- create_room: nickname, roomName, mode, maxPlayers
- list_rooms
- join: nickname, roomId
- ready: ready
- start_game: mapId
- input: move {x, y}, aimAngle
- action: action {type, ...} (shoot, reload, select_weapon, use_item,
  pickup, open_chest)
- leave

Server messages are welcome, room_created, room_list, room_state,
game_started, state, action_result, error and pong. A state packet contains
the authoritative entities, players, world, phase, mapId, roomId and server
tick.

## Tests

    npm test
    npm run check
