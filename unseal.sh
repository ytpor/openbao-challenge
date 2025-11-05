#!/bin/bash
# Unseal the vault

not_found() { local COMMENT="$1"; echo "${COMMENT} not found" 1>&2; exit 1; }

# Load environment variables from .env file
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
else
    not_found ".env"
fi

unseal_in_container() {
    local KEY=$1
    echo "Unsealing Vault with key..."
    docker exec "${OPENBAO_CONTAINER}" /bin/sh -c "export BAO_ADDR=${OPENBAO_ADDR} && bao operator unseal ${KEY}"
}

# Unseal with both keys
unseal_in_container "${UNSEAL_KEY_1}"
unseal_in_container "${UNSEAL_KEY_2}"

echo "Vault unseal process completed inside Docker container '$OPENBAO_CONTAINER'."
