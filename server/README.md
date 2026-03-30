# Multiplayer Signaling Server

Minimal room-code WebSocket signaling service for the Godot multiplayer lobby.

## Run

```bash
cd server
npm install
npm start
```

Default endpoint: `ws://localhost:8080`

## Messages

- `hello`
- `create_room`
- `join_room`
- `leave_room`
- `start_match`
- `relay_input`
- `relay_snapshot`
- `relay_event`

All rooms are in-memory and reset when the process restarts.
