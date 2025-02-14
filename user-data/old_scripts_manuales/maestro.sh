#!/bin/bash


MASTER_IP="10.216.1.10"
SLAVE_IP="10.216.1.20"
MASTER_USER="replicador"
MASTER_PASSWORD="Admin123"

echo 
sudo apt update
sudo apt install mysql-server -y

sudo systemctl start mysql
sudo systemctl enable mysql

echo "Configurando MySQL para aceptar conexiones remotas..."
CONFIG_DIR="/etc/mysql/mysql.conf.d"
CONFIG_FILE="mysqld.cnf"
CONFIG_PATH="$CONFIG_DIR/$CONFIG_FILE"
if [ -f "$CONFIG_PATH" ]; then
  sudo sed -i "s/^bind-address.*/bind-address = 0.0.0.0/" "$CONFIG_PATH"
  sudo sed -i "s/^# server-id.*/server-id = 1/" "$CONFIG_PATH"
  sudo sed -i "s|^# log_bin.*|log_bin = /var/log/mysql/mysql-bin.log|" "$CONFIG_PATH"
  sudo sed -i "s/^max_binlog_size.*/max_binlog_size = 10000M/" "$CONFIG_PATH"
else
  echo "Archivo de configuración $CONFIG_PATH no encontrado. Abortando."
  exit 1
fi

sudo systemctl restart mysql

mysql -u root <<EOF
CREATE USER IF NOT EXISTS '$MASTER_USER'@'$SLAVE_IP' IDENTIFIED WITH mysql_native_password BY '$MASTER_PASSWORD';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO '$MASTER_USER'@'$SLAVE_IP';
FLUSH PRIVILEGES;
FLUSH TABLES WITH READ LOCK;
SHOW MASTER STATUS;
UNLOCK TABLES;
EOF

sudo systemctl restart mysql

mysql -u root <<EOF
SHOW MASTER STATUS;
EOF

exit 0
