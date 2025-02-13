#!/bin/bash
# Update and install necessary packages
apt-get update -y
apt-get install -y curl certbot

# Set up DuckDNS - Update the DuckDNS IP every 5 minutes
echo "Setting up DuckDNS update script..."
mkdir -p /opt/duckdns
cat <<DUCKDNS_SCRIPT > /opt/duckdns/duckdns.sh
#!/bin/bash
echo "Updating DuckDNS: $DUCKDNS_SUBDOMAIN2"
curl -k "https://www.duckdns.org/update?domains=$DUCKDNS_SUBDOMAIN2&token=$DUCKDNS_TOKEN&ip=" -o /opt/duckdns/duck.log
DUCKDNS_SCRIPT
chmod +x /opt/duckdns/duckdns.sh
(crontab -l 2>/dev/null; echo "*/5 * * * * /opt/duckdns/duckdns.sh >/dev/null 2>&1") | crontab -

# Update DuckDNS immediately to set the IP
echo "Updating DuckDNS IP..."
/opt/duckdns/duckdns.sh
sleep 30
# Obtain SSL certificate in standalone mode (non-interactive)
echo "Obtaining SSL certificate using certbot..."
certbot certonly --standalone \
  --non-interactive \
  --agree-tos \
  --email $EMAIL \
  -d "$DUCKDNS_SUBDOMAIN2.duckdns.org"

apt-get install nginx -y
apt install nginx-extras -y
cat <<CONFIG > /etc/nginx/sites-available/proxy_site
upstream backend_servers {
    server 10.216.4.100:443;
    server 10.216.4.200:443;
}

server {
    listen 80;
    server_name $DUCKDNS_SUBDOMAIN2.duckdns.org;
    return 301 https://\$host\$request_uri;  # Redirect HTTP to HTTPS
}

server {
    listen 443 ssl;
    server_name $DUCKDNS_SUBDOMAIN2.duckdns.org;

    ssl_certificate /etc/letsencrypt/live/$DUCKDNS_SUBDOMAIN2.duckdns.org/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DUCKDNS_SUBDOMAIN2.duckdns.org/privkey.pem;
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

CONFIG
ln -s /etc/nginx/sites-available/proxy_site /etc/nginx/sites-enabled/
rm /etc/nginx/sites-enabled/default
systemctl restart nginx
systemctl enable nginx
echo "DDNS installed !"
