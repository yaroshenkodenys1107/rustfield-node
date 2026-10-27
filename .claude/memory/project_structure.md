# Files

- `compose.yaml` — two boxes: `wings` (Pterodactyl's worker) and `cloudflared` (the tunnel). The game servers are not
  here: Wings makes them on the server's Docker (label `Service=Pterodactyl`, network `pterodactyl_nw`).
- `rustfield-node` — day-to-day: status, start, stop, restart, update, help. Short command `rustfield-node`.
  `update`: newest code, then the settings are written again IF this code writes them differently (a fingerprint
  of the rendered text in `/etc/pterodactyl/rustfield-settings.md5`; Wings rewriting its own file does not count),
  then the images; Wings restarts only if its settings changed. Game servers keep running.
- `rustfield-node-install` — reads the join code (through `<<<` in the install line, so it never shows in the
  process list; an argument also works), Docker, firewall (SSH only), settings, start, then checks that Wings
  answers through the tunnel (HTTP 401 from `/api/system` = the road works). Run again WITHOUT a code, it reuses
  the saved settings (a failed try can simply be repeated).
- `rustfield-node-delete` — wipes the node: Wings + tunnel FIRST (so Wings cannot restart a game server), then the
  game servers, their files, the images (ours + Pterodactyl's game images, pattern `GAME_IMAGES`; an image another
  box uses stays), settings, this folder. Stops if Docker is installed but not running.
- `tools/steps.sh` — every step; its "Look" part is a copy of the main project's. ShellCheck checks it directly
  (`checks.yml` lists it: `-x` alone only follows it).
- On the server, outside this folder: `/etc/pterodactyl/config.yml` (Wings settings with its key, root only),
  `/var/lib/pterodactyl` (game files), `/var/log/pterodactyl`, `/etc/logrotate.d/rustfield-node`, and `.env` here
  (tunnel key, root only, never in git).
- Wings listens on 443 inside Docker: the panel sends Wings ITS settings after every change of the node (port 443),
  and Wings takes them over; any other port would be replaced and the tunnel would lose Wings.
- The join code: base64 of `KEY=value` lines: NODE_NAME, NODE_ADDRESS, PANEL_URL, WINGS_UUID, WINGS_TOKEN_ID,
  WINGS_TOKEN, TUNNEL_TOKEN. Made by `rustfield node add` on the main server.
