#!/usr/bin/env bash
# Executar UMA vez na VM Ubuntu (ARM64) da OCI:  bash bootstrap-vm.sh
set -euo pipefail
REPO_URL="https://github.com/outraperspectiva/MiroFish.git"
APP_DIR="/var/www/mirofish"

# 1) iptables local (imagens Ubuntu da OCI bloqueiam 80/443 por padrão)
for p in 80 443; do
  sudo iptables -C INPUT -p tcp --dport $p -m conntrack --ctstate NEW -j ACCEPT 2>/dev/null \
    || sudo iptables -I INPUT -p tcp --dport $p -m conntrack --ctstate NEW -j ACCEPT
done
sudo DEBIAN_FRONTEND=noninteractive apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
sudo netfilter-persistent save

# 2) Pacotes + Docker
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg git nginx certbot python3-certbot-nginx
command -v docker >/dev/null || curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"

# 3) Swap de 4 GB (build do Vite/uv + simulações) — evita OOM
if ! swapon --show | grep -q /swapfile; then
  sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile
  sudo mkswap /swapfile && sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi

# 4) Código (branch oci-prod do fork)
sudo mkdir -p "$APP_DIR" && sudo chown -R "$USER":"$USER" "$APP_DIR"
[ -d "$APP_DIR/.git" ] || git clone "$REPO_URL" "$APP_DIR"
cd "$APP_DIR" && git fetch origin && git checkout oci-prod && git pull --ff-only
mkdir -p backend/uploads

# 5) Nginx
sudo cp deploy/oci/nginx-mirofish.conf /etc/nginx/sites-available/mirofish
sudo ln -sf /etc/nginx/sites-available/mirofish /etc/nginx/sites-enabled/mirofish
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx

echo
echo "OK. Agora crie $APP_DIR/.env (veja .env.example), depois:"
echo "  cd $APP_DIR && sg docker -c 'docker compose up -d --build'"
