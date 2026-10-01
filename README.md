# Cubism D — Спринт 1

Импортируйте project.godot в Godot 4.x и нажмите F6 для текущей сцены или F5 для проекта.
Рендерер: Forward+. Главная сцена: scenes/MainMenu.tscn.

- Compaign → Levels → 1 / 2 → Level 1 / Level 2 → Exit → главное меню.
- Create Room → Create → Node.js lobby.
- Join Room → Update → выберите комнату Node.js и войдите.
- Settings: Text — placeholder пустого поля. Введённый ник хранится в GameState до закрытия приложения.
- При прямом запуске Game.tscn без выбранного уровня отображается Game.
- Сетевой клиент Godot подключается к `ws://127.0.0.1:9090`; адрес можно изменить в `NetworkManager.gd` или в поле Join Room.
- `game-server/` — authoritative Node.js WebSocket-сервер. Запуск: `npm install`, затем `npm start`.
- sprites/ — спрайты и фоны; settings/ — настройки и служебные ресурсы; tilemaps/ — карты и тайлы.

Интерфейс использует анкоры, контейнеры и масштабирование canvas_items / expand от 1366 × 768.
