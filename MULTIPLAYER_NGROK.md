# Multiplayer Server With Docker and ngrok

This repo includes a small WebSocket relay server for multiplayer experiments. It does not add multiplayer gameplay to Godot yet; it gives the game a public server URL to connect to when that client code is added.

## What You Need

- Docker running on your computer.
- Docker Compose. Docker Desktop usually includes it; if `docker compose version` fails, enable or install the Compose plugin.
- An ngrok account.
- Your ngrok auth token from the ngrok dashboard.

Do not commit your ngrok token.

## Setup

1. Copy the example env file:

   ```bash
   cp .env.example .env
   ```

2. Open `.env` and replace the placeholder:

   ```bash
   NGROK_AUTHTOKEN=your_real_ngrok_token
   ```

3. Start the server and ngrok tunnel:

   ```bash
   docker compose up --build
   ```

   If your Docker install uses the older standalone Compose command:

   ```bash
   docker-compose up --build
   ```

4. Open the local ngrok dashboard:

   ```text
   http://localhost:4040
   ```

5. Copy the public `https://...ngrok...` forwarding URL. For Godot WebSocket multiplayer, use the same URL with `wss://` instead of `https://`.

   Example:

   ```text
   https://example.ngrok-free.app
   wss://example.ngrok-free.app
   ```

6. Health check:

   ```bash
   curl https://example.ngrok-free.app/health
   ```

## Godot Client URL

When multiplayer client code is added, the web client should connect to:

```gdscript
var multiplayer_url := "wss://example.ngrok-free.app"
```

## Notes

- The `happy-boo-server` container listens on port `8080`.
- The `ngrok` container exposes that server publicly.
- Rooms currently allow 4 players max. Change `MAX_PLAYERS_PER_ROOM` in `compose.yaml` to adjust this for local testing.
- The current relay supports rooms, host assignment, join messages, ping/pong, and broadcasting JSON messages to other players in the same room.
- The ngrok URL can change unless your ngrok account has a reserved/static domain.
