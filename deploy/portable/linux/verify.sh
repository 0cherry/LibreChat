#!/usr/bin/env bash
set -Eeuo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
bash -n "$source_dir/setup.sh" "$source_dir/run.sh"

test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
make_fixture() {
  local target="$1"
  mkdir -p "$target"
  cp "$source_dir/setup.sh" "$target/"
  cat >"$target/images.env" <<'EOF'
LIBRECHAT_IMAGE=librechat-0cherry:test
LIBRECHAT_IMAGE_ID=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
MONGO_IMAGE=mongo:8.0.20
MONGO_IMAGE_ID=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
MEILI_IMAGE=getmeili/meilisearch:v1.35.1
MEILI_IMAGE_ID=sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
IMAGES_SHA256=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
EOF
}

first="$test_root/first"
second="$test_root/second"
invalid="$test_root/invalid"
make_fixture "$first"
make_fixture "$second"
make_fixture "$invalid"

bash "$first/setup.sh" --server-url http://192.168.0.50:8080 --port 8080
bash "$second/setup.sh" --server-url http://192.168.0.50:8080 --port 8080
grep -Eq '^JWT_SECRET=[a-f0-9]{64}$' "$first/.env"
grep -Eq '^CREDS_IV=[a-f0-9]{32}$' "$first/.env"
grep -Eq '^HTTP_PORT=8080$' "$first/.env"
grep -Eq '^ALLOW_REGISTRATION=false$' "$first/.env"
grep -Eq '^REQUIRE_ADMIN_APPROVAL=true$' "$first/.env"
grep -Fq '${QWEN_API_KEY}' "$first/librechat.yaml"
grep -Fq 'thinking: false' "$first/librechat.yaml"
[[ "$(stat -c '%a' "$first/.env")" == '600' ]]
[[ "$(stat -c '%a' "$first/librechat.yaml")" == '600' ]]
[[ "$(sed -n 's/^JWT_SECRET=//p' "$first/.env")" != "$(sed -n 's/^JWT_SECRET=//p' "$second/.env")" ]]

before="$(sha256sum "$first/.env")"
! bash "$first/setup.sh" --server-url http://192.168.0.51:3080
[[ "$before" == "$(sha256sum "$first/.env")" ]]
for bad_url in file:///tmp/test http://user:password@example.com http://example.com/subpath 'http://example.com/?q=x'; do
  ! bash "$invalid/setup.sh" --server-url "$bad_url"
  [[ ! -e "$invalid/.env" && ! -e "$invalid/librechat.yaml" ]]
done

printf '%s\n' 'PASS: Bash syntax, setup defaults, permissions, secret uniqueness, overwrite and URL checks.'
