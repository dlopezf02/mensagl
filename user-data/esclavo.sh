#!/bin/bash

MASTER_IP="10.0.1.10"
MASTER_USER="replicador"
MASTER_PASSWORD="Admin123"

sudo apt update
sudo apt install mysql-server -y

sudo systemctl start mysql
sudo systemctl enable mysql

CONFIG_FILE="/etc/mysql/mysql.conf.d/mysqld.cnf"

if [ -f "$CONFIG_FILE" ]; then
  sudo sed -i "s/^bind-address.*/bind-address = 0.0.0.0/" "$CONFIG_FILE"
  sudo sed -i "s/^# server-id.*/server-id = 2/" "$CONFIG_FILE"
  sudo sed -i "s|^# log_bin.*|log_bin = /var/log/mysql/mysql-bin.log|" "$CONFIG_FILE"
  sudo sed -i "s/^max_binlog_size.*/max_binlog_size = 10000M/" "$CONFIG_PATH"
else
  echo "Archivo de configuración no encontrado. Abortando."
  exit 1
fi

sudo systemctl restart mysql

echo "Obteniendo información del maestro..."
MASTER_STATUS=$(mysql -h "$MASTER_IP" -u "$MASTER_USER" -p"$MASTER_PASSWORD" -e "SHOW MASTER STATUS\G" 2>/dev/null)
BINLOG_FILE=$(echo "$MASTER_STATUS" | grep "File:" | awk '{print $2}')
BINLOG_POSITION=$(echo "$MASTER_STATUS" | grep "Position:" | awk '{print $2}')

if [ -z "$BINLOG_FILE" ] || [ -z "$BINLOG_POSITION" ]; then
  echo "Error obteniendo información del maestro. Verifica las credenciales o conexión."
  exit 1
fi

echo "Archivo binlog: $BINLOG_FILE, Posición: $BINLOG_POSITION"

mysql -u root <<EOF
CHANGE MASTER TO
    MASTER_HOST='$MASTER_IP',
    MASTER_USER='$MASTER_USER',
    MASTER_PASSWORD='$MASTER_PASSWORD',
    MASTER_LOG_FILE='$BINLOG_FILE',
    MASTER_LOG_POS=$BINLOG_POSITION,
    MASTER_SSL=0;
START SLAVE;
SHOW SLAVE STATUS\G;
EOF
