#!/bin/bash
###########################################################################################################
#########################                      KEYS SSH                          ##########################
###########################################################################################################

# The name of the user for lab
printf "%s" "Insert personal name: "
read ALUMNO

# Key pair SSH
KEY_NAME="ssh-mensagl-2025-${ALUMNO}"

aws ec2 create-key-pair \
  --key-name "${KEY_NAME}" \
  --query "KeyMaterial" \
  --output text > ${KEY_NAME}.pem

echo "SSH KEYS !";
