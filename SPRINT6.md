# Sprint 6 — Node.js authoritative multiplayer

## Files

```text
autoloads/NetworkManager.gd
scenes/
  Game.tscn
  Lobby.tscn
  maps/Island.tscn
  maps/City.tscn
  objects/Player.tscn
  objects/Bullet.tscn
  objects/Chest.tscn
  objects/Pickup.tscn
  objects/Zombie.tscn
  ui/HUD.tscn
scripts/
  game.gd
  lobby.gd
  player.gd
  bullet.gd
  chest.gd
  pickup.gd
  zombie.gd
sprites/
  lobby_bg.png
  ui/ready_icon.png
  ui/not_ready_icon.png
sounds/
  music/lobby_music.ogg
  music/match_music.ogg
  ui/connect.wav
  ui/disconnect.wav
```

## Network flow

- `NetworkManager` is an Autoload using `WebSocketPeer` and JSON packets over `ws://.../ws`. The Node.js server owns users, rooms, readiness, match state, movement, combat, loot and respawn.
- The lobby sends `room.ready`; the room owner sends `room.start`. The server broadcasts `room.started` and `room.state`, then Godot switches to `Game.tscn`.
- `Game.tscn` contains only visual containers. Players, zombies, bullets, chests and pickups are created from server snapshots; no Godot ENet/RPC/spawner is used.
- Clients send movement intent at 20 Hz and action intents (`shoot`, `reload`, `select_weapon`, `use_item`, `pickup`, `open_chest`). The server validates and simulates them; health, inventory and positions come back in snapshots.
- The Node.js server exposes `GET /health` and WebSocket `/ws`. A disconnected client is removed from its room; a closed server returns the Godot client to Main Menu.

## Visuals and audio

- HUD health uses a dark rounded panel with a red rounded panel over it. The red width is `200 * current_health / max_health`; it uses no texture.
- `lobby_bg.png` is 1920×1080. Ready icons are 32×32 transparent PNGs.
- Lobby and match tracks are generated loopable chiptune-style OGG files of 30 and 60 seconds. `lobby.gd` enables looping and plays the connection sounds; `game.gd` enables looping for match music. The WAV connection cues are 0.28 and 0.32 seconds.

## Run and check

Run `game-server/npm install && npm start`, then run the Godot project. The default endpoint is `ws://127.0.0.1:8080/ws`; remote clients use the server machine address. `npm test`, `npm run check` and Godot 4.7.2 headless scene-load checks pass. The server still requires the `ws` npm dependency to be installed before launch.
