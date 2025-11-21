#!/bin/bash
# ===============================================================
# maildir-git-backup-all.sh – finale, config-basierte Version
# Läuft als vmail (oder jeder andere User mit eigenem Config)
# ===============================================================

set -euo pipefail

# ——— Wer bin ich? (damit mehrere User eigene Config haben können) ———
RUN_USER="${SUDO_USER:-$(whoami)}"
if [ "$RUN_USER" = "root" ] && [ -n "${SUDO_USER:-}" ]; then
  RUN_USER="$SUDO_USER"
fi

# ——— Config finden – zuerst im Home des laufenden Users ———
CONFIG_PATH=""
for dir in "/home/$RUN_USER/.config" "$HOME/.config" "/etc/maildir-git-backup-all.conf"; do
  if [ -f "$dir/maildir-git-backup-all.conf" ]; then
    CONFIG_PATH="$dir/maildir-git-backup-all.conf"
    break
  fi
done

if [ -z "$CONFIG_PATH" ]; then
  echo "FEHLER: Keine Config gefunden für User $RUN_USER" >&2
  exit 1
fi

echo "Lade Config: $CONFIG_PATH"
source "$CONFIG_PATH"

# ——— Default-Werte falls nicht in Config ———
: ${BASE:="/mnt/eichert2/vmail"}
: ${GIT_SERVER:="git@raspberry-intra"}
: ${LOG:="/var/log/maildir-git-backup-all.log"}
: ${LOCK:="/var/run/maildir-git-backup-all.lock"}
: ${FORCE_PUSH_EVERY:=24}

# ——— Lock (pro Config, damit mehrere Instanzen parallel können) ———
exec 200>"$LOCK"
flock -n 200 || { echo "$(date) – Backup läuft bereits" >> "$LOG"; exit 0; }
trap "rm -f '$LOCK'" EXIT

echo "=========================================================" >> "$LOG"
echo "=== $(date '+%Y-%m-%d %H:%M:%S') – Backup-Start als $RUN_USER ===" >> "$LOG"

# Zähler für force-push
COUNTER_FILE="$HOME/.cache/maildir-git-backup-counter"
mkdir -p "$(dirname "$COUNTER_FILE")"
if [ -f "$COUNTER_FILE" ]; then
  COUNT=$(cat "$COUNTER_FILE")
else
  COUNT=0
fi
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

find "$BASE" -mindepth 2 -maxdepth 2 -type d -print0 | while IFS= read -r -d '' MAILDIR; do
  DOMAIN=$(basename "$(dirname "$MAILDIR")")
  USER=$(basename "$MAILDIR")
  REPO_NAME="${DOMAIN}-${USER@Q}"  # @Q = quoted für seltsame Namen
  REMOTE="git@$GIT_SERVER:mail/$REPO_NAME.git"

  echo "→ $DOMAIN / $USER ($REPO_NAME)" >> "$LOG"

  cd "$MAILDIR"

  # Repo initialisieren falls nötig
  if [ ! -d ".git" ]; then
    echo "   Initialisiere Repo: $REPO_NAME" >> "$LOG"
    git init -q
    git checkout -b main 2>/dev/null || true
    echo -e "*.tmp\ncourier*\n*.lock\n*.log\n.*.swp" > .gitignore
    git add .gitignore
    git commit -q -m "Initial commit" || true
    git remote add origin "$REMOTE" 2>/dev oder true
  fi

  NEW=$(git ls-files --others --exclude-standard | wc -l)
  MOD=$(git diff --name-only HEAD 2>/dev/null | wc -l)
  TOTAL=$((NEW + MOD))

  [ $TOTAL -eq 0 ] && { echo "   keine Änderungen" >> "$LOG"; continue; }

  git add -A .
  NOW=$(date '+%Y-%m-%d %H:%M')
  git commit -q -m "Auto-Backup $NOW – +$NEW neue, $MOD geändert"

  PUSH_CMD="git push -q origin main"
  [ $((COUNT % FORCE_PUSH_EVERY)) -eq 0 ] && PUSH_CMD="git push -q --force-with-lease origin main"

  if $PUSH_CMD 2>>"$LOG"; then
    echo "   $TOTAL Dateien gesichert & gepusht" >> "$LOG"
  else
    echo "   Push fehlschlag (Repo wird beim nächsten Mal angelegt)" >> "$LOG"
  fi

  git gc --quiet --auto 2>/dev/null
done

echo "=== Backup-Run fertig – $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG"
echo "" >> "$LOG"
