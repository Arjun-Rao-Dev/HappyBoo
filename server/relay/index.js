'use strict';

const WebSocket = require('ws');

const PORT = parseInt(process.env.PORT || '8080', 10);
const HOST = process.env.HOST || '0.0.0.0';
const ROOM_CODE_LENGTH = 6;
const MAX_ROOM_CREATE_ATTEMPTS = 100;

const rooms = new Map();

function randomCode() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < ROOM_CODE_LENGTH; i += 1) {
    code += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return code;
}

function generateRoomCode() {
  for (let i = 0; i < MAX_ROOM_CREATE_ATTEMPTS; i += 1) {
    const code = randomCode();
    if (!rooms.has(code)) {
      return code;
    }
  }
  return null;
}

function send(socket, payload) {
  if (!socket || socket.readyState !== WebSocket.OPEN) {
    return;
  }
  socket.send(JSON.stringify(payload));
}

function normalizeUsername(username, fallback) {
  if (typeof username !== 'string') {
    return fallback;
  }
  const cleaned = username.trim();
  return cleaned.length > 0 ? cleaned : fallback;
}

function roomRoster(room) {
  const roster = {};
  for (const [peerId, client] of room.clients.entries()) {
    roster[String(peerId)] = { username: client.username || `Player${peerId}` };
  }
  return roster;
}

function broadcastRoster(room) {
  const players = roomRoster(room);
  for (const [, client] of room.clients.entries()) {
    send(client.socket, { type: 'roster', players });
  }
}

function removeClientFromRoom(client, { notify = true } = {}) {
  if (!client.roomCode || !rooms.has(client.roomCode)) {
    client.roomCode = null;
    client.peerId = null;
    client.isHost = false;
    return;
  }

  const room = rooms.get(client.roomCode);
  const wasHost = client.isHost;
  room.clients.delete(client.peerId);

  if (wasHost) {
    for (const [, member] of room.clients.entries()) {
      send(member.socket, {
        type: 'host_disconnected',
        reason: 'Host disconnected.',
      });
      member.roomCode = null;
      member.peerId = null;
      member.isHost = false;
    }
    rooms.delete(room.code);
  } else {
    if (notify && room.clients.size > 0) {
      broadcastRoster(room);
    }
  }

  client.roomCode = null;
  client.peerId = null;
  client.isHost = false;
}

function requireRoom(client) {
  if (!client.roomCode) {
    send(client.socket, { type: 'error', message: 'Not in a room.' });
    return null;
  }
  const room = rooms.get(client.roomCode);
  if (!room) {
    send(client.socket, { type: 'error', message: 'Room no longer exists.' });
    removeClientFromRoom(client, { notify: false });
    return null;
  }
  return room;
}

function ensureHost(client, room, actionLabel) {
  if (!client.isHost || room.hostPeerId !== client.peerId) {
    send(client.socket, { type: 'error', message: `Only host may send ${actionLabel}.` });
    return false;
  }
  return true;
}

function ensureNonHost(client, actionLabel) {
  if (client.isHost) {
    send(client.socket, { type: 'error', message: `Host cannot send ${actionLabel}.` });
    return false;
  }
  return true;
}

const wss = new WebSocket.Server({ port: PORT, host: HOST });

wss.on('connection', (socket) => {
  const client = {
    socket,
    roomCode: null,
    peerId: null,
    isHost: false,
    username: 'Player',
  };

  socket.on('message', (raw) => {
    let message;
    try {
      message = JSON.parse(raw.toString());
    } catch (_err) {
      send(socket, { type: 'error', message: 'Invalid JSON.' });
      return;
    }

    const type = typeof message.type === 'string' ? message.type : '';

    if (type === 'create_room') {
      removeClientFromRoom(client, { notify: false });

      const roomCode = generateRoomCode();
      if (!roomCode) {
        send(socket, { type: 'error', message: 'Could not allocate room code.' });
        return;
      }

      const maxPlayersRaw = Number.isFinite(message.max_players) ? message.max_players : 4;
      const maxPlayers = Math.min(Math.max(Math.floor(maxPlayersRaw), 2), 4);

      const room = {
        code: roomCode,
        hostPeerId: 1,
        nextPeerId: 2,
        maxPlayers,
        mode: typeof message.mode === 'string' ? message.mode : 'team',
        clients: new Map(),
      };

      client.peerId = 1;
      client.isHost = true;
      client.roomCode = roomCode;
      client.username = normalizeUsername(message.username, `Player${client.peerId}`);
      room.clients.set(client.peerId, client);
      rooms.set(roomCode, room);

      send(socket, {
        type: 'room_created',
        room_code: roomCode,
        peer_id: client.peerId,
        is_host: true,
        roster: roomRoster(room),
      });
      return;
    }

    if (type === 'join_room') {
      removeClientFromRoom(client, { notify: false });
      const requestedCode = typeof message.room_code === 'string' ? message.room_code.trim().toUpperCase() : '';
      if (!requestedCode || !rooms.has(requestedCode)) {
        send(socket, { type: 'error', message: 'Room not found.' });
        return;
      }

      const room = rooms.get(requestedCode);
      if (room.clients.size >= room.maxPlayers) {
        send(socket, { type: 'error', message: 'Room is full.' });
        return;
      }

      const peerId = room.nextPeerId;
      room.nextPeerId += 1;

      client.peerId = peerId;
      client.isHost = false;
      client.roomCode = requestedCode;
      client.username = normalizeUsername(message.username, `Player${peerId}`);
      room.clients.set(peerId, client);

      send(socket, {
        type: 'join_ok',
        room_code: requestedCode,
        peer_id: peerId,
        is_host: false,
        roster: roomRoster(room),
      });
      broadcastRoster(room);
      return;
    }

    if (type === 'set_username') {
      const room = requireRoom(client);
      if (!room) {
        return;
      }
      client.username = normalizeUsername(message.username, `Player${client.peerId}`);
      broadcastRoster(room);
      return;
    }

    if (type === 'start_match') {
      const room = requireRoom(client);
      if (!room || !ensureHost(client, room, 'start_match')) {
        return;
      }
      const mode = typeof message.mode === 'string' ? message.mode : room.mode;
      room.mode = mode;
      for (const [, member] of room.clients.entries()) {
        send(member.socket, { type: 'match_started', mode });
      }
      return;
    }

    if (type === 'input') {
      const room = requireRoom(client);
      if (!room || !ensureNonHost(client, 'input')) {
        return;
      }
      const host = room.clients.get(room.hostPeerId);
      if (!host) {
        send(socket, { type: 'error', message: 'Host is unavailable.' });
        return;
      }
      send(host.socket, {
        type: 'relay_input',
        peer_id: client.peerId,
        payload: message.payload || {},
      });
      return;
    }

    if (type === 'snapshot') {
      const room = requireRoom(client);
      if (!room || !ensureHost(client, room, 'snapshot')) {
        return;
      }
      for (const [peerId, member] of room.clients.entries()) {
        if (peerId === room.hostPeerId) {
          continue;
        }
        send(member.socket, {
          type: 'relay_snapshot',
          payload: message.payload || {},
        });
      }
      return;
    }

    if (type === 'event') {
      const room = requireRoom(client);
      if (!room || !ensureHost(client, room, 'event')) {
        return;
      }
      for (const [peerId, member] of room.clients.entries()) {
        if (peerId === room.hostPeerId) {
          continue;
        }
        send(member.socket, {
          type: 'relay_event',
          payload: message.payload || {},
        });
      }
      return;
    }

    if (type === 'leave') {
      removeClientFromRoom(client);
      return;
    }

    send(socket, { type: 'error', message: `Unknown message type: ${type || '(empty)'}` });
  });

  socket.on('close', () => {
    removeClientFromRoom(client);
  });

  socket.on('error', () => {
    removeClientFromRoom(client);
  });
});

wss.on('listening', () => {
  console.log(`Relay server listening on ws://${HOST}:${PORT}`);
});
