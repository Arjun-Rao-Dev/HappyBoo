# Happy Boo Relay Server

Minimal in-memory WebSocket relay for web multiplayer.

## Run locally

```bash
cd server/relay
npm install
npm start
```

Defaults:
- Host: `0.0.0.0`
- Port: `8080`
- Relay URL in game: `ws://127.0.0.1:8080`

Optional env vars:

```bash
HOST=0.0.0.0 PORT=8080 npm start
```

## Message protocol

Client -> server:
- `create_room`
- `join_room`
- `set_username`
- `start_match`
- `input`
- `snapshot`
- `event`
- `leave`

Server -> client:
- `room_created`
- `join_ok`
- `roster`
- `match_started`
- `relay_input`
- `relay_snapshot`
- `relay_event`
- `host_disconnected`
- `error`

## Notes

- Rooms are in-memory only and reset when process restarts.
- First peer in a room is host (`peer_id = 1`).
- Host is authoritative for match start, snapshots, and events.
- Non-host peers can only send input.
