# ocserv-tunnel

Multi-tenant SSL VPN POP based on [ocserv](https://gitlab.com/openconnect/ocserv) — Route B integration for VPN platforms.

Single domain + `select-group-by-url` (`https://{pop}/{access_key}`), RADIUS `TunnelGroupName` (Cisco VSA 146), hot-add groups via SIGHUP, and POP management API sidecar.

## Features

- **URL tenant selection** — ASAv `group-url` equivalent via `select-group-by-url`
- **RADIUS auth** — radcli + FreeRADIUS; platform policy via Access-Accept
- **Hot-add groups** — `config-per-group/{access_key}` + SIGHUP (no restart)
- **POP API (P2 sidecar)** — Go HTTP API for Worker provisioning
- **Gate POC G1–G6** — automated acceptance tests in `gate-poc/`
- **Fork patches** — TunnelGroupName VSA 146 (SPEC-01, P1)

## Quick start (Ubuntu 24.04 POP)

```bash
git clone https://github.com/hk59775634/ocserv-tunnel.git
cd ocserv-tunnel
sudo bash scripts/prod-ocserv-install.sh
```

Build pop-api sidecar:

```bash
cd pop-api && go build -o ocserv-pop-api .
sudo install -m 0755 ocserv-pop-api /usr/local/bin/
sudo cp deploy/systemd/ocserv-pop-api.service /etc/systemd/system/
# Set OCSERV_API_KEY in /etc/ocserv/pop-api.env
sudo systemctl enable --now ocserv-pop-api
```

Run gate tests:

```bash
export POP_HOST=127.0.0.1 OCSERV_API_KEY=your_key
bash gate-poc/scripts/run-all.sh
```

## Layout

```
ocserv-tunnel/
├── configs/           # ocserv.d + radcli dictionary
├── patches/           # ocserv fork patches (TunnelGroupName)
├── pop-api/           # P2 sidecar REST API
├── deploy/systemd/    # Unit files
├── scripts/           # build + prod install
└── gate-poc/          # G1–G6 gate POC
```

## POP API (P2 sidecar)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/status` | ocserv running state |
| POST | `/api/v1/reload` | SIGHUP reload |
| POST | `/api/v1/groups` | Hot-add config-per-group |
| DELETE | `/api/v1/groups/{name}` | Remove group |
| PUT | `/api/v1/certificate` | TLS cert hot update |

Header: `X-API-Key: <OCSERV_API_KEY>`

## Gate POC results

See [`gate-poc/docs/REPORT.md`](gate-poc/docs/REPORT.md). Decision: **P2 sidecar** ([G6](gate-poc/docs/G6-pop-api-decision.md)).

## ocserv version

- Ubuntu apt ships **1.2.4** (no `select-group-by-url`)
- Install script builds **1.4.2** from source when needed
- Baseline tag: `1.4.2`

## License

ocserv-derived patches are **GPLv2**. Configs, pop-api sidecar, and scripts follow the same policy as upstream ocserv integration work.
