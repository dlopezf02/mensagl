#!/bin/bash

export DUCKDNS_TOKEN="${DUCKDNS_TOKEN}"
export DUCKDNS_SUBDOMAIN="${DUCKDNS_SUBDOMAIN}"
export EMAIL="${EMAIL}"
export host="${host}"
export request_uri="${request_uri}"

# Update and install necessary packages
sudo apt update && sudo  DEBIAN_FRONTEND=noninteractive apt install nginx-full python3-pip pipx -y
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
pip install certbot-dns-duckdns
pipx install certbot-dns-duckdns
sudo snap install --classic certbot
sudo snap install certbot-dns-duckdns
sudo snap set certbot trust-plugin-with-root=ok
sudo snap connect certbot:plugin certbot-dns-duckdns



echo "Setting up DuckDNS update script..."
mkdir -p /opt/duckdns
cat <<DUCKDNS_SCRIPT > /opt/duckdns/duckdns.sh
#!/bin/bash
echo "Updating DuckDNS: ${DUCKDNS_SUBDOMAIN}"
curl -k "https://www.duckdns.org/update?domains=${DUCKDNS_SUBDOMAIN}&token=${DUCKDNS_TOKEN}&ip=" -o /opt/duckdns/duck.log
DUCKDNS_SCRIPT
chmod +x /opt/duckdns/duckdns.sh
(crontab -l 2>/dev/null; echo "*/5 * * * * /opt/duckdns/duckdns.sh >/dev/null 2>&1") | crontab -

echo "Updating DuckDNS IP..."
/opt/duckdns/duckdns.sh

sleep 10

#while [ ! -e /etc/letsencrypt/live/${DUCKDNS_SUBDOMAIN}.duckdns.org ]; do
sudo certbot certonly  --non-interactive \
    --agree-tos \
    --email "${EMAIL}" \
    --preferred-challenges dns \
    --authenticator dns-duckdns \
    --dns-duckdns-token "${DUCKDNS_TOKEN}" \
    --dns-duckdns-propagation-seconds 60 \
    -d "${DUCKDNS_SUBDOMAIN}.duckdns.org"
#done
#while [ ! -e /etc/letsencrypt/live/${DUCKDNS_SUBDOMAIN}.duckdns.org-0001 ]; do
sudo certbot certonly  --non-interactive \
    --agree-tos \
    --email "${EMAIL}" \
    --preferred-challenges dns \
    --authenticator dns-duckdns \
    --dns-duckdns-token "${DUCKDNS_TOKEN}" \
    --dns-duckdns-propagation-seconds 60 \
    -d "*.${DUCKDNS_SUBDOMAIN}.duckdns.org"
#done


# Install and configure NGINX
echo "Installing and configuring NGINX..."

cat <<EOF > /etc/nginx/sites-available/proxy_site
upstream backend_meets {
    server 10.216.3.100:443;
    server 10.216.3.200:443;
#    server 10.216.3.150:443;
}

upstream backend_xmpp {
    server 10.216.3.100:12345;
    server 10.216.3.200:12345;
}

server {
    listen 80;
    server_name ${DUCKDNS_SUBDOMAIN}.duckdns.org upload.${DUCKDNS_SUBDOMAIN}.duckdns.org;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }

    location /llamadas {
        return 301 https://\$host\$request_uri;
    }

    location /xmpp {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name ${DUCKDNS_SUBDOMAIN}.duckdns.org;

    ssl_certificate /etc/letsencrypt/live/${DUCKDNS_SUBDOMAIN}.duckdns.org/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DUCKDNS_SUBDOMAIN}.duckdns.org/privkey.pem;

    # Redirect root (/) to /llamadas
#    location / {
#        return 301 https://\$host/llamadas;
#    }

    # Strip /llamadas before sending to Jitsi
    location /llamadas/ {
#    location / {
        rewrite ^/llamadas(/.*)\$ \$1 break;
        proxy_pass https://backend_meets;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Allow Jitsi static files (CSS, JS, images)
    location /libs/ {
        proxy_pass https://backend_meets;
        proxy_set_header Host \$host;
    }

    location /css/ {
        proxy_pass https://backend_meets;
        proxy_set_header Host \$host;
    }

    location /static/ {
        proxy_pass https://backend_meets;
        proxy_set_header Host \$host;
    }

    location /images/ {
        proxy_pass https://backend_meets;
        proxy_set_header Host \$host;
    }

    location /sounds/ {
        proxy_pass https://backend_meets;
        proxy_set_header Host \$host;
    }

    location /xmpp {
        proxy_pass http://backend_xmpp;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
ln -s /etc/nginx/sites-available/proxy_site /etc/nginx/sites-enabled/
rm /etc/nginx/sites-enabled/default
rm /etc/nginx/sites-available/default

# Add stream block to nginx.conf
cat <<STREAM_CONF | sudo tee -a /etc/nginx/nginx.conf > /dev/null
stream {
    upstream backend_xmpp_5222 {
        server 10.216.3.100:5222;
        server 10.216.3.200:5222;
    }

    upstream backend_xmpp_5280 {
        server 10.216.3.100:5280;
        server 10.216.3.200:5280;
    }

    upstream backend_xmpp_5281 {
        server 10.216.3.100:5281;
        server 10.216.3.200:5281;
    }

    upstream backend_xmpp_5347 {
        server 10.216.3.100:5347;
        server 10.216.3.200:5347;
    }

    upstream backend_xmpp_4443 {
        server 10.216.3.100:4443;
        server 10.216.3.200:4443;
    }

    upstream backend_xmpp_10000 {
        server 10.216.3.100:10000;
        server 10.216.3.200:10000;
    }

    upstream backend_xmpp_5269 {
        server 10.216.3.100:5269;
        server 10.216.3.200:5269;
    }
    upstream backend_xmpp_5270 {
        server 10.216.3.100:5270;
        server 10.216.3.200:5270;
    }
    upstream backend_mysql {
        server 10.216.3.10:3306;
        server 10.216.3.20:3306;
    }

    server {
        listen 5222;
        proxy_pass backend_xmpp_5222;
    }
    server {
        listen 5280;
        proxy_pass backend_xmpp_5280;
    }
    server {
        listen 5281;
        proxy_pass backend_xmpp_5281;
    }
    server {
        listen 5347;
        proxy_pass backend_xmpp_5347;
    }
    server {
        listen 4443;
        proxy_pass backend_xmpp_4443;
    }
    server {
        listen 10000;
        proxy_pass backend_xmpp_10000;
    }
    server {
        listen 5269;
        proxy_pass backend_xmpp_5269;
#       ssl_certificate /etc/letsencrypt/${DUCKDNS_SUBDOMAIN}.duckdns.org/fullchain.pem;
#       ssl_certificate_key /etc/letsencrypt/${DUCKDNS_SUBDOMAIN}.duckdns.org/keyfile.pem;
        proxy_ssl_verify off;
    }
    server {
        listen 5270;
        proxy_pass backend_xmpp_5270;
#        ssl_certificate /etc/letsencrypt/${DUCKDNS_SUBDOMAIN}.duckdns.org/fullchain.pem;
#        ssl_certificate_key /etc/letsencrypt/${DUCKDNS_SUBDOMAIN}.duckdns.org/keyfile.pem;
        proxy_ssl_verify off;
    }
    server {
        listen 3306;
        proxy_pass backend_mysql;
        proxy_timeout 600s;
        proxy_connect_timeout 600s;
    }
}
STREAM_CONF

sudo systemctl start nginx
sudo systemctl restart nginx
systemctl enable nginx
echo "DDNS installed !"




cat <<CERT > /home/ubuntu/certs.sh
#!/bin/bash
sudo systemctl stop nginx
sudo certbot certonly  --non-interactive \
    --agree-tos \
    --email "${EMAIL}" \
    --preferred-challenges dns \
    --authenticator dns-duckdns \
    --dns-duckdns-token "${DUCKDNS_TOKEN}" \
    --dns-duckdns-propagation-seconds 120 \
    -d "${DUCKDNS_SUBDOMAIN}.duckdns.org"
sudo certbot certonly  --non-interactive \
    --agree-tos \
    --email "${EMAIL}" \
    --preferred-challenges dns \
    --authenticator dns-duckdns \
    --dns-duckdns-token "${DUCKDNS_TOKEN}" \
    --dns-duckdns-propagation-seconds 120 \
    -d "*.${DUCKDNS_SUBDOMAIN}.duckdns.org"

mkdir /home/ubuntu/certs
mkdir -p /home/ubuntu/certs/wildcard

sudo cp /etc/letsencrypt/live/${DUCKDNS_SUBDOMAIN}.duckdns.org/* /home/ubuntu/certs
sudo cp /etc/letsencrypt/live/_.${DUCKDNS_SUBDOMAIN}.duckdns.org-0001/* /home/ubuntu/certs/wildcard
sudo chown -R ubuntu:ubuntu /home/ubuntu/certs
sudo chown -R ubuntu:ubuntu /home/ubuntu/certs/wildcard
sudo systemctl start nginx
sudo systemctl restart nginx
CERT
chmod +x /home/ubuntu/certs.sh
