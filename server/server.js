const http = require("http");
const crypto = require("crypto");
const { WebSocketServer } = require("ws");

const port = Number.parseInt(process.env.PORT || "8080", 10);
const rooms = new Map();

const server = http.createServer((req, res) => {
  if (req.url === "/health") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ ok: true, rooms: rooms.size }));
    return;
  }

  res.writeHead(200, { "content-type": "text/plain" });
  res.end("Happy Boo multiplayer server\n");
});

const wss = new WebSocketServer({ server });

wss.on("connection", (socket) => {
  socket.playerId = crypto.randomUUID();
  socket.roomId = "lobby";
  joinRoom(socket, socket.roomId);

  send(socket, {
    type: "welcome",
    player_id: socket.playerId,
    room_id: socket.roomId
  });

  socket.on("message", (raw) => {
    let message;
    try {
      message = JSON.parse(raw.toString());
    } catch (_error) {
      send(socket, { type: "error", message: "Invalid JSON" });
      return;
    }

    if (message.type === "join") {
      const nextRoom = sanitizeRoomId(message.room_id || message.room || "lobby");
      leaveRoom(socket);
      socket.roomId = nextRoom;
      joinRoom(socket, nextRoom);
      send(socket, {
        type: "joined",
        player_id: socket.playerId,
        room_id: socket.roomId
      });
      broadcast(socket, {
        type: "player_joined",
        player_id: socket.playerId,
        room_id: socket.roomId
      });
      return;
    }

    if (message.type === "ping") {
      send(socket, { type: "pong", server_time_ms: Date.now() });
      return;
    }

    broadcast(socket, {
      ...message,
      from_player_id: socket.playerId,
      room_id: socket.roomId
    });
  });

  socket.on("close", () => {
    const roomId = socket.roomId;
    leaveRoom(socket);
    broadcastToRoom(roomId, {
      type: "player_left",
      player_id: socket.playerId,
      room_id: roomId
    });
  });
});

function sanitizeRoomId(value) {
  const roomId = String(value).trim().slice(0, 32);
  return roomId.replace(/[^A-Za-z0-9_-]/g, "") || "lobby";
}

function joinRoom(socket, roomId) {
  if (!rooms.has(roomId)) {
    rooms.set(roomId, new Set());
  }
  rooms.get(roomId).add(socket);
}

function leaveRoom(socket) {
  const room = rooms.get(socket.roomId);
  if (!room) {
    return;
  }
  room.delete(socket);
  if (room.size === 0) {
    rooms.delete(socket.roomId);
  }
}

function broadcast(sender, message) {
  broadcastToRoom(sender.roomId, message, sender);
}

function broadcastToRoom(roomId, message, except = null) {
  const room = rooms.get(roomId);
  if (!room) {
    return;
  }

  for (const socket of room) {
    if (socket !== except) {
      send(socket, message);
    }
  }
}

function send(socket, message) {
  if (socket.readyState === socket.OPEN) {
    socket.send(JSON.stringify(message));
  }
}

server.listen(port, "0.0.0.0", () => {
  console.log(`Happy Boo multiplayer server listening on port ${port}`);
});
