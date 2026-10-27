# Files

- `compose.yaml` — two boxes: `wings` (Pterodactyl's worker) and `cloudflared` (the tunnel). The game servers are not
  here: Wings makes them on the server's Docker (label `Service=Pterodactyl`, network `pterodactyl_nw`).
- `rustfield-node` — day-to-day: status, start, stop, restart, update, help. Short command `rustfield-node`.
- `rustfield-node-install <join code>` — Docker, firewall (SSH only), settings from the join code, start, then checks
  that Wings answers through the tunnel (HTTP 401 from `/api/system` = the road works).
- `rustfield-node-delete` — wipes the node (game servers + files, Wings, tunnel, settings, this folder).
- `tools/steps.sh` — every step; its "Look" part is a copy of the main project's.
- On the server, outside this folder: `/etc/pterodactyl/config.yml` (Wings settings with its key, root only),
  `/var/lib/pterodactyl` (game files), `/var/log/pterodactyl`, `/etc/logrotate.d/rustfield-node`, and `.env` here
  (tunnel key, root only, never in git).
- The join code: base64 of `KEY=value` lines: NODE_NAME, NODE_ADDRESS, PANEL_URL, WINGS_UUID, WINGS_TOKEN_ID,
  WINGS_TOKEN, TUNNEL_TOKEN. Made by `rustfield node add` on the main server.
