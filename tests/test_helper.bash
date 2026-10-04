#!/usr/bin/env bash
# Helpers for the dokku-libredb-studio bats suite. Sourced by every *.bats file.
# The suite runs as root inside the dokku container and calls dokku directly.

STUDIO_APP="libredb-studio"
STUDIO_HOST="${STUDIO_APP}.dokku.test"
STUDIO_ADMIN_EMAIL="admin@libredb.local"
PLUGIN_ROOT="/var/lib/dokku/data/libredb-studio"
SEED_FILE="${PLUGIN_ROOT}/seed/connections.json"
ENTRIES_DIR="${PLUGIN_ROOT}/entries"

new_service_name() {
  echo "lt${BATS_TEST_NUMBER:-0}x${RANDOM}"
}

install_studio() {
  dokku libredb-studio:install --allow-http
  # a short cache, so a test sees a change to the seed file within seconds
  # rather than within the default minute
  dokku config:set "$STUDIO_APP" SEED_CACHE_TTL_MS=2000
}

remove_studio() {
  dokku libredb-studio:uninstall >/dev/null 2>&1 || true
  if dokku apps:exists "$STUDIO_APP" >/dev/null 2>&1; then
    dokku --force apps:destroy "$STUDIO_APP" >/dev/null 2>&1 || true
  fi
  dokku --force network:destroy libredb-studio >/dev/null 2>&1 || true
}

# plugin:uninstall in a test removes the plugin; the next test needs it back.
# The install trigger also recreates the network.
reinstall_plugin() {
  dokku plugin:installed libredb-studio || dokku plugin:install "file:///tmp/libredb-studio"
}

# A datastore whose service-list trigger fails, as a broken or half-upgraded
# datastore plugin would.
install_broken_service_list() {
  local dir="/var/lib/dokku/plugins/available/lt-broken-list"
  mkdir -p "$dir"
  printf '[plugin]\ndescription = "test: a failing service-list"\nversion = "0.0.1"\n[plugin.config]\n' >"$dir/plugin.toml"
  printf '#!/usr/bin/env bash\necho "failed to list services" >&2\nexit 1\n' >"$dir/service-list"
  chmod +x "$dir/service-list"
  dokku plugin:enable lt-broken-list
}

remove_broken_service_list() {
  dokku plugin:disable lt-broken-list || true
  rm -rf /var/lib/dokku/plugins/available/lt-broken-list
}

destroy_service() {
  local type="$1" service="$2"
  if dokku "$type:exists" "$service" >/dev/null 2>&1; then
    dokku --force "$type:destroy" "$service" >/dev/null 2>&1 || true
  fi
}

seed_id() {
  echo "dokku-$1-$2"
}

seed_entry() {
  local id="$1"
  jq -c --arg id "$id" '.connections[] | select(.id == $id)' "$SEED_FILE"
}

dsn_password() {
  local type="$1" service="$2" dsn
  dsn="$(dokku "$type:info" "$service" --dsn)"
  dsn="${dsn#*://}"
  dsn="${dsn%@*}"
  echo "${dsn#*:}"
}

# Retries a command until it succeeds or the timeout in seconds passes.
wait_for() {
  local timeout="$1"
  shift
  local deadline=$((SECONDS + timeout))
  until "$@"; do
    ((SECONDS < deadline)) || return 1
    sleep 2
  done
}

studio_curl() {
  curl -fsS -H "Host: ${STUDIO_HOST}" -H "Origin: http://${STUDIO_HOST}" "$@"
}

studio_login() {
  local jar="$1" password
  password="$(dokku config:get "$STUDIO_APP" ADMIN_PASSWORD)"
  jq -n --arg email "$STUDIO_ADMIN_EMAIL" --arg password "$password" '{email: $email, password: $password}' |
    studio_curl -c "$jar" -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1/api/auth/login
}

# Runs a statement through Studio on a seeded connection, the way the editor does.
studio_query() {
  local jar="$1" id="$2" sql="$3"
  jq -n --arg id "seed:$id" --arg sql "$sql" '{connectionId: $id, sql: $sql}' |
    studio_curl -b "$jar" -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1/api/db/query
}

studio_lists() {
  local jar="$1" id="$2"
  studio_curl -b "$jar" http://127.0.0.1/api/connections/managed |
    jq -e --arg id "$id" '[.. | objects | select(.seedId? == $id or .id? == $id or .id? == ("seed:" + $id))] | length > 0' >/dev/null
}

studio_container_ids() {
  docker container ls --quiet --no-trunc --filter "label=com.dokku.app-name=${STUDIO_APP}" | sort
}
