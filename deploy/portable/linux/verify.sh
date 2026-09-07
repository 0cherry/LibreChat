#!/usr/bin/env bash
set -Eeuo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
bash -n "$source_dir/setup.sh" "$source_dir/run.sh"

test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
make_fixture() {
  local target="$1"
  mkdir -p "$target"
  cp "$source_dir/setup.sh" "$source_dir/run.sh" "$target/"
  cat >"$target/images.env" <<'EOF'
LIBRECHAT_IMAGE=librechat-0cherry:test
LIBRECHAT_IMAGE_ID=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
LIBRECHAT_CONFIG_ID=sha256:1111111111111111111111111111111111111111111111111111111111111111
MONGO_IMAGE=mongo:8.0.20
MONGO_IMAGE_ID=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
MONGO_CONFIG_ID=sha256:2222222222222222222222222222222222222222222222222222222222222222
MEILI_IMAGE=getmeili/meilisearch:v1.35.1
MEILI_IMAGE_ID=sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
MEILI_CONFIG_ID=sha256:3333333333333333333333333333333333333333333333333333333333333333
SOURCE_COMMIT=4444444444444444444444444444444444444444
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

fake_bin="$test_root/bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == 'info' ]]; then
  printf '%s\n' 'linux/x86_64'
elif [[ "$1" == 'compose' && "$2" == 'version' ]]; then
  exit 0
elif [[ "$1" == 'image' && "$2" == 'inspect' && "$3" != '--format' ]]; then
  exit 0
elif [[ "$1" == 'image' && "$2" == 'inspect' && "$3" == '--format' ]]; then
  case "$4" in
    '{{.Id}}')
      case "$5" in
        librechat-0cherry:test)
          printf '%s\n' 'sha256:1111111111111111111111111111111111111111111111111111111111111111'
          ;;
        mongo:8.0.20)
          printf '%s\n' 'sha256:2222222222222222222222222222222222222222222222222222222222222222'
          ;;
        getmeili/meilisearch:v1.35.1)
          printf '%s\n' 'sha256:3333333333333333333333333333333333333333333333333333333333333333'
          ;;
      esac
      ;;
    '{{.Os}}/{{.Architecture}}')
      printf '%s\n' 'linux/amd64'
      ;;
    *)
      printf '%s\n' '4444444444444444444444444444444444444444'
      ;;
  esac
elif [[ "$1" == 'compose' ]]; then
  exit 0
else
  printf 'Unexpected docker invocation: %s\n' "$*" >&2
  exit 1
fi
EOF
chmod 755 "$fake_bin/docker"
PATH="$fake_bin:$PATH" LIBRECHAT_PROJECT=librechat-verify bash "$first/run.sh" start

before="$(sha256sum "$first/.env")"
! bash "$first/setup.sh" --server-url http://192.168.0.51:3080
[[ "$before" == "$(sha256sum "$first/.env")" ]]
for bad_url in file:///tmp/test http://user:password@example.com http://example.com/subpath 'http://example.com/?q=x'; do
  ! bash "$invalid/setup.sh" --server-url "$bad_url"
  [[ ! -e "$invalid/.env" && ! -e "$invalid/librechat.yaml" ]]
done

printf '%s\n' 'PASS: Bash syntax, setup defaults, permissions, secret uniqueness, overwrite and URL checks.'
