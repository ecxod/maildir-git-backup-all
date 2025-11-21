# Maildir Backup System (git Methode)

BASE - Verzeichnis wo sich die Emails befinden (Maildir Verzeichnis des Postfix Servers)
GIT_SERVER - der Git-Server auf den wir den Backup pushen 
LOG - Log Datei unseres Programmes
LOCK - Lock Datei damit wir mehrere Instanzen fahren können

Wir nutzen einen popligen Raspberry PI als Git Server

## Config anlegen
```sh
sudo -u vmail mkdir -p /home/vmail/.config
sudo -u vmail tee /home/vmail/.config/maildir-git-backup-all.conf > /dev/null <<'EOF'
BASE="/var/vmail"
GIT_SERVER="git@raspberry-intra"
LOG="/var/log/maildir-git-backup-all.log"
LOCK="/var/run/maildir-git-backup-all.lock"
FORCE_PUSH_EVERY=24
EOF
```

## Auf dem Raspberry Pi (Git-Server) – automatisches Anlegen von Bare-Repos

```sh
# Einmalig auf dem Raspberry (als dein git-User, z. B. git)
sudo mkdir -p /var/git/mail
sudo chown git:git /var/git/mail

# Globalen post-receive Hook, der neue Repos automatisch anlegt
sudo tee /var/git/mail/.git/hooks/post-receive <<'EOF'
#!/bin/sh
# Automatisches Anlegen von neuen Bare-Repos
while read oldrev newrev refname; do
    REPO_NAME=$(basename "$(pwd)" .git)
    REPO_DIR="/var/git/mail/$REPO_NAME.git"

    if [ ! -d "$REPO_DIR" ]; then
        echo "Lege neues Bare-Repo an: $REPO_NAME.git"
        mkdir -p "$REPO_DIR"
        cd "$REPO_DIR"
        git init --bare -q
        chown -R git:git "$REPO_DIR"
    fi
done
EOF

sudo chmod +x /var/git/mail/.git/hooks/post-receive
```
Wichtig: Der Pfad `/var/git/mail` muss exakt der sein, auf den dein SSH-User zugreift (also git@raspberry-intra:mail/…).

## Script installieren
```sh
sudo tee /usr/local/bin/maildir-git-backup-all.sh <(cat das_obige_script)
sudo chmod +x /usr/local/bin/maildir-git-backup-all.sh
```
## Crontab als vmail
```sh
crontab -u vmail -e
# oder als root:  crontab -e  und dann:
3 2,5,8,11,14,17,20,23 * * * /usr/local/bin/maildir-git-backup-all.sh >/dev/null 2>&1
```

## SSH-Key vom vmail-User ohne Passwort auf den Raspberry
```sh
su - vmail
ssh-keygen -t ed25519 -C "vmail@mailserver backup key" -f ~/.ssh/id_mailbackup
cat ~/.ssh/id_mailbackup.pub
# → öffentlichen Key in ~git/.ssh/authorized_keys auf dem Raspberry einfügen
# (am besten nur mit command-Restriction auf das Hook-Script, aber für den Anfang reicht’s)
ssh git@raspberry-intra uptime   # → muss ohne Passwort gehen
```
