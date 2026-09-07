#!/usr/bin/env bash
set -Eeuo pipefail

bundle_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
action="${1:-start}"
project_name="${LIBRECHAT_PROJECT:-librechat-portable}"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "$action" =~ ^(load|start|stop|status|logs|bootstrap-admin|create-user|check)$ ]] ||
  fail 'Usage: ./run.sh {load|start|stop|status|logs|bootstrap-admin|create-user|check}'
[[ "$project_name" =~ ^[a-z0-9][a-z0-9_-]+$ ]] || fail 'Invalid LIBRECHAT_PROJECT'

command -v docker >/dev/null 2>&1 || fail 'Docker is not installed'
engine="$(docker info --format '{{.OSType}}/{{.Architecture}}' 2>/dev/null)" ||
  fail 'Docker Engine is not running or this user lacks permission'
[[ "$engine" == 'linux/x86_64' || "$engine" == 'linux/amd64' ]] ||
  fail 'This bundle requires a Linux amd64 Docker Engine'
docker compose version >/dev/null || fail 'Docker Compose v2 is required'

manifest_value() {
  local key="$1"
  local value
  value="$(sed -n "s/^${key}=//p" "$bundle_dir/images.env")"
  [[ -n "$value" && "$(grep -c "^${key}=" "$bundle_dir/images.env")" -eq 1 ]] ||
    fail "Invalid images.env key: $key"
  printf '%s' "$value"
}

librechat_image="$(manifest_value LIBRECHAT_IMAGE)"
librechat_id="$(manifest_value LIBRECHAT_IMAGE_ID)"
librechat_config_id="$(manifest_value LIBRECHAT_CONFIG_ID)"
mongo_image="$(manifest_value MONGO_IMAGE)"
mongo_id="$(manifest_value MONGO_IMAGE_ID)"
mongo_config_id="$(manifest_value MONGO_CONFIG_ID)"
meili_image="$(manifest_value MEILI_IMAGE)"
meili_id="$(manifest_value MEILI_IMAGE_ID)"
meili_config_id="$(manifest_value MEILI_CONFIG_ID)"
source_commit="$(manifest_value SOURCE_COMMIT)"
images_sha256="$(manifest_value IMAGES_SHA256)"

for image in "$librechat_image" "$mongo_image" "$meili_image"; do
  [[ "$image" =~ ^[A-Za-z0-9][A-Za-z0-9./_:-]+$ ]] || fail 'Invalid image tag'
done
for id in "$librechat_id" "$librechat_config_id" "$mongo_id" "$mongo_config_id" "$meili_id" "$meili_config_id"; do
  [[ "$id" =~ ^sha256:[a-f0-9]{64}$ ]] || fail 'Invalid image ID'
done
[[ "$source_commit" =~ ^[a-f0-9]{40}$ ]] || fail 'Invalid source commit'
[[ "$images_sha256" =~ ^[a-f0-9]{64}$ ]] || fail 'Invalid image archive SHA256'

verify_images() {
  local actual
  local config_id
  local image
  local expected
  local platform
  while read -r image expected config_id; do
    actual="$(docker image inspect --format '{{.Id}}' "$image" 2>/dev/null)" ||
      fail "Missing image: $image; run ./run.sh load"
    [[ "$actual" == "$expected" || "$actual" == "$config_id" ]] ||
      fail "Image ID mismatch: $image; run ./run.sh load"
    platform="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image")"
    [[ "$platform" == 'linux/amd64' ]] || fail "Wrong image platform: $image"
  done <<EOF
$librechat_image $librechat_id $librechat_config_id
$mongo_image $mongo_id $mongo_config_id
$meili_image $meili_id $meili_config_id
EOF

  local actual_revision
  actual_revision="$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$librechat_image")"
  [[ "$actual_revision" == "$source_commit" ]] ||
    fail 'LibreChat image source commit does not match images.env'
}

load_images() {
  printf '%s\n' 'Verifying image archive SHA256...'
  printf '%s  %s\n' "$images_sha256" "$bundle_dir/images.tar" | sha256sum --check --status ||
    fail 'Image checksum mismatch; copy the bundle again'
  docker image load --input "$bundle_dir/images.tar"
  verify_images
}

compose() {
  docker compose     --project-name "$project_name"     --project-directory "$bundle_dir"     --env-file "$bundle_dir/.env"     --file "$bundle_dir/compose.yaml"     "$@"
}

enable_registration() {
  local env_tmp
  grep -Fxq 'ALLOW_REGISTRATION=false' "$bundle_dir/.env" ||
    fail 'Registration is already enabled; use ./run.sh create-user for another CLI account'
  env_tmp="$(mktemp "$bundle_dir/.env.update.XXXXXXXX")"
  sed 's/^ALLOW_REGISTRATION=false$/ALLOW_REGISTRATION=true/' "$bundle_dir/.env" >"$env_tmp"
  chmod 600 "$env_tmp"
  mv -- "$env_tmp" "$bundle_dir/.env"
}

if [[ "$action" == 'load' ]]; then
  load_images
  exit 0
fi
[[ -f "$bundle_dir/.env" && -f "$bundle_dir/librechat.yaml" ]] ||
  fail 'Run ./setup.sh --server-url http://SERVER-IP:3080 first'

case "$action" in
  start)
    if ! docker image inspect "$librechat_image" "$mongo_image" "$meili_image" >/dev/null 2>&1; then
      load_images
    else
      verify_images
    fi
    compose config --quiet
    compose up -d --pull never --wait --wait-timeout 240
    printf '%s\n' 'LibreChat is ready. Use the server URL configured in .env.'
    printf '%s\n' 'For initial setup: ./run.sh bootstrap-admin'
    ;;
  stop)
    compose stop
    ;;
  status)
    compose ps --all
    ;;
  logs)
    compose logs --follow --tail 100
    ;;
  bootstrap-admin)
    printf '%s\n' 'Create the initial administrator in a private terminal.'
    printf '%s\n' 'Public registration stays closed until this command succeeds.'
    compose exec api node config/create-user.js
    enable_registration
    compose up -d --pull never --no-deps --force-recreate --wait --wait-timeout 240 api
    printf '%s\n' 'Administrator created. Public registration is enabled with approval required.'
    ;;
  create-user)
    printf '%s\n' 'Create a local account in a private terminal.'
    printf '%s\n' 'Do not pass a password on the command line.'
    compose exec api node config/create-user.js
    ;;
  check)
    compose config --quiet
    verify_images
    compose exec -T api node -e       "fetch('http://127.0.0.1:3080/api/config',{signal:AbortSignal.timeout(10000)}).then(r=>{console.log('LibreChat HTTP '+r.status);process.exit(r.ok?0:1)}).catch(e=>{console.error(e.message);process.exit(1)})"
    compose exec -T api node -e       "const fs=require('fs'),yaml=require('js-yaml');const c=yaml.load(fs.readFileSync('/app/librechat.yaml','utf8'));const u=c.endpoints.custom[0].baseURL.replace(/\/$/,'')+'/models';fetch(u,{headers:{Authorization:'Bearer '+process.env.QWEN_API_KEY},signal:AbortSignal.timeout(10000)}).then(r=>{console.log('Qwen models HTTP '+r.status);process.exit(r.ok?0:1)}).catch(e=>{console.error(e.message);process.exit(1)})"
    ;;
esac
