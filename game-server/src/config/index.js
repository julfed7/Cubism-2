function numberEnv(name, fallback, minimum) {
  const value = Number(process.env[name]);
  return Number.isFinite(value) && value >= minimum ? value : fallback;
}

module.exports = Object.freeze({
  // The game server is a separate local process during development.
  host: process.env.HOST || '0.0.0.0',
  port: numberEnv('PORT', 9090, 1),
  tickRate: numberEnv('TICK_RATE', 20, 1),
  maxPlayersPerRoom: numberEnv('MAX_PLAYERS_PER_ROOM', 20, 1),
  maxRooms: numberEnv('MAX_ROOMS', 32, 1),
  maxPacketsPerSecond: numberEnv('MAX_PACKETS_PER_SECOND', 120, 10),
});
