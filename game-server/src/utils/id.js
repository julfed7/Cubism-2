const { randomUUID } = require('node:crypto');

function generateId(length = 8) {
  const safeLength = Math.max(4, Math.min(32, Number(length) || 8));
  return randomUUID().replaceAll('-', '').slice(0, safeLength);
}

module.exports = generateId;
module.exports.generateId = generateId;
