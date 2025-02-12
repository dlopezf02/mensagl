#!/bin/bash


MAESTRO_USER="osboxes"  
MAESTRO_IP="192.168.31.221" 
DB_NAME="sedes"  
BACKUP_DIR="/var/backups/mysql_maestro" 
SSH_KEY="/home/osboxes/.ssh/id_rsa"  
MYSQL_DATA_DIR="/var/lib/mysql"  
LOGFILE="/var/log/backup_mysql.log"  
DUMP_FILE="/tmp/${DB_NAME}-full-dump.sql"  
BINLOG_DIR="/var/lib/mysql"  
BINLOG_BACKUP_DIR="$BACKUP_DIR/$DB_NAME/binlogs"  

DATE=$(date +"%Y%m%d%H%M")

mkdir -p "$BACKUP_DIR/$DB_NAME"
mkdir -p "$BINLOG_BACKUP_DIR"

function perform_backup() {
    if [ ! -f "$BACKUP_DIR/$DB_NAME/last_backup" ]; then
        echo "== Realizando un respaldo completo de la base de datos '$DB_NAME' en el maestro =="
        
        ssh -i "$SSH_KEY" "$MAESTRO_USER@$MAESTRO_IP" \
            "sudo mysqldump -u root --databases $DB_NAME --single-transaction --quick --lock-tables=false > $DUMP_FILE"

        scp -i "$SSH_KEY" "$MAESTRO_USER@$MAESTRO_IP:$DUMP_FILE" "$BACKUP_DIR/$DB_NAME/"
        echo "Backup completo realizado: $(date)" >> "$LOGFILE"

        touch "$BACKUP_DIR/$DB_NAME/last_backup"
    else
        echo "== Realizando backup incremental de los archivos de datos de MySQL de '$DB_NAME' =="

        sudo mkdir -p "$BACKUP_DIR/$DB_NAME/incremental/$DATE"

        sshpass -p 'osboxes.org' sudo rsync -avz --delete -e "ssh -i $SSH_KEY" --rsync-path="sudo rsync" \
        "$MAESTRO_USER@$MAESTRO_IP:$MYSQL_DATA_DIR/sedes/" "$BACKUP_DIR/$DB_NAME/incremental/$DATE/"

        if [ $? -eq 0 ]; then
            echo "Backup incremental exitoso para '$DB_NAME': $DATE" >> "$LOGFILE"
        else
            echo "Error en el backup incremental: $DATE" >> "$LOGFILE"
        fi

        echo "== Realizando backup incremental de binlogs para '$DB_NAME' =="

        FILES=$(ssh -i "$SSH_KEY" "$MAESTRO_USER@$MAESTRO_IP" "sudo ls -1t $BINLOG_DIR/llamadas-relay-bin.* | grep -v '\.index$'| head -n 2")

        while IFS= read -r FILE; do
            FILENAME=$(basename "$FILE")
            echo "Copiando $FILENAME..."

            scp -i "$SSH_KEY" "$MAESTRO_USER@$MAESTRO_IP:$FILE" "$BINLOG_BACKUP_DIR/$FILENAME"
        done <<< "$FILES"

        if [ $? -eq 0 ]; then
            echo "Backup incremental exitoso de binlogs para '$DB_NAME': $DATE" >> "$LOGFILE"
        else
            echo "Error en el backup incremental de binlogs: $DATE" >> "$LOGFILE"
        fi
    fi

    echo "=== Backup finalizado para la base de datos '$DB_NAME' ==="
}

# Ejecutar el backup
perform_backup
