# Config anlegen
sudo -u vmail mkdir -p /home/vmail/.config
sudo -u vmail tee /home/vmail/.config/maildir-git-backup-all.conf > /dev/null <<'EOF'
BASE="/mnt/eichert2/vmail"
GIT_SERVER="git@raspberry-intra"
LOG="/var/log/maildir-git-backup-all.log"
LOCK="/var/run/maildir-git-backup-all.lock"
FORCE_PUSH_EVERY=24
EOF

# Script installieren
sudo tee /usr/local/bin/maildir-git-backup-all.sh <(cat das_obige_script)
sudo chmod +x /usr/local/bin/maildir-git-backup-all.sh

# Crontab als vmail
sudo -u vmail crontab -e
# → 7 * * * * /usr/local/bin/maildir-git-backup-all.sh >/dev/null 2>&1