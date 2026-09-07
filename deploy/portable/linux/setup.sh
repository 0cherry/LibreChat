#!/usr/bin/env bash
set -Eeuo pipefail

bundle_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
server_url=""
port="3080"
bind_address="0.0.0.0"
qwen_url="http://10.10.10.200:19640/v1"
model="Qwen/Qwen3.6-27B"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  ./setup.sh --server-url http://SERVER-IP:3080 [options]

Options:
  --port PORT                 Host port (default: 3080)
  --bind-address IPV4         Bind address (default: 0.0.0.0)
  --qwen-url URL              OpenAI-compatible base URL
  --model ID                  Model ID
  -h, --help                  Show this help
EOF
}

need_value() {
  [[ $# -ge 2 && -n "$2" ]] || fail "Missing value for $1"
}

while (($#)); do
  case "$1" in
    --server-url) need_value "$@"; server_url="$2"; shift 2 ;;
    --port) need_value "$@"; port="$2"; shift 2 ;;
    --bind-address) need_value "$@"; bind_address="$2"; shift 2 ;;
    --qwen-url) need_value "$@"; qwen_url="$2"; shift 2 ;;
    --model) need_value "$@"; model="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown option: $1" ;;
  esac
done

[[ -n "$server_url" ]] || { usage >&2; fail '--server-url is required'; }
[[ "$server_url" =~ ^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?/?$ ]] ||
  fail 'Server URL must be an HTTP(S) site root without credentials, query, or path'
[[ "$qwen_url" =~ ^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?/?$ ]] ||
  fail 'Qwen URL contains unsupported characters or components'
[[ "$model" =~ ^[A-Za-z0-9._:/+-]+$ ]] || fail 'Invalid model ID'
[[ "$port" =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535)) || fail 'Port must be 1-65535'

[[ "$bind_address" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || fail 'Bind address must be IPv4'
IFS=. read -r ip1 ip2 ip3 ip4 extra <<<"$bind_address"
[[ -z "${extra:-}" && -n "${ip4:-}" ]] || fail 'Bind address must be IPv4'
for octet in "$ip1" "$ip2" "$ip3" "$ip4"; do
  [[ "$octet" =~ ^[0-9]{1,3}$ ]] || fail 'Bind address must be IPv4'
  ((10#$octet <= 255)) || fail 'Bind address must be IPv4'
done

env_path="$bundle_dir/.env"
config_path="$bundle_dir/librechat.yaml"
[[ ! -e "$env_path" && ! -e "$config_path" ]] ||
  fail 'Configuration exists; setup never replaces .env or librechat.yaml'

manifest_value() {
  local key="$1"
  local value
  value="$(sed -n "s/^${key}=//p" "$bundle_dir/images.env")"
  [[ -n "$value" && "$(grep -c "^${key}=" "$bundle_dir/images.env")" -eq 1 ]] ||
    fail "Invalid images.env key: $key"
  printf '%s' "$value"
}

librechat_image="$(manifest_value LIBRECHAT_IMAGE)"
mongo_image="$(manifest_value MONGO_IMAGE)"
meili_image="$(manifest_value MEILI_IMAGE)"
for image in "$librechat_image" "$mongo_image" "$meili_image"; do
  [[ "$image" =~ ^[A-Za-z0-9][A-Za-z0-9./_:-]+$ ]] || fail 'Invalid image tag'
done

new_secret() {
  local bytes="${1:-32}"
  od -An -N "$bytes" -tx1 /dev/urandom | tr -d ' \n'
}

server_url="${server_url%/}"
qwen_url="${qwen_url%/}"
authority="${qwen_url#*://}"
authority="${authority%%/*}"
umask 077
env_tmp="$(mktemp "$bundle_dir/.env.tmp.XXXXXXXX")"
config_tmp="$(mktemp "$bundle_dir/librechat.yaml.tmp.XXXXXXXX")"
cleanup() {
  rm -f -- "$env_tmp" "$config_tmp"
}
trap cleanup EXIT

cat >"$env_tmp" <<EOF
LIBRECHAT_IMAGE=$librechat_image
MONGO_IMAGE=$mongo_image
MEILI_IMAGE=$meili_image
HTTP_PORT=$port
BIND_ADDRESS=$bind_address
DOMAIN_CLIENT=$server_url
DOMAIN_SERVER=$server_url
JWT_SECRET=$(new_secret)
JWT_REFRESH_SECRET=$(new_secret)
CREDS_KEY=$(new_secret)
CREDS_IV=$(new_secret 16)
MEILI_MASTER_KEY=$(new_secret)
QWEN_API_KEY=local-no-key
ENDPOINTS=custom
SEARCH=true
MEILI_NO_ANALYTICS=true
ALLOW_EMAIL_LOGIN=true
ALLOW_REGISTRATION=false
REQUIRE_ADMIN_APPROVAL=true
ALLOW_SOCIAL_LOGIN=false
ALLOW_SOCIAL_REGISTRATION=false
ALLOW_PASSWORD_RESET=false
ALLOW_UNVERIFIED_EMAIL_LOGIN=true
ALLOW_SHARED_LINKS=false
ALLOW_SHARED_LINKS_PUBLIC=false
NO_INDEX=true
DEBUG_LOGGING=false
EOF

cat >"$config_tmp" <<EOF
version: 1.3.15
cache: true
endpoints:
  allowedAddresses:
    - '$authority'
  custom:
    - name: 'Qwen Local'
      apiKey: '\${QWEN_API_KEY}'
      baseURL: '$qwen_url'
      models:
        default:
          - '$model'
        fetch: false
      titleConvo: false
      summarize: false
      modelDisplayLabel: 'Qwen Local'
      defaultParams:
        thinking: false
      customParams:
        paramDefinitions:
          - key: 'thinking'
            label: 'Qwen Thinking'
            description: 'Enable or disable model reasoning before the answer.'
            type: 'boolean'
            default: false
            component: 'switch'
            columnSpan: 2
EOF

chmod 600 "$env_tmp" "$config_tmp"
mv -- "$env_tmp" "$env_path"
mv -- "$config_tmp" "$config_path"
trap - EXIT
printf 'Configured: %s\n' "$server_url"
printf '%s\n' 'New secrets generated. Keep .env private and back it up with your data.'
printf '%s\n' 'Next: ./run.sh start, then ./run.sh bootstrap-admin'
