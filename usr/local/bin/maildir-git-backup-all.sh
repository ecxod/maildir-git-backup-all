#!/bin/bash
# ===============================================================
# Vollautomatisches Backup ALLER Maildirs → eigene Git-Repos
# Läuft stündlich als User vmail
# ===============================================================
BASE="/mnt/eichert2/vmail"
GIT_SERVER="git@raspberry-intra"           # SSH-Hostalias deines Raspberry Pi
LOG="/var/log/maildir-git-backup-all.log"

# Lock für das gesamte Script
LOCK="/var/run/maildir-git-backup-all.lock"
exec 200>"$LOCK"
flock -n 200 || exit 0
trap "rm -f $LOCK" EXIT

echo "=== $(date '+%Y-%m-%d %H:%M:%S') – Start Backup-Run ===" >> "$LOG"

# Rekursiv alle Maildirs finden (nur die eigentlichen Benutzerordner)
find "$BASE" -mindepth 2 -maxdepth 2 -type d | while read MAILDIR; do
  DOMAIN=$(basename "$(dirname "$MAILDIR")")
  USER=$(basename "$MAILDIR")
  REPO_NAME="${DOMAIN}-${USER}"                    # z. B. example.com-maxmustermann
  REPO_PATH="$MAILDIR"
  REMOTE="git@$GIT_SERVER:mail/$REPO_NAME.git"

  echo "Bearbeite: $DOMAIN / $USER → $REPO_NAME" >> "$LOG"

  cd "$REPO_PATH" || continue

  # ---- Repo existiert noch nicht lokal? → initialisieren ----
  if [ ! -d ".git" ]; then
    echo "   → Initialisiere neues Repo für $REPO_NAME" >> "$LOG"
    git init -q
    git checkout -b main 2>/dev/null || true
    echo -e "*.tmp\ncourier*\n*.lock\n*.log" > .gitignore
    git add .gitignore
    git commit -q -m "Initial commit + .gitignore" 2>/dev/null || true
    # Remote setzen (falls noch nicht da)
    git remote | grep -q origin || git remote add origin "$REMOTE"
  fi

  # ---- Änderungen prüfen ----
  NEW=$(git ls-files --others --exclude-standard | wc -l)
  MOD=$(git diff --name-only HEAD 2>/dev/null | wc -l)
  TOTAL=$((NEW + MOD))

  if [ $TOTAL -eq 0 ]; then
    echo "   → $REPO_NAME: keine Änderungen" >> "$LOG"
    continue
  fi

  # ---- Commit ----
  git add -A .
  NOW=$(date '+%Y-%m-%d %H:%M')
  git commit -q -m "Auto-Backup $NOW – +$NEW neue, $MOD geändert"

  # ---- Push (erstellt das Remote-Repo automatisch, siehe Punkt 2) ----
  if git push -q origin main 2>>"$LOG"; then
    echo "   → $REPO_NAME: $TOTAL Dateien gesichert & gepusht" >> "$LOG"
  else
    echo "   → $REPO_NAME: Push fehlgeschlagen (erstes Mal? → Repo wird gleich angelegt)" >> "$LOG"
  fi

  # Aufräumen
  git gc --quiet --auto 2>/dev/null
done

echo "=== Backup-Run fertig $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG"
echo "" >> "$LOG"