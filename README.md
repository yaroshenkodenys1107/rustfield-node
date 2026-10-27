# Rustfield.eu node

Turns any server into a game server **node** for the Rustfield.eu Pterodactyl panel.

A node runs two ready-made programs in Docker:

- **Wings** (Pterodactyl's worker): takes orders from the panel and starts, stops and watches the game servers, one
  Docker box each.
- **cloudflared** (Cloudflare Tunnel): the panel's road to Wings. It calls out, so Wings needs no open port.

Players reach the game servers directly on their game ports (28000–28999, opened by Docker only while a game server
uses them). Only SSH is open in the firewall.

## Add a node

1. On the main server: `rustfield node add`, fill in the form. It prints one install line.
2. On the new server (as root): paste that line. It installs Docker if needed, this repo, Wings and the tunnel.
   If it fails halfway, run `./rustfield-node-install` again in `/root/rustfield-node`: it reuses the saved settings.

## Every day

`rustfield-node status` · `start` · `stop` · `restart` · `update` · `help`

## Remove a node

1. On the main server: `rustfield node delete` (removes it from the panel and Cloudflare).
2. On the node: `cd /root/rustfield-node && ./rustfield-node-delete`. It wipes Wings, the tunnel, every game server
   and its files, and their images, with no backup. Docker and the firewall stay.

This repo is public and holds no secrets: the node's keys come with the join code and stay in `.env` on the node.
