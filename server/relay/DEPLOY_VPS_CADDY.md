# Deploy Relay on Ubuntu VPS (`relay.arjunrao.dev`)

This guide deploys the relay as a private local service (`127.0.0.1:8080`) behind Caddy TLS on `443`.

## 1) DNS

Create an `A` record:

- `relay.arjunrao.dev -> <VPS_PUBLIC_IP>`

Wait for DNS to propagate.

## 2) Install runtime and proxy

```bash
sudo apt update
sudo apt install -y curl git ufw debian-keyring debian-archive-keyring apt-transport-https
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install -y caddy
```

## 3) Firewall

```bash
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable
sudo ufw status
```

Do not open `8080` publicly.

## 4) Deploy relay app

```bash
sudo mkdir -p /opt/happyboo
sudo chown -R $USER:$USER /opt/happyboo
git clone https://github.com/Arjun-Rao-Dev/HappyBoo.git /opt/happyboo
cd /opt/happyboo/server/relay
npm install --omit=dev
```

## 5) Install systemd service

```bash
sudo cp /opt/happyboo/server/relay/deploy/happyboo-relay.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now happyboo-relay
sudo systemctl status happyboo-relay --no-pager
```

If `/usr/bin/node` path differs, update `ExecStart` in the service file.

## 6) Configure Caddy TLS/WebSocket proxy

```bash
sudo cp /opt/happyboo/server/relay/deploy/Caddyfile /etc/caddy/Caddyfile
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
sudo systemctl status caddy --no-pager
```

## 7) Verify

```bash
curl -I https://relay.arjunrao.dev
sudo journalctl -u happyboo-relay -n 50 --no-pager
```

Expected:

- HTTPS endpoint responds on `relay.arjunrao.dev`
- Relay service is active
- Browser connects with `wss://relay.arjunrao.dev`

## 8) Game URL setting

For GitHub Pages/web builds, use:

- `wss://relay.arjunrao.dev`

For local desktop debugging only:

- `ws://127.0.0.1:8080`
