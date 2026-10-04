#!/usr/bin/env bash
# Helpers for the unit suite. It runs the plugin's own files against stand-ins
# for dokku, docker, plugn and the datastore plugins (tests/unit/stubs), so it
# needs no docker daemon and no dokku host: `bats tests/unit`.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
STUBS="$REPO_ROOT/tests/unit/stubs"

setup_sandbox() {
  local type

  export STUB_STATE="$BATS_TEST_TMPDIR/state"
  mkdir -p "$STUB_STATE/apps" "$STUB_STATE/services" "$STUB_STATE/docker/networks" "$STUB_STATE/docker/containers"
  : >"$STUB_STATE/calls.log"

  export PLUGIN_CORE_AVAILABLE_PATH="$BATS_TEST_TMPDIR/core"
  mkdir -p "$PLUGIN_CORE_AVAILABLE_PATH"
  ln -s "$STUBS/common" "$PLUGIN_CORE_AVAILABLE_PATH/common"

  export PLUGIN_AVAILABLE_PATH="$BATS_TEST_TMPDIR/available"
  mkdir -p "$PLUGIN_AVAILABLE_PATH"
  ln -s "$REPO_ROOT" "$PLUGIN_AVAILABLE_PATH/libredb-studio"

  export PLUGIN_ENABLED_PATH="$BATS_TEST_TMPDIR/enabled"
  for type in postgres mysql mariadb mongo redis; do
    mkdir -p "$PLUGIN_ENABLED_PATH/$type/subcommands"
    ln -s "$STUBS/datastore/subcommand" "$PLUGIN_ENABLED_PATH/$type/subcommands/info"
    ln -s "$STUBS/datastore/subcommand" "$PLUGIN_ENABLED_PATH/$type/subcommands/set"
  done

  export DOKKU_LIB_ROOT="$BATS_TEST_TMPDIR/lib"
  export DOKKU_SYSTEM_USER DOKKU_SYSTEM_GROUP
  DOKKU_SYSTEM_USER="$(id -un)"
  DOKKU_SYSTEM_GROUP="$(id -gn)"
  export LIBREDB_STUDIO_UID LIBREDB_STUDIO_GID
  LIBREDB_STUDIO_UID="$(id -u)"
  LIBREDB_STUDIO_GID="$(id -g)"
  export DOCKER_BIN="docker"
  export LIBREDB_STUDIO_LOCK_TIMEOUT=2
  export PATH="$STUBS/bin:$PATH"

  ROOT="$DOKKU_LIB_ROOT/data/libredb-studio"
  SEED_FILE="$ROOT/seed/connections.json"
  ENTRIES_DIR="$ROOT/entries"
  LOCK_FILE="$ROOT/seed.lock"
  mkdir -p "$ROOT/seed" "$ROOT/entries" "$ROOT/storage"
}

# Runs one function from internal-functions in a fresh bash, as a trigger would.
plugin_call() {
  bash -c 'source "$PLUGIN_AVAILABLE_PATH/libredb-studio/internal-functions"; "$@"' _ "$@"
}

# Runs one function from command-functions in a fresh bash, as a subcommand would.
command_call() {
  bash -c 'source "$PLUGIN_AVAILABLE_PATH/libredb-studio/command-functions"; "$@"' _ "$@"
}

# The DNS name dokku-datastore gives a service: dots and underscores become dashes.
service_alias() {
  local name="$2"
  name="${name//./-}"
  echo "dokku-$1-${name//_/-}"
}

# Creates a datastore service with a running container, as <type>:create does.
add_service() {
  local type="$1" service="$2" dir alias
  dir="$STUB_STATE/services/$type/$service"
  alias="$(service_alias "$type" "$service")"
  mkdir -p "$dir" "$STUB_STATE/docker/containers/dokku.$type.$service"
  case "$type" in
    redis) echo "redis://:secret-$service@$alias:6379" >"$dir/dsn" ;;
    *) echo "postgres://postgres:secret-$service@$alias:5432/$service" >"$dir/dsn" ;;
  esac
}

# Creates a running container of an app on the Studio network, labelled with
# the app name as dokku labels every container it makes for an app.
add_app_container() {
  local app="$1" container="$2"
  mkdir -p "$STUB_STATE/docker/containers/$container" "$STUB_STATE/docker/app-labels"
  echo "$container" >"$STUB_STATE/docker/containers/$container/libredb-studio"
  echo "$app" >"$STUB_STATE/docker/app-labels/$container"
}

remove_service() {
  local type="$1" service="$2"
  rm -rf "$STUB_STATE/services/$type/$service" "$STUB_STATE/docker/containers/dokku.$type.$service"
}

service_networks() {
  cat "$STUB_STATE/services/$1/$2/post-create-network" 2>/dev/null || true
}

container_on_network() {
  [[ -f "$STUB_STATE/docker/containers/dokku.$1.$2/libredb-studio" ]]
}

network_exists() {
  [[ -f "$STUB_STATE/docker/networks/libredb-studio" ]]
}

# The state libredb-studio:install leaves: the app, its property, the network.
install_studio() {
  mkdir -p "$STUB_STATE/apps/libredb-studio" "$STUB_STATE/props/_libredb-studio/--global"
  echo "libredb-studio" >"$STUB_STATE/props/_libredb-studio/--global/app"
  touch "$STUB_STATE/docker/networks/libredb-studio"
}

studio_app_property() {
  cat "$STUB_STATE/props/_libredb-studio/--global/app" 2>/dev/null || true
}

# Prints the line number of the first call log line that matches a pattern.
call_line() {
  grep -n -m1 -- "$1" "$STUB_STATE/calls.log" | cut -d: -f1
}

entry_count() {
  find "$ENTRIES_DIR" -name '*.json' | wc -l
}
