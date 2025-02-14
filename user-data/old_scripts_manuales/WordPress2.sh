#!/bin/bash
set -e

# The mail for certs and wordpress config
printf "%s" "Insert email: "
read EMAIL
#printf "%s" "DuckDNS domain2: "
read DUCKDNS_SUBDOMAIN2
# Variables for RDS
printf "%s" "RDS Direction (IP or URL): "
read RDS_ENDPOINT
printf "%s" "RDS Wordpress Database: "
read wDBName
printf "%s" "RDS Wordpress Username: "
read DB_USERNAME
printf "%s" "RDS Wordpress Password: "
read DB_PASSWORD


sleep 120
sudo apt update
sudo apt install apache2 mysql-client mysql-server php php-mysql -y
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp
sudo rm -rf /var/www/html/*
sudo chmod -R 755 /var/www/html
sudo chown -R ubuntu:ubuntu /var/www/html
# MySQL credentials
MYSQL_CMD="sudo mysql -h ${RDS_ENDPOINT} -u ${DB_USERNAME} -p${DB_PASSWORD}"
$MYSQL_CMD <<EOF2
CREATE DATABASE IF NOT EXISTS ${wDBName};
CREATE USER IF NOT EXISTS '${DB_USERNAME}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${wDBName}.* TO '${DB_USERNAME}'@'%';
FLUSH PRIVILEGES;
EOF2
sudo -u ubuntu -k -- wp core download --path=/var/www/html
sudo -u ubuntu -k -- wp core config --dbname=${wDBName} --dbuser=${DB_USERNAME} --dbpass=${DB_PASSWORD} --dbhost=${RDS_ENDPOINT} --dbprefix=wp_ --path=/var/www/html
sudo -u ubuntu -k -- wp core install --url=${DUCKDNS_SUBDOMAIN2}  --title=MensAGL --admin_user=${DB_USERNAME} --admin_password=${DB_PASSWORD} --admin_email=${EMAIL} --path=/var/www/html
#sudo -u ubuntu -k -- wp option update home 'https://${DUCKDNS_SUBDOMAIN2}' --path=/var/www/html
#sudo -u ubuntu -k -- wp option update siteurl 'https://${DUCKDNS_SUBDOMAIN2}' --path=/var/www/html
sudo -u ubuntu -k -- wp plugin install supportcandy --activate --path=/var/www/html
echo "
if(isset(\$_SERVER['HTTP_X_FORWARDED_FOR'])) {
    \$list = explode(',', \$_SERVER['HTTP_X_FORWARDED_FOR']);
    \$_SERVER['REMOTE_ADDR'] = \$list[0];
}
\$_SERVER['HTTP_HOST'] = '${DUCKDNS_SUBDOMAIN2}';
\$_SERVER['REMOTE_ADDR'] = '${DUCKDNS_SUBDOMAIN2}';
\$_SERVER['SERVER_ADDR'] = '${DUCKDNS_SUBDOMAIN2}';
" | sudo tee -a /var/www/html/wp-config.php
echo "Wordpress mounted !!"

sudo a2enmod ssl
sudo a2ensite default-ssl
sudo a2dissite 000-default
sudo systemctl restart apache2
