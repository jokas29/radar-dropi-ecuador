#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive
WEBROOT=/var/www/radar-commerce
DB_NAME=radar_commerce
DB_USER=radar_wp
DB_PASS="$(openssl rand -hex 24)"
WP_ADMIN="${RADAR_WP_ADMIN_USER:-radar_admin}"
WP_PASS="${RADAR_WP_ADMIN_PASS:-$(openssl rand -hex 24)}"

log(){ printf '[radar-commerce] %s\n' "$*"; }

log 'Installing packages'
apt-get update -y
apt-get install -y nginx mariadb-server php-fpm php-cli php-mysql php-curl php-gd php-intl php-mbstring php-soap php-xml php-zip unzip curl jq ca-certificates certbot python3-certbot-nginx ufw fail2ban

PUBLIC_IP=''
for _ in $(seq 1 20); do
  PUBLIC_IP="$(curl -4fsS --max-time 5 https://api.ipify.org || true)"
  if [[ "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then break; fi
  sleep 5
done
[[ "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Could not detect public IPv4' >&2; exit 1; }
DOMAIN="radar-${PUBLIC_IP//./-}.sslip.io"

log 'Adding swap for the Always Free micro VM'
if ! swapon --show | grep -q '/swapfile'; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

log 'Tuning MariaDB for low memory'
cat >/etc/mysql/mariadb.conf.d/60-radar.cnf <<'EOF'
[mysqld]
innodb_buffer_pool_size=128M
innodb_log_buffer_size=16M
max_connections=25
performance_schema=OFF
table_open_cache=256
tmp_table_size=32M
max_heap_table_size=32M
skip_name_resolve=1
EOF
systemctl restart mariadb

mysql <<SQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

log 'Installing WP-CLI and WordPress'
curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp
chmod +x /usr/local/bin/wp
mkdir -p "$WEBROOT"
chown -R www-data:www-data "$WEBROOT"
sudo -u www-data wp core download --path="$WEBROOT" --locale=es_ES
sudo -u www-data wp config create --path="$WEBROOT" --dbname="$DB_NAME" --dbuser="$DB_USER" --dbpass="$DB_PASS" --dbhost=localhost --skip-check
sudo -u www-data wp config set DISALLOW_FILE_EDIT true --raw --path="$WEBROOT"
sudo -u www-data wp config set WP_MEMORY_LIMIT 256M --path="$WEBROOT"
sudo -u www-data wp config set DISABLE_WP_CRON true --raw --path="$WEBROOT"
sudo -u www-data wp core install --path="$WEBROOT" --url="http://${DOMAIN}" --title='Radar Commerce Bridge' --admin_user="$WP_ADMIN" --admin_password="$WP_PASS" --admin_email="admin@${DOMAIN}" --skip-email
sudo -u www-data wp option update blog_public 0 --path="$WEBROOT"
sudo -u www-data wp option update users_can_register 0 --path="$WEBROOT"
sudo -u www-data wp rewrite structure '/%postname%/' --hard --path="$WEBROOT"

log 'Installing WooCommerce and Dropify'
sudo -u www-data wp plugin install woocommerce --activate --path="$WEBROOT"
sudo -u www-data wp plugin install wc-dropi-integration --activate --path="$WEBROOT"
sudo -u www-data wp option update woocommerce_default_country 'EC' --path="$WEBROOT"
sudo -u www-data wp option update woocommerce_currency 'USD' --path="$WEBROOT"
sudo -u www-data wp option update woocommerce_enable_guest_checkout 'yes' --path="$WEBROOT"

PHP_FPM_SOCK="$(find /run/php -maxdepth 1 -type s -name 'php*-fpm.sock' | head -n1)"
[[ -n "$PHP_FPM_SOCK" ]] || { echo 'PHP-FPM socket not found' >&2; exit 1; }

cat >/etc/nginx/sites-available/radar-commerce <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    root ${WEBROOT};
    index index.php index.html;
    add_header X-Robots-Tag 'noindex, nofollow, noarchive' always;
    client_max_body_size 64m;

    location / { try_files \$uri \$uri/ /index.php?\$args; }
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_FPM_SOCK};
    }
    location ~ /\. { deny all; }
    location ~* /(wp-config\.php|readme\.html|license\.txt)$ { deny all; }
}
EOF
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/radar-commerce /etc/nginx/sites-enabled/radar-commerce
nginx -t
systemctl restart nginx

log 'Configuring VM firewall'
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable
systemctl enable --now fail2ban

log 'Attempting free HTTPS certificate'
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect || true
if [[ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
  sudo -u www-data wp option update home "https://${DOMAIN}" --path="$WEBROOT"
  sudo -u www-data wp option update siteurl "https://${DOMAIN}" --path="$WEBROOT"
  SCHEME=https
else
  SCHEME=http
fi

cat >/etc/cron.d/radar-wordpress <<EOF
*/5 * * * * www-data /usr/bin/php ${WEBROOT}/wp-cron.php >/dev/null 2>&1
EOF
chmod 644 /etc/cron.d/radar-wordpress

umask 077
cat >/root/RADAR_READY.txt <<EOF
RADAR COMMERCE READY
URL=${SCHEME}://${DOMAIN}
WP_ADMIN_URL=${SCHEME}://${DOMAIN}/wp-admin/
WP_USER=${WP_ADMIN}
WP_PASSWORD=${WP_PASS}
PUBLIC_IP=${PUBLIC_IP}

Installed plugins:
- WooCommerce
- Dropify (wc-dropi-integration)

These credentials live only on this VM. Do not paste them into chats or public repositories.
EOF

touch /root/RADAR_INSTALL_OK
log "Ready: ${SCHEME}://${DOMAIN}"
