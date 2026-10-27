# Rustfield.eu node: the shared steps of ./rustfield-node, ./rustfield-node-install and ./rustfield-node-delete.
# Every step is one bash function. A script is only a list of step names (STEPS=(...)), run in order by run_steps.
# A step checks what it needs first (a wrong order stops with a clear message) and is safe to run again.
# The scripts read this file with `source` after setting ROOT (the project folder); it does nothing on its own.
#
# The "Look" part below is a COPY of the main project's look (rustfield.eu repo, tools/steps.sh), so a node looks
# the same as the main server. The main repo is private, so a node cannot read it from there. A change to the look
# is made in both repos.

# ── Look: one style for every script ───────────────────────────────────────────────────────────────────────────
# The "timeline" look: a ◆ Rustfield.eu title, then lines that hang on a thin line (├─ ╰─). No frames.
# Colors from the Rustfield.eu color system (repo rustfield-color-system), made for a dark terminal.
C_ACCENT='#CD412B'   # --accent (rust-500): the brand, the progress bar
C_OK='#22C55E'       # --success: done
C_WORK='#FBBF24'     # --warning: working
C_FAIL='#EF4444'     # --danger: failed
C_TEXT='#FFFFFF'     # --text
C_TEXT2='#AAAAAA'    # --text-secondary
C_MUTED='#888888'    # --text-muted
C_OFF='#666666'      # --text-disabled: waiting, stopped
C_LINE='#444444'     # gray-600: the tree lines, the empty part of the bar
SPIN=(⣾ ⣽ ⣻ ⢿ ⡿ ⣟ ⣯ ⣷)   # the spinner: one frame per redraw
TEXT_WIDTH=46        # longer text lines wrap here: fits a 50-column phone terminal

# Colors and animation only on a real terminal; a pipe or a log file gets plain text.
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then UI_TTY=1; else UI_TTY=0; fi

# Escape code for a hex color (empty when there are no colors).
fg() {
  ((UI_TTY)) || return 0
  local h=${1#\#}
  printf '\e[38;2;%d;%d;%dm' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
}
E_ACCENT=$(fg "$C_ACCENT"); E_OK=$(fg "$C_OK"); E_WORK=$(fg "$C_WORK"); E_FAIL=$(fg "$C_FAIL")
E_TEXT=$(fg "$C_TEXT"); E_TEXT2=$(fg "$C_TEXT2"); E_MUTED=$(fg "$C_MUTED"); E_OFF=$(fg "$C_OFF"); E_LINE=$(fg "$C_LINE")
if ((UI_TTY)); then E_BOLD=$'\e[1m'; E_0=$'\e[0m'; else E_BOLD=''; E_0=''; fi

UI_FRAME_LINES=0   # lines of the live view on screen now; the next live view draws over it (restart = one view)

# "◆ Rustfield.eu · <what>"
ui_title() { printf '%s◆ %s%sRustfield%s%s.eu%s%s · %s%s' "$E_ACCENT" "$E_0" "$E_BOLD$E_TEXT" "$E_0" "$E_BOLD$E_ACCENT" "$E_0" "$E_TEXT2" "$1" "$E_0"; }

# The tree line in front of item <n> of <count>: ├─ for every item, ╰─ for the last one.
ui_branch() { if (($1 == $2)); then printf '%s╰─%s' "$E_LINE" "$E_0"; else printf '%s├─%s' "$E_LINE" "$E_0"; fi; }
ui_stem()   { printf '%s│%s' "$E_LINE" "$E_0"; }

# ONE TREE per command (user, 2026-10-26): one header, every line hangs on the tree, the result is the last branch ╰─.
# UI_TREE: 0 = no tree yet, 1 = open, 2 = closed by its last line. UI_SUB = 1: lines go into an indented block under
# a closed tree (install's clean-up after a failure).
UI_TREE=0 UI_SUB=0

ui_header() { ui_cursor_hide; ui_title "$1"; printf '\n%s\n' "$(ui_stem)"; UI_TREE=1 UI_FRAME_LINES=0; }
# What goes in front of a line: "├─ " in the open tree, "   " in a block under a closed tree, nothing without a tree.
ui_prefix() {
  if ((UI_SUB)); then printf '   '; elif ((UI_TREE == 1)); then printf '%s ' "$(ui_branch 1 2)"; fi
}
ui_gap()   { UI_FRAME_LINES=0; if ((UI_TREE == 1 && !UI_SUB)); then printf '%s\n' "$(ui_stem)"; else printf '\n'; fi; }
ui_step()  { UI_FRAME_LINES=0; printf '%s%s✓ %s%s\n' "$(ui_prefix)" "$E_OK" "$1" "$E_0"; }
ui_warn()  { UI_FRAME_LINES=0; printf '%s%s⚠ %s%s\n' "$(ui_prefix)" "$E_WORK" "$1" "$E_0"; }
# Text inside the open tree, under its items (explanations, warnings next to a question): <text> [color]
ui_line()  { UI_FRAME_LINES=0; printf '%s  %s%s%s\n' "$(ui_stem)" "${2:-$E_TEXT2}" "$1" "$E_0"; }

# The result: the last branch "╰─ ✓/✗ …" (it closes the tree), or a plain line when there is no tree.
ui_ok()   { ui_result "$E_OK✓" "$1"; }
ui_fail() { ui_result "$E_FAIL✗" "$1" >&2; }
ui_result() {
  UI_FRAME_LINES=0
  if ((UI_SUB)); then printf '   %s %s%s\n' "$1" "$2" "$E_0"
  elif ((UI_TREE == 1)); then printf '%s %s %s%s\n' "$(ui_branch 1 1)" "$1" "$2" "$E_0"; UI_TREE=2
  else printf '%s %s%s\n' "$1" "$2" "$E_0"; fi
}
# Gray details under the last line: inside the open tree "│  …", under a closed one "   …".
ui_detail() {
  UI_FRAME_LINES=0
  if ((UI_SUB)); then printf '     %s%s%s\n' "$E_MUTED" "$1" "$E_0" >&2
  elif ((UI_TREE == 1)); then printf '%s  %s%s%s\n' "$(ui_stem)" "$E_MUTED" "$1" "$E_0" >&2
  else printf '   %s%s%s\n' "$E_MUTED" "$1" "$E_0" >&2; fi
}

# A typed answer, inside the tree: <prompt with colors>. The answer is in UI_ANSWER. The cursor shows only while typing.
UI_ANSWER=''
ui_ask() {
  UI_FRAME_LINES=0
  if ((UI_TREE == 1)); then printf '%s  ' "$(ui_stem)"; fi
  printf '%s%s' "$1" "$E_0"
  ui_cursor_show
  read -r UI_ANSWER || UI_ANSWER=''
  ui_cursor_hide
}

# A bar: <done> <total> <width>, e.g. ━━━━━━━━━━━━━━━━━━━━ in rust (done) and gray (still to do).
ui_bar() {
  local done=$1 total=$2 width=$3 full=0 i out=''
  if ((total > 0)); then full=$((done * width / total)); fi
  for ((i = 0; i < width; i++)); do
    if ((i == full)); then out+=$E_LINE; fi
    out+='━'
  done
  printf '%s%s%s' "$E_ACCENT" "$out" "$E_0"
}

# Draws <text> over the view on screen now (if any). No blinking: it writes over the old view (never erases it
# first), clears only what is left at each line's end and below, and sends the whole frame in one write inside
# "synchronized output" (the terminal shows it at once). Not a terminal: just prints the text.
ui_redraw() {
  local view=$1 out=''
  local only_newlines=${view//[!$'\n']/}
  if ((UI_TTY)); then
    if ((UI_FRAME_LINES > 0)); then printf -v out '\e[%dF' "$UI_FRAME_LINES"; fi
    out+=${view//$'\n'/$'\e[K\n'}$'\e[K\n\e[J'
    printf '\e[?2026h%s\e[?2026l' "$out"
  else
    printf '%s\n' "$view"
  fi
  UI_FRAME_LINES=$((${#only_newlines} + 1))
}

# A spinner with a text on its own line, while this shell does some work (ui_wait is for work in the background).
# Rule (user, 2026-10-26): every wait longer than half a second shows a spinner that says what is happening.
UI_SPIN_PID=''
ui_spinner_start() {
  if ((!UI_TTY)) || [[ -n $UI_SPIN_PID ]]; then return 0; fi
  local text=$1 parent=$$
  local prefix
  prefix=$(ui_prefix)
  ui_cursor_hide
  (
    tick=0
    # Stops by itself if the script is gone (so it can never keep drawing after an error).
    while kill -0 "$parent" 2>/dev/null; do
      printf '\r%s%s%s %s%s\e[K' "$prefix" "$E_WORK" "${SPIN[tick % ${#SPIN[@]}]}" "$text" "$E_0"
      tick=$((tick + 1))
      sleep 0.12
    done
  ) &
  UI_SPIN_PID=$!
}
ui_spinner_stop() {
  if [[ -z $UI_SPIN_PID ]]; then return 0; fi
  kill "$UI_SPIN_PID" 2>/dev/null || true
  wait "$UI_SPIN_PID" 2>/dev/null || true
  UI_SPIN_PID=''
  printf '\r\e[K'
}

# The cursor is hidden for the whole run (no blinking between steps) and shows again at the end, also after an error
# or Ctrl+C (ui_exit). While the user types an answer it shows (ui_ask).
ui_cursor_hide() { if ((UI_TTY)); then printf '\e[?25l'; fi; }
ui_cursor_show() { if ((UI_TTY)); then printf '\e[?25h'; fi; }
ui_exit() { ui_spinner_stop; ui_cursor_show; }
trap ui_exit EXIT

# A meter: <percent> <width>. Rust up to 80 %, yellow above 80 %, red above 90 % (a filling disk catches the eye).
ui_meter() {
  local pct=$1 width=$2 full color=$E_ACCENT i out=''
  if ((pct > 90)); then color=$E_FAIL; elif ((pct > 80)); then color=$E_WORK; fi
  full=$(((pct * width + 50) / 100))
  if ((full > width)); then full=$width; fi
  for ((i = 0; i < width; i++)); do
    if ((i == full)); then out+=$E_LINE; fi
    out+='━'
  done
  printf '%s%s%s' "$color" "$out" "$E_0"
}

# Bytes in human words: "700 KB" → "1 MB", "16.9 MB" → "17 MB", "1073741824" → "1 GB", "4004536 KB" → "3.8 GB".
ui_bytes() {
  awk -v b="$1" 'BEGIN {
    g = b / 1073741824
    if (g >= 1) { if (g == int(g)) printf "%d GB", g; else printf "%.1f GB", g }
    else { m = int(b / 1048576 + 0.5); if (m < 1 && b > 0) m = 1; printf "%d MB", m }
  }'
}

# A file size in human words: "844 B", "1.7 KB", "12 MB", "1.2 GB".
ui_size() {
  awk -v b="$1" 'BEGIN {
    if (b < 1024) printf "%d B", b
    else if (b < 1048576) printf "%.1f KB", b / 1024
    else if (b < 1073741824) printf "%.0f MB", b / 1048576
    else printf "%.1f GB", b / 1073741824
  }'
}

# One item on the tree: "├─ <label>  <value>"; a long value wraps under its own column (never mid-word, never past
# ~58 characters, so it fits a phone). <label> <value>
ui_item() {
  local first=1 piece
  while IFS= read -r piece; do
    if ((first)); then
      printf '%s %s%-10s%s %s%s%s\n' "$(ui_branch 1 2)" "$E_TEXT2" "$1" "$E_0" "$E_TEXT" "${piece% }" "$E_0"
      first=0
    else
      printf '%s%13s %s%s%s\n' "$(ui_stem)" '' "$E_TEXT" "${piece% }" "$E_0"
    fi
  done < <(printf '%s\n' "$2" | fold -s -w 44)
  UI_FRAME_LINES=0
}

# "1 volume", "2 volumes": <number> <word>
ui_count() { if (($1 == 1)); then printf '1 %s' "$2"; else printf '%d %ss' "$1" "$2"; fi; }

# A time span in seconds, short: "40 s", "12 min", "5 h", "3 d". With "long": "1 d 21 h", "5 h 3 min".
ui_age() {
  local s=$1 mode=${2:-short}
  if ((s < 60)); then printf '%d s' "$s"
  elif ((s < 3600)); then printf '%d min' $((s / 60))
  elif ((s < 86400)); then
    if [[ $mode == long ]]; then printf '%d h %d min' $((s / 3600)) $((s % 3600 / 60)); else printf '%d h' $((s / 3600)); fi
  else
    if [[ $mode == long ]]; then printf '%d d %d h' $((s / 86400)) $((s % 86400 / 3600)); else printf '%d d' $((s / 86400)); fi
  fi
}

# A spinner with a text on one line while process <pid> runs; the line is gone afterwards. <pid> <text> [keep]
# With "keep" the line stays until the next ui_redraw writes over it (no empty moment in between).
ui_wait() {
  local pid=$1 text=$2 keep=${3:-} tick=0 prefix
  if ((!UI_TTY)); then return 0; fi
  prefix=$(ui_prefix)
  ui_cursor_hide
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r%s%s%s %s%s\e[K' "$prefix" "$E_WORK" "${SPIN[tick % ${#SPIN[@]}]}" "$text" "$E_0"
    tick=$((tick + 1))
    sleep 0.12
  done
  if [[ -n $keep ]]; then
    printf '\n'
    UI_FRAME_LINES=1
  else
    printf '\r\e[K'
  fi
}

# One action in the timeline: a spinner with <working text> while <command...> runs, then "├─ ✓ <done text>", or
# "├─ ✗ <done text>: failed" with the command's last lines. Returns 1 when it failed.
ui_do() {
  local working=$1 done=$2 log pid
  shift 2
  log=$(mktemp)
  "$@" >"$log" 2>&1 &
  pid=$!
  ui_wait "$pid" "$working"
  if wait "$pid"; then
    ui_step "$done"
    rm -f "$log"
    return 0
  fi
  printf '%s%s✗ %s: failed%s\n' "$(ui_prefix)" "$E_FAIL" "$done" "$E_0"
  grep -v '^[[:space:]]*$' "$log" | tail -n 3 | while IFS= read -r line; do ui_detail "$line"; done
  rm -f "$log"
  return 1
}

# The header of a command: "◆ Rustfield.eu · <node name> · <command>" (TITLE, set by the script). Once per command.
# shellcheck disable=SC2153 # TITLE is set by the script (the command name)
begin() { ui_header "$(node_name) · $TITLE"; }

# ── Running the steps ──────────────────────────────────────────────────────────────────────────────────────────
run_steps() {
  local step
  for step in "$@"; do
    if ! declare -F "$step" >/dev/null; then
      ui_fail "Unknown step \"$step\"."
      ui_detail "A mistake in the script's STEPS list."
      exit 1
    fi
    "$step"
  done
}

need_docker() {
  if ! command -v docker >/dev/null; then
    ui_fail "Docker is not installed."
    ui_detail "./rustfield-node-install installs it."
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    ui_fail "Docker is not running."
    ui_detail "(Or this user may not use Docker.)"
    ui_detail "Start it as root: systemctl start docker"
    exit 1
  fi
}

# Docker's official apt steps (docs.docker.com/engine/install/ubuntu, checked 2026-10-25), for Ubuntu and Debian.
docker_install() {
  local os
  # shellcheck source=/dev/null # a system file (Ubuntu/Debian name and version)
  os=$(. /etc/os-release && echo "$ID")
  if [[ $os != ubuntu && $os != debian ]]; then echo "Only Ubuntu and Debian: install Docker by hand, then run me again."; return 1; fi
  apt-get update -q
  apt-get install -y -q ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/$os/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  # shellcheck source=/dev/null # a system file (Ubuntu/Debian name and version)
  cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/$os
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
  apt-get update -q
  apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
}

# ── The node: names and places ─────────────────────────────────────────────────────────────────────────────────
# Wings (Pterodactyl's worker) runs in Docker, but it starts the game servers on THIS server's Docker, so its folders
# must have the same path inside and outside its box. These are Wings's standard folders.
WINGS_CONFIG=/etc/pterodactyl/config.yml
WINGS_FOLDERS=(/etc/pterodactyl /var/lib/pterodactyl /var/log/pterodactyl /tmp/pterodactyl /run/wings)
GAME_DATA=/var/lib/pterodactyl      # the game servers' files (maps, player data)
GAME_LABEL=Service=Pterodactyl      # Wings puts this label on every game server box
GAME_NETWORK=pterodactyl_nw         # Wings makes this network for the game servers
LOG_ROTATE=/etc/logrotate.d/$PROJECT
# The join code holds these keys (made by `rustfield node add` on the main server).
JOIN_KEYS=(NODE_NAME NODE_ADDRESS PANEL_URL WINGS_UUID WINGS_TOKEN_ID WINGS_TOKEN TUNNEL_TOKEN)

# The value of <key> in this node's .env (made by install from the join code; empty if there is none).
env_value() {
  grep -E "^$1=" "$ROOT/.env" 2>/dev/null | tail -n 1 | cut -d= -f2- || true
}
node_name() { local n; n=$(env_value NODE_NAME); printf '%s' "${n:-node}"; }

need_root() {
  if ((EUID != 0)); then ui_fail "Run it as root."; exit 1; fi
}

# Install and delete run only as ./<script> from the project folder (no short command for them, on purpose).
need_project_folder() {
  if [[ $(pwd -P) != "$ROOT" ]]; then
    ui_fail "Run it from the project folder: cd $ROOT && ./$(basename "$0")"
    exit 1
  fi
}

need_installed() {
  if [[ ! -f $ROOT/.env || ! -f $WINGS_CONFIG ]]; then
    ui_fail "This node is not installed."
    ui_detail "Get the install line from the main server: rustfield node add"
    exit 1
  fi
}

# For commands that take nothing after them.
no_args() {
  if ((${#ARGS[@]} > 0)); then ui_fail "\"$CMD\" takes nothing after it."; exit 1; fi
}

# Does Wings answer through the tunnel at the node's address? Wings says "401" (no key) to a visit without a key:
# that is the proof that the whole road works (Cloudflare → tunnel → Wings).
node_reachable() {
  local code
  code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "https://$(env_value NODE_ADDRESS)/api/system" || true)
  [[ $code == 401 ]]
}

# ── Steps: install (./rustfield-node-install <join code>) ──────────────────────────────────────────────────────
# Turns this server into a game server node: Docker if missing, the firewall, the settings from the join code,
# Wings + the tunnel, then checks that the panel's road to Wings works. Safe to run again with the same code.
declare -A JOIN=()

install_begin() { ui_header "install"; }

# The short command is the "installed" mark: if it is there, install changes nothing.
install_check_installed() {
  local shortcut="/usr/local/bin/$PROJECT"
  if [[ -L $shortcut && $(readlink -f "$shortcut") == "$ROOT/$PROJECT" ]]; then
    ui_ok "Already installed. Nothing was changed."
    ui_detail "See it: $PROJECT status"
    exit 0
  fi
}

# Reads the join code: base64 of "KEY=value" lines. Only known keys and plain characters are taken (it is pasted
# text, so nothing in it may ever run as a command).
install_read_code() {
  local code=${ARGS[0]:-} text line key value
  if [[ -z $code || ${#ARGS[@]} -gt 1 ]]; then
    ui_fail "The join code is missing."
    ui_detail "Copy the whole install line from the main server (rustfield node add)."
    exit 1
  fi
  text=$(printf '%s' "$code" | base64 -d 2>/dev/null) || text=''
  # Split at the FIRST "=" only: keys made of base64 can end with "=".
  while IFS= read -r line; do
    key=${line%%=*} value=${line#*=}
    if [[ " ${JOIN_KEYS[*]} " == *" $key "* && $value =~ ^[A-Za-z0-9._:/+=-]+$ ]]; then JOIN[$key]=$value; fi
  done <<<"$text"
  for key in "${JOIN_KEYS[@]}"; do
    if [[ -z ${JOIN[$key]:-} ]]; then
      ui_fail "The join code is broken (no $key)."
      ui_detail "Copy the whole line again, from start to end."
      exit 1
    fi
  done
  ui_step "Join code: node ${JOIN[NODE_NAME]} (${JOIN[NODE_ADDRESS]})"
}

# Docker: kept if it works; started if installed but stopped; installed from Docker's official source if missing.
install_docker() {
  if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
    ui_step "Docker $(docker version -f '{{.Server.Version}}')"
    return
  fi
  if command -v docker >/dev/null; then
    ui_do "Starting Docker…" "Docker started" systemctl start docker || exit 1
    return
  fi
  ui_do "Installing Docker (Docker's official source)…" "Docker installed" docker_install || exit 1
}

# The firewall (ufw): on, only SSH open. The game ports need no rule: Docker opens a game server's ports itself,
# only while that game server exists (agreed with the user, 2026-10-26). Wings has no open port: the tunnel calls out.
# SSH stays open on every port sshd uses (plus 22), so this never locks anyone out.
install_firewall() {
  local ports port
  if ! command -v ufw >/dev/null; then
    ui_do "Installing the firewall (ufw)…" "Firewall installed" apt-get install -y -q ufw || exit 1
  fi
  ports=$({ sshd -T 2>/dev/null | awk '$1 == "port" {print $2}'; echo 22; } | sort -un)
  for port in $ports; do ufw allow "$port/tcp" >/dev/null; done
  ufw --force enable >/dev/null
  ui_step "Firewall on: only SSH ($(paste -sd, <<<"$ports" | sed 's/,/, /g')) is open"
}

# Writes the node's settings: .env (the tunnel key; never in git), Wings's settings file, and the log limit for
# Wings's own log file. Only root may read the two files with keys.
install_settings() {
  umask 077
  cat >"$ROOT/.env" <<EOT
# This node's settings. Made by ./rustfield-node-install from the join code. NEVER in git (the repo is public).
NODE_NAME=${JOIN[NODE_NAME]}
NODE_ADDRESS=${JOIN[NODE_ADDRESS]}
TUNNEL_TOKEN=${JOIN[TUNNEL_TOKEN]}
EOT
  mkdir -p "${WINGS_FOLDERS[@]}"
  cat >"$WINGS_CONFIG" <<EOT
# Wings settings for this node. Made by ./rustfield-node-install from the join code. Wings adds its defaults.
debug: false
uuid: ${JOIN[WINGS_UUID]}
token_id: ${JOIN[WINGS_TOKEN_ID]}
token: ${JOIN[WINGS_TOKEN]}
# Wings listens only inside Docker; the tunnel brings the panel's visits to it (https ends at Cloudflare).
api:
  host: 0.0.0.0
  port: 8080
  ssl:
    enabled: false
  upload_limit: 100
system:
  # Wings's own log rotation would only work inside its box: $LOG_ROTATE does it on the server.
  enable_log_rotate: false
docker:
  # The game servers' network. Its own address range, so it never meets the one Docker gives our compose network.
  network:
    interface: 172.30.0.1
    interfaces:
      v4:
        subnet: 172.30.0.0/16
        gateway: 172.30.0.1
remote: ${JOIN[PANEL_URL]}
EOT
  umask 022
  # Order, not server size: only the newest 30 MB of Wings's log file are kept (like every container's log).
  cat >"$LOG_ROTATE" <<EOT
# Made by ./rustfield-node-install (repo rustfield-node). Removed by ./rustfield-node-delete.
/var/log/pterodactyl/*.log {
    size 10M
    rotate 2
    copytruncate
    missingok
    notifempty
}
EOT
  ui_step "Settings written (only root can read them)"
}

install_images() {
  ui_do "Downloading Wings and the tunnel…" "Images downloaded" docker compose --progress quiet pull || exit 1
}

install_start() {
  ui_do "Starting Wings and the tunnel…" "Wings and the tunnel started" \
    docker compose --progress quiet up -d --wait --wait-timeout 120 || exit 1
}

# The proof: the panel's road to Wings works. A new address can take a short moment to be known everywhere.
install_connected() {
  local i
  ui_spinner_start "Checking the road: Cloudflare → tunnel → Wings…"
  for ((i = 0; i < 30; i++)); do
    if node_reachable; then
      ui_spinner_stop
      ui_step "Connected: $(env_value NODE_ADDRESS) answers"
      return
    fi
    sleep 3
  done
  ui_spinner_stop
  ui_fail "Wings does not answer at $(env_value NODE_ADDRESS)."
  ui_detail "Wait a minute, then: ./rustfield-node-install again (safe)."
  exit 1
}

# The LAST step: the short command. From now on install says "Already installed".
install_shortcut() {
  ln -sfn "$ROOT/$PROJECT" "/usr/local/bin/$PROJECT"
  ui_step "Short command: $PROJECT (works in any folder)"
  ui_ok "Node $(node_name) is ready. The panel can use it now."
}

# ── Steps: start, stop, restart, update ───────────────────────────────────────────────────────────────────────
# Stopping Wings does NOT stop the game servers: they are their own boxes. The panel only cannot reach them meanwhile.
start_node()   { ui_do "Starting…" "Wings and the tunnel started" docker compose --progress quiet up -d --wait --wait-timeout 120 || exit 1; done_line; }
stop_node()    { ui_do "Stopping…" "Wings and the tunnel stopped" docker compose --progress quiet stop || exit 1; ui_ok "Stopped. The game servers keep running."; }
restart_node() { ui_do "Restarting…" "Wings and the tunnel restarted" docker compose --progress quiet restart || exit 1; done_line; }

# The newest code of this repo, then the image versions it names.
update_node() {
  ui_do "Getting the newest code…" "Code: $(git -C "$ROOT" log -1 --format=%h)" git -C "$ROOT" pull --ff-only -q || exit 1
  # The line above showed the old commit if the pull brought a new one: show the real one.
  ui_line "now at $(git -C "$ROOT" log -1 --format='%h · %s' | cut -c1-44)"
  ui_do "Downloading images…" "Images up to date" docker compose --progress quiet pull || exit 1
  ui_do "Starting the new versions…" "Running the new versions" \
    docker compose --progress quiet up -d --wait --wait-timeout 120 || exit 1
  done_line
}

done_line() {
  if node_reachable; then ui_ok "Done. The panel can reach this node."
  else ui_ok "Done."; ui_detail "Not reachable through the tunnel yet: see $PROJECT status"; fi
}

# ── Steps: status ──────────────────────────────────────────────────────────────────────────────────────────────
# One screen: the node (Wings, tunnel, the road from the panel), its game servers, and the server (memory, CPU, disk).
show_status() {
  local wings tunnel road games_up games_all t1 t2 cpu mem_total mem_used disk_used disk_size
  ui_spinner_start "Measuring…"
  t1=$(cpu_sample)
  wings=$(docker inspect -f '{{.State.Status}}' "$PROJECT-wings" 2>/dev/null || echo missing)
  tunnel=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
    "$PROJECT-cloudflared" 2>/dev/null || echo missing)
  if node_reachable; then road=1; else road=0; fi
  games_all=$(docker ps -aq --filter "label=$GAME_LABEL" --filter label=ContainerType=server_process | wc -l)
  games_up=$(docker ps -q --filter "label=$GAME_LABEL" --filter label=ContainerType=server_process | wc -l)
  sleep 0.5
  t2=$(cpu_sample)
  cpu=$(cpu_percent "$t1" "$t2")
  mem_total=$(awk '/^MemTotal:/ {print $2 * 1024}' /proc/meminfo)
  mem_used=$((mem_total - $(awk '/^MemAvailable:/ {print $2 * 1024}' /proc/meminfo)))
  read -r disk_used disk_size < <(df -B1 --output=used,size "$(dirname "$GAME_DATA")" | tail -n 1)
  ui_spinner_stop

  ui_title "$(node_name) · status"; printf '\n%s\n' "$(ui_stem)"
  printf '%s %sNode%s\n' "$(ui_branch 1 2)" "$E_BOLD$E_TEXT" "$E_0"
  status_state 1 Address "$E_TEXT" "$(env_value NODE_ADDRESS)"
  status_state 2 Wings "$(state_color "$wings" running)" "$wings · $(docker inspect -f '{{.Config.Image}}' \
    "$PROJECT-wings" 2>/dev/null | sed 's/.*://')"
  status_state 3 Tunnel "$(state_color "$tunnel" healthy)" "$tunnel"
  if ((road)); then status_state 4 Panel "$E_OK" "can reach Wings"; else status_state 4 Panel "$E_FAIL" "cannot reach Wings"; fi
  printf '%s\n' "$(ui_stem)"
  printf '%s %sGames%s   %s%d running · %d stopped%s\n' "$(ui_branch 1 2)" "$E_BOLD$E_TEXT" "$E_0" "$E_TEXT" \
    "$games_up" $((games_all - games_up)) "$E_0"
  printf '%s\n' "$(ui_stem)"
  printf '%s %sServer%s\n' "$(ui_branch 1 2)" "$E_BOLD$E_TEXT" "$E_0"
  status_meter 1 Memory $((mem_used * 100 / mem_total)) "$(ui_bytes "$mem_used") / $(ui_bytes "$mem_total")"
  status_meter 2 CPU "$cpu" "$cpu % · $(nproc) cores"
  status_meter 3 Disk $((disk_used * 100 / disk_size)) "$(ui_bytes "$disk_used") / $(ui_bytes "$disk_size")"
  printf '%s  %s %s%-6s%s %s%s%s\n' "$(ui_stem)" "$(ui_branch 4 4)" "$E_TEXT2" Up "$E_0" "$E_TEXT" \
    "$(ui_age "$(awk '{print int($1)}' /proc/uptime)" long)" "$E_0"
  printf '%s\n' "$(ui_stem)"
  if [[ $wings == running && $tunnel == healthy ]] && ((road)); then UI_TREE=1; ui_ok "Everything works"
  else UI_TREE=1; ui_fail "Something is wrong (see above)"; fi
}

# One node line: <n> <label> <color> <text>
status_state() {
  printf '%s  %s %s%-7s%s %s● %s%s\n' "$(ui_stem)" "$(ui_branch "$1" 4)" "$E_TEXT2" "$2" "$E_0" "$3" "$4" "$E_0"
}
# Green for the good word, red for anything else: <word> <good word>
state_color() { if [[ $1 == "$2" ]]; then printf '%s' "$E_OK"; else printf '%s' "$E_FAIL"; fi; }

# One server line with a meter: <n> <label> <percent> <text after the meter>
status_meter() {
  printf '%s  %s %s%-6s%s %s  %s%s%s\n' "$(ui_stem)" "$(ui_branch "$1" 4)" "$E_TEXT2" "$2" "$E_0" "$(ui_meter "$3" 14)" \
    "$E_TEXT" "$4" "$E_0"
}

# CPU time counters "<total> <idle>" from /proc/stat; cpu_percent turns two of them into a busy percent.
cpu_sample() { awk '/^cpu / {print $2 + $3 + $4 + $5 + $6 + $7 + $8 + $9, $5 + $6}' /proc/stat; }
cpu_percent() {
  local t1 i1 t2 i2
  read -r t1 i1 <<<"$1"
  read -r t2 i2 <<<"$2"
  if ((t2 > t1)); then echo $((100 * ((t2 - t1) - (i2 - i1)) / (t2 - t1))); else echo 0; fi
}

show_help() {
  ui_title "$(node_name) · help"; printf '\n%s\n' "$(ui_stem)"
  local lines=(
    "status|the node, its game servers, the server"
    "start|start Wings and the tunnel"
    "stop|stop them (game servers keep running)"
    "restart|restart Wings and the tunnel"
    "update|newest code + image versions"
  )
  local line
  for line in "${lines[@]}"; do ui_item "${line%%|*}" "${line#*|}"; done
  ui_line "Remove the node: first rustfield node delete on" "$E_MUTED"
  ui_line "the main server, then ./rustfield-node-delete here." "$E_MUTED"
  printf '%s\n' "$(ui_stem)"
  UI_TREE=1; ui_ok "$PROJECT <command>"
}

# ── Steps: delete (./rustfield-node-delete) ────────────────────────────────────────────────────────────────────
# Wipes the node: every game server and its files, Wings, the tunnel, their images, the settings, the short command
# and this folder (user, 2026-10-27: no backup first). Docker and the firewall stay. Run it after
# `rustfield node delete` on the main server (that removes the node from the panel and Cloudflare).
D_GAMES=() D_OURS=() D_IMAGES=() D_NETWORKS=() D_FOLDERS=() D_FILES=() D_BYTES=0 D_FAILED=0

delete_begin() { ui_header "$(node_name) · delete"; }

delete_scan() {
  local f
  ui_spinner_start "Looking at what is installed…"
  D_GAMES=() D_OURS=() D_IMAGES=() D_NETWORKS=() D_FOLDERS=() D_FILES=() D_BYTES=0
  if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
    mapfile -t D_GAMES < <(docker ps -aq --filter "label=$GAME_LABEL")
    mapfile -t D_OURS < <(docker ps -aq --filter "label=com.docker.compose.project=$PROJECT")
    # Images: the ones the game servers and our two boxes use (read before the boxes are gone).
    if ((${#D_GAMES[@]} + ${#D_OURS[@]} > 0)); then
      mapfile -t D_IMAGES < <(docker inspect -f '{{.Config.Image}}' "${D_GAMES[@]}" "${D_OURS[@]}" | sort -u)
    fi
    mapfile -t D_NETWORKS < <({ docker network ls -q --filter "label=com.docker.compose.project=$PROJECT"
      docker network ls -q --filter "name=^${GAME_NETWORK}$"; } | sort -u)
  fi
  for f in "${WINGS_FOLDERS[@]}"; do if [[ -e $f ]]; then D_FOLDERS+=("$f"); fi; done
  if [[ -d $GAME_DATA ]]; then D_BYTES=$(du -sb "$GAME_DATA" 2>/dev/null | cut -f1 || echo 0); fi
  for f in "$LOG_ROTATE" "/usr/local/bin/$PROJECT"; do if [[ -e $f || -L $f ]]; then D_FILES+=("$f"); fi; done
  ui_spinner_stop
}

delete_show() {
  ui_item Games "$(ui_count "${#D_GAMES[@]}" "game server box")"
  ui_item Files "$(ui_size "$D_BYTES") of game files ($GAME_DATA)"
  ui_item Node "Wings + tunnel: $(ui_count "${#D_OURS[@]}" box), $(ui_count "${#D_IMAGES[@]}" image)"
  ui_item Settings "${D_FOLDERS[*]:-none}"
  ui_item Folder "$ROOT (the original is on GitHub)"
  ui_line "Stays: Docker, the firewall (only SSH open)" "$E_MUTED"
  ui_gap
  if ((${#D_GAMES[@]})) || ((D_BYTES > 0)); then
    ui_line "⚠ ALL GAME SERVERS here are DELETED. No backup." "$E_WORK"
  fi
}

# The typed question: the node's name, so a node is never wiped by a wrong key press.
delete_ask() {
  local name
  name=$(node_name)
  if [[ ! -t 0 ]]; then ui_fail "delete asks a question: run it in a terminal."; exit 1; fi
  ui_ask "${E_TEXT}Type \"${E_ACCENT}$name${E_TEXT}\" to delete (anything else stops): "
  if [[ $UI_ANSWER != "$name" ]]; then ui_fail "Stopped. Nothing was deleted."; exit 1; fi
  ui_gap
}

# Runs one removal with a spinner. A failure is shown, and the other removals still run.
delete_do() {
  local done=$1
  shift
  ui_do "${done%% *}…" "$done" "$@" || D_FAILED=1
}

delete_games() {
  if ((${#D_GAMES[@]})); then delete_do "Game servers removed (${#D_GAMES[@]})" docker rm -f -v "${D_GAMES[@]}"; fi
}
delete_ours() {
  if ((${#D_OURS[@]})); then delete_do "Wings and the tunnel removed" docker rm -f -v "${D_OURS[@]}"; fi
}
delete_networks() {
  if ((${#D_NETWORKS[@]})); then delete_do "Networks removed" docker network rm "${D_NETWORKS[@]}"; fi
}
# Images: one by one; one that something else on this server still uses is kept.
delete_images() {
  local image gone=0
  for image in "${D_IMAGES[@]}"; do
    if [[ -z $(docker ps -aq --filter "ancestor=$image") ]] && docker rmi "$image" >/dev/null 2>&1; then gone=$((gone + 1)); fi
  done
  if ((${#D_IMAGES[@]})); then ui_step "Images removed ($gone)"; fi
}
delete_files() {
  if ((${#D_FOLDERS[@]})); then delete_do "Game files and settings removed" rm -rf "${D_FOLDERS[@]}"; fi
  if ((${#D_FILES[@]})); then rm -f "${D_FILES[@]}"; ui_step "Removed: short command, log limit"; fi
}

# The project folder, LAST and only when everything else worked (after a failure the folder is needed to run delete
# again). The running script stays readable after its file is gone (Linux keeps an open file until it is closed).
delete_folder() {
  if ((D_FAILED)); then return 0; fi
  if [[ ! -f $ROOT/rustfield-node-delete || $ROOT == / || $ROOT == "$HOME" ]]; then
    ui_fail "The project folder looks wrong ($ROOT): it was not removed."
    D_FAILED=1
    return 0
  fi
  cd /
  delete_do "Folder removed: $ROOT" rm -rf "${ROOT:?}"
}

delete_done() {
  if ((D_FAILED)); then
    ui_fail "Not everything could be removed. Run ./rustfield-node-delete again."
    exit 1
  fi
  ui_ok "Done: nothing of the node is left on this server."
  ui_detail "Your terminal was in the removed folder: type  cd /root"
}
