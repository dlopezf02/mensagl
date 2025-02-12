#!/bin/bash

export DUCKDNS_TOKEN="${DUCKDNS_TOKEN}"
export DUCKDNS_SUBDOMAIN2="${DUCKDNS_SUBDOMAIN2}"
export EMAIL="${EMAIL}"

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


# Set up DuckDNS - Update the DuckDNS IP every 5 minutes
echo "Setting up DuckDNS update script..."
mkdir -p /opt/duckdns
cat <<DUCKDNS_SCRIPT > /opt/duckdns/duckdns.sh
#!/bin/bash
echo "Updating DuckDNS: ${DUCKDNS_SUBDOMAIN2}"
curl -k "https://www.duckdns.org/update?domains=${DUCKDNS_SUBDOMAIN2}&token=${DUCKDNS_TOKEN}&ip=" -o /opt/duckdns/duck.log
DUCKDNS_SCRIPT
chmod +x /opt/duckdns/duckdns.sh
(crontab -l 2>/dev/null; echo "*/5 * * * * /opt/duckdns/duckdns.sh >/dev/null 2>&1") | crontab -

# Update DuckDNS immediately to set the IP
echo "Updating DuckDNS IP..."
/opt/duckdns/duckdns.sh

sleep 10


#while [ ! -e /etc/letsencrypt/live/${DUCKDNS_SUBDOMAIN2}.duckdns.org ]; do
sudo certbot certonly  --non-interactive \
    --agree-tos \
    --email "${EMAIL}" \
    --preferred-challenges dns \
    --authenticator dns-duckdns \
    --dns-duckdns-token "${DUCKDNS_TOKEN}" \
    --dns-duckdns-propagation-seconds 60 \
    -d "${DUCKDNS_SUBDOMAIN2}.duckdns.org"
#done


cat <<EOF > /etc/nginx/sites-available/proxy_site
upstream backend_servers {
    server 10.0.4.100:443;
    server 10.0.4.200:443;
}

server {
    listen 80;
    server_name ${DUCKDNS_SUBDOMAIN2}.duckdns.org;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name ${DUCKDNS_SUBDOMAIN2}.duckdns.org;

    ssl_certificate /etc/letsencrypt/live/${DUCKDNS_SUBDOMAIN2}.duckdns.org/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DUCKDNS_SUBDOMAIN2}.duckdns.org/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass https://backend_servers;
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

sudo systemctl start nginx
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
    -d "${DUCKDNS_SUBDOMAIN2}.duckdns.org"
sudo certbot certonly  --non-interactive \
    --agree-tos \
    --email "${EMAIL}" \
    --preferred-challenges dns \
    --authenticator dns-duckdns \
    --dns-duckdns-token "${DUCKDNS_TOKEN}" \
    --dns-duckdns-propagation-seconds 120 \
    -d "*.${DUCKDNS_SUBDOMAIN2}.duckdns.org"

mkdir /home/ubuntu/certs
mkdir -p /home/ubuntu/certs/wildcard

sudo cp /etc/letsencrypt/live/${DUCKDNS_SUBDOMAIN2}.duckdns.org/* /home/ubuntu/certs
sudo cp /etc/letsencrypt/live/_.${DUCKDNS_SUBDOMAIN2}.duckdns.org-0001/* /home/ubuntu/certs/wildcard
sudo chown -R ubuntu:ubuntu /home/ubuntu/certs
sudo chown -R ubuntu:ubuntu /home/ubuntu/certs/wildcard
sudo systemctl start nginx
sudo systemctl restart nginx
CERT
chmod +x /home/ubuntu/certs.sh
