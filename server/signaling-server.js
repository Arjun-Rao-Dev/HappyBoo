import { WebSocketServer } from 'ws';

const PORT = Number(process.env.PORT || 8080);
const MAX_PLAYERS = 4;

let nextPeerId = 1;
const peers = new Map(); // ws -> { peerId, username, roomCode }
const rooms = new Map(); // roomCode -> { hostPeerId, mode, maxPlayers, members:Set<peerId> }

const wss = new WebSocketServer({ port: PORT });

function send(ws, payload) {
  if (ws.readyState !== ws.OPEN) return;
  ws.send(JSON.stringify(payload));
}

function peerById(peerId) {
  for (const [ws, info] of peers.entries()) {
    if (info.peerId === peerId) return { ws, info };
  }
  return null;
}

function roomPlayersObject(room) {
  const out = {};
  for (const peerId of room.members) {
    const entry = peerById(peerId);
    if (!entry) continue;
    out[String(peerId)] = { username: entry.info.username || 'Player' };
  }
  return out;
}

function broadcastRoom(roomCode, payload) {
  const room = rooms.get(roomCode);
  if (!room) return;
  for (const peerId of room.members) {
    const entry = peerById(peerId);
    if (!entry) continue;
    send(entry.ws, payload);
  }
}

function randomCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < 6; i += 1) {
    code += chars[Math.floor(Math.random() * chars.length)];
  }
  return code;
}

function allocateRoomCode() {
  for (let i = 0; i < 100; i += 1) {
    const code = randomCode();
    if (!rooms.has(code)) return code;
  }
  return `${Date.now()}`.slice(-6);
}

function leaveRoom(ws) {
  const info = peers.get(ws);
  if (!info || !info.roomCode) return;

  const roomCode = info.roomCode;
  const room = rooms.get(roomCode);
  info.roomCode = '';

  if (!room) return;

  room.members.delete(info.peerId);

  if (room.hostPeerId === info.peerId) {
    broadcastRoom(roomCode, {
      type: 'host_disconnected',
      reason: 'Host left the room.'
    });
    for (const peerId of room.members) {
      const entry = peerById(peerId);
      if (entry) entry.info.roomCode = '';
    }
    rooms.delete(roomCode);
    return;
  }

  if (room.members.size === 0) {
    rooms.delete(roomCode);
    return;
  }

  broadcastRoom(roomCode, {
    type: 'roster',
    players: roomPlayersObject(room)
  });
}

wss.on('connection', (ws) => {
  const peerId = nextPeerId++;
  peers.set(ws, {
    peerId,
    username: `Player${peerId}`,
    roomCode: ''
  });

  send(ws, { type: 'welcome', peer_id: peerId });

  ws.on('message', (raw) => {
    let msg;
    try {
      msg = JSON.parse(String(raw));
    } catch {
      send(ws, { type: 'error', message: 'Invalid JSON payload.' });
      return;
    }

    const info = peers.get(ws);
    if (!info) return;
    const type = String(msg.type || '');

    if (type === 'hello') {
      const username = String(msg.username || '').trim();
      if (username) info.username = username;
      send(ws, { type: 'status', message: `Hello ${info.username}` });
      return;
    }

    if (type === 'create_room') {
      leaveRoom(ws);
      const roomCode = allocateRoomCode();
      const mode = msg.mode === 'pvp' ? 'pvp' : 'team';
      const room = {
        hostPeerId: info.peerId,
        mode,
        maxPlayers: Math.min(MAX_PLAYERS, Math.max(2, Number(msg.max_players || MAX_PLAYERS))),
        members: new Set([info.peerId])
      };
      rooms.set(roomCode, room);
      info.roomCode = roomCode;

      send(ws, {
        type: 'room_created',
        room_code: roomCode,
        host_peer_id: room.hostPeerId,
        players: roomPlayersObject(room)
      });
      return;
    }

    if (type === 'join_room') {
      leaveRoom(ws);
      const roomCode = String(msg.room_code || '').trim().toUpperCase();
      const room = rooms.get(roomCode);
      if (!room) {
        send(ws, { type: 'error', message: 'Room not found.' });
        return;
      }
      if (room.members.size >= room.maxPlayers) {
        send(ws, { type: 'error', message: 'Room is full.' });
        return;
      }

      info.roomCode = roomCode;
      room.members.add(info.peerId);

      send(ws, {
        type: 'room_joined',
        room_code: roomCode,
        host_peer_id: room.hostPeerId,
        players: roomPlayersObject(room)
      });

      broadcastRoom(roomCode, {
        type: 'roster',
        players: roomPlayersObject(room)
      });
      return;
    }

    if (type === 'leave_room') {
      leaveRoom(ws);
      return;
    }

    if (type === 'start_match') {
      const room = rooms.get(info.roomCode);
      if (!room) {
        send(ws, { type: 'error', message: 'Join a room first.' });
        return;
      }
      if (room.hostPeerId !== info.peerId) {
        send(ws, { type: 'error', message: 'Only host can start.' });
        return;
      }
      if (room.members.size < 2) {
        send(ws, { type: 'error', message: 'Need at least 2 players.' });
        return;
      }

      broadcastRoom(info.roomCode, {
        type: 'start_match',
        mode: room.mode,
        room_code: info.roomCode,
        host_peer_id: room.hostPeerId
      });
      return;
    }

    if (type === 'relay_input' || type === 'relay_snapshot' || type === 'relay_event') {
      const room = rooms.get(info.roomCode);
      if (!room) return;
      for (const peerId of room.members) {
        if (peerId === info.peerId) continue;
        const entry = peerById(peerId);
        if (!entry) continue;
        if (type === 'relay_input') {
          send(entry.ws, { type, from: info.peerId, input: msg.input || {} });
        } else if (type === 'relay_snapshot') {
          send(entry.ws, { type, from: info.peerId, snapshot: msg.snapshot || {} });
        } else {
          send(entry.ws, { type, from: info.peerId, event: msg.event || {} });
        }
      }
      return;
    }

    send(ws, { type: 'error', message: `Unknown message type: ${type}` });
  });

  ws.on('close', () => {
    leaveRoom(ws);
    peers.delete(ws);
  });
});

console.log(`Signaling server running on ws://0.0.0.0:${PORT}`);
