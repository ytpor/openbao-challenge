#!/bin/bash
# Sample script that will create namespace, policy, approle and secret

jq_not_installed() { echo "jq not installed" 1>&2; exit 1; }

not_found() { local COMMENT="$1"; echo "${COMMENT} not found" 1>&2; exit 1; }

# Load environment variables from .env file
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
else
    not_found ".env"
fi

HOST=${OPENBAO_ADDR}
NAMESPACE="my-namespace"
ENGINE_PATH="secret"
POLICY_NAME="my-app-policy"
POLICY_NAME_READ_ONLY="my-app-read-only-policy"
ROLE_NAME="my-app-role"
ROLE_NAME_READ_ONLY="my-app-read-only-role"
SECRET_JSON="secret.sample.json"

check_status_code() {
    local COMMENT="$1"
    local STATUS_CODE="$2"

    if [[ "${STATUS_CODE}" == "200" ]]; then
        echo "✅ ${COMMENT} created successfully."
    elif [[ "${STATUS_CODE}" == "204" ]]; then
        echo "✅ ${COMMENT} created successfully."
    elif [[ "${STATUS_CODE}" == "400" ]]; then
        echo "📌 ${COMMENT} already exists."
    else
        echo "❌ Failed to create ${COMMENT}. HTTP status: ${STATUS_CODE}"
        exit 1
    fi
}

create_namespace() {
    local NAMESPACE="$1"
    local STATUS_CODE

    STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "${HOST}/v1/sys/namespaces/${NAMESPACE}" \
        -H "X-Vault-Token: ${OPENBAO_TOKEN}")

    check_status_code "Namespace '${NAMESPACE}'" ${STATUS_CODE}
}

enable_secret_engine() {
    local NAMESPACE="$1"
    local ENGINE_PATH="$2"
    local STATUS_CODE

    STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "${HOST}/v1/sys/mounts/${ENGINE_PATH}" \
        -H "X-Vault-Token: ${OPENBAO_TOKEN}" \
        -H "X-Vault-Namespace: ${NAMESPACE}" \
        -d '{"type":"kv", "options":{"version":"2"}}')

    check_status_code "Secret Engine '${ENGINE_PATH}'" ${STATUS_CODE}
}

enable_auth_method_approle() {
    local NAMESPACE="$1"
    local STATUS_CODE

    STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "${HOST}/v1/sys/auth/approle" \
        -H "X-Vault-Token: ${OPENBAO_TOKEN}" \
        -H "X-Vault-Namespace: ${NAMESPACE}" \
        -d '{"type": "approle"}')

    check_status_code "Auth Method 'approle'" ${STATUS_CODE}
}

store_secret() {
    local NAMESPACE="$1"
    local TOKEN="$2"
    local JSON_FILE="$3"
    local STATUS_CODE

    STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X PUT "${HOST}/v1/secret/data/${NAMESPACE}" \
        -H "X-Vault-Token: ${TOKEN}" \
        -H "X-Vault-Namespace: ${NAMESPACE}" \
        -d "@${JSON_FILE}")

    check_status_code "Secret" ${STATUS_CODE}
}

get_secret() {
    local NAMESPACE="$1"
    local TOKEN="$2"
    local RESPONSE
    local SECRET

    RESPONSE=$(curl -s -X GET \
        "${HOST}/v1/secret/data/${NAMESPACE}" \
        -H "X-Vault-Token: ${TOKEN}" \
        -H "X-Vault-Namespace: ${NAMESPACE}")

    # Extract secret using jq
    SECRET=$(echo "${RESPONSE}" | jq -r .data.data)

    if [[ "${SECRET}" ]]; then
        echo "🗝️ Namespace '${NAMESPACE}' Secret: ${SECRET}"
    fi
}

create_policy() {
    local NAMESPACE="$1"
    local POLICY_NAME="$2"
    local ROLE_NAME="$3"
    local STATUS_CODE

    STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X PUT "${HOST}/v1/sys/policies/acl/${POLICY_NAME}" \
        -H "X-Vault-Token: ${OPENBAO_TOKEN}" \
        -H "X-Vault-Namespace: ${NAMESPACE}" \
        -d "{
        \"policy\": \"path \\\"secret/data/${NAMESPACE}\\\" {\\n    capabilities = [\\\"read\\\", \\\"create\\\", \\\"update\\\"]\\n}\"
        }")

    check_status_code "AppRole '${POLICY_NAME}'" ${STATUS_CODE}
}

create_read_only_policy() {
    local NAMESPACE="$1"
    local POLICY_NAME="$2"
    local ROLE_NAME="$3"
    local STATUS_CODE

    STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X PUT "${HOST}/v1/sys/policies/acl/${POLICY_NAME}" \
        -H "X-Vault-Token: ${OPENBAO_TOKEN}" \
        -H "X-Vault-Namespace: ${NAMESPACE}" \
        -d "{
        \"policy\": \"path \\\"secret/data/${NAMESPACE}\\\" {\\n    capabilities = [\\\"read\\\"]\\n}\"
        }")

    check_status_code "AppRole '${POLICY_NAME}'" ${STATUS_CODE}
}

create_role() {
    local NAMESPACE="$1"
    local POLICY_NAME="$2"
    local ROLE_NAME="$3"
    local STATUS_CODE

    STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "${HOST}/v1/auth/approle/role/${ROLE_NAME}" \
        -H "X-Vault-Token: ${OPENBAO_TOKEN}" \
        -H "X-Vault-Namespace: ${NAMESPACE}" \
        -d "{\"policies\": [\"${POLICY_NAME}\"], \"token_ttl\": \"10m\", \"token_max_ttl\": \"15m\"}")

    check_status_code "Role '${ROLE_NAME}'" ${STATUS_CODE}
}

get_role_id() {
    local NAMESPACE="$1"
    local ROLE_NAME="$2"
    local RESPONSE

    RESPONSE=$(curl -s -X GET \
        "${HOST}/v1/auth/approle/role/${ROLE_NAME}/role-id" \
        -H "X-Vault-Token: ${OPENBAO_TOKEN}" \
        -H "X-Vault-Namespace: ${NAMESPACE}")

    # Extract role_id using jq
    ROLE_ID=$(echo "${RESPONSE}" | jq -r .data.role_id)

    if [[ "${ROLE_ID}" ]]; then
        echo "👤 Role '${ROLE_NAME}' Role ID: ${ROLE_ID}"
    fi
}

get_secret_id() {
    local NAMESPACE="$1"
    local ROLE_NAME="$2"
    local RESPONSE

    RESPONSE=$(curl -s -X POST \
        "${HOST}/v1/auth/approle/role/${ROLE_NAME}/secret-id" \
        -H "X-Vault-Token: ${OPENBAO_TOKEN}" \
        -H "X-Vault-Namespace: ${NAMESPACE}")

    # Extract secret_id using jq
    SECRET_ID=$(echo "${RESPONSE}" | jq -r .data.secret_id)

    if [[ "${SECRET_ID}" ]]; then
        echo "🗝️ Role '${ROLE_NAME}' Secret ID: ${SECRET_ID}"
    fi
}

get_token() {
    local NAMESPACE="$1"
    local ROLE_ID="$2"
    local SECRET_ID="$3"
    local RESPONSE

    RESPONSE=$(curl -s -X POST \
        "${HOST}/v1/auth/approle/login" \
        -H "X-Vault-Namespace: ${NAMESPACE}" \
        -d "{\"role_id\": \"${ROLE_ID}\", \"secret_id\": \"${SECRET_ID}\"}")

    # Extract role_id using jq
    TOKEN=$(echo "${RESPONSE}" | jq -r .auth.client_token)

    if [[ "${TOKEN}" ]]; then
        echo "🧩 Role ID '${ROLE_ID}' Token: ${TOKEN}"
    fi
}

main() {
    create_namespace ${NAMESPACE}
    enable_secret_engine ${NAMESPACE} ${ENGINE_PATH}
    # With root access
    store_secret ${NAMESPACE} ${OPENBAO_TOKEN} ${SECRET_JSON}
    get_secret ${NAMESPACE} ${OPENBAO_TOKEN}
    enable_auth_method_approle ${NAMESPACE}
    create_policy ${NAMESPACE} ${POLICY_NAME}
    create_read_only_policy ${NAMESPACE} ${POLICY_NAME_READ_ONLY}
    create_role ${NAMESPACE} ${POLICY_NAME} ${ROLE_NAME}
    create_role ${NAMESPACE} ${POLICY_NAME_READ_ONLY} ${ROLE_NAME_READ_ONLY}
    # With role that has full access
    get_role_id ${NAMESPACE} ${ROLE_NAME}
    get_secret_id ${NAMESPACE} ${ROLE_NAME}
    get_token ${NAMESPACE} ${ROLE_ID} ${SECRET_ID}
    store_secret ${NAMESPACE} ${TOKEN} ${SECRET_JSON}
    get_secret ${NAMESPACE} ${TOKEN}
    # With role that has read only access
    get_role_id ${NAMESPACE} ${ROLE_NAME_READ_ONLY}
    get_secret_id ${NAMESPACE} ${ROLE_NAME_READ_ONLY}
    get_token ${NAMESPACE} ${ROLE_ID} ${SECRET_ID}
    get_secret ${NAMESPACE} ${TOKEN}
    store_secret ${NAMESPACE} ${TOKEN} ${SECRET_JSON}
}

# Run the script
main
