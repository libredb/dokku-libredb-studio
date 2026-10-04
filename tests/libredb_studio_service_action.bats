#!/usr/bin/env bats

load 'test_helper'

setup_file() {
  load 'test_helper'
  install_studio
}

teardown_file() {
  load 'test_helper'
  remove_studio
}

setup() {
  SERVICE="$(new_service_name)"
}

teardown() {
  chmod 0750 "$ENTRIES_DIR"
  destroy_service postgres "$SERVICE"
  destroy_service redis "$SERVICE"
}

@test "postgres:create adds a managed, admin-only entry with the service's own credentials" {
  run dokku postgres:create "$SERVICE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LibreDB Studio: $SERVICE is listed"* ]]

  local entry
  entry="$(seed_entry "$(seed_id postgres "$SERVICE")")"
  echo "$entry" | jq -e --arg host "dokku-postgres-$SERVICE" --arg db "$SERVICE" '
    .type == "postgres" and .host == $host and .port == 5432 and .database == $db
    and .user == "postgres" and .managed == true and .roles == ["admin"] and .ssl.mode == "require"'
  [ "$(echo "$entry" | jq -r .password)" = "$(dsn_password postgres "$SERVICE")" ]
}

@test "the seed file is private to the dokku user and group" {
  dokku postgres:create "$SERVICE"
  [ "$(stat -c '%U:%G %a' "$SEED_FILE")" = "dokku:dokku 640" ]
  # no temporary file is left next to it
  [ "$(find "${PLUGIN_ROOT}/seed" -mindepth 1 | wc -l)" -eq 1 ]
}

@test "postgres:create puts the service on the Studio network, now and for later containers" {
  dokku postgres:create "$SERVICE"
  run dokku postgres:info "$SERVICE" --post-create-network
  [[ "$output" == *"libredb-studio"* ]]
  docker container inspect --format '{{json .NetworkSettings.Networks}}' "dokku.postgres.$SERVICE" |
    jq -e --arg alias "dokku-postgres-$SERVICE" '.["libredb-studio"].Aliases | index($alias) != null'
}

@test "postgres:create does not link Studio to the service" {
  dokku postgres:create "$SERVICE"
  run dokku postgres:links "$SERVICE"
  [[ "$output" != *"$STUDIO_APP"* ]]
}

@test "postgres:destroy succeeds and removes the entry, and the file when it was the last" {
  dokku postgres:create "$SERVICE"
  run dokku --force postgres:destroy "$SERVICE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LibreDB Studio: $SERVICE is no longer listed"* ]]
  if [ -f "$SEED_FILE" ]; then
    [ -z "$(seed_entry "$(seed_id postgres "$SERVICE")")" ]
  fi
}

@test "redis:create adds host, port and password fields and no connection string" {
  dokku redis:create "$SERVICE"
  local entry
  entry="$(seed_entry "$(seed_id redis "$SERVICE")")"
  echo "$entry" | jq -e --arg host "dokku-redis-$SERVICE" '
    .type == "redis" and .host == $host and .port == 6379 and (.password | length > 0)
    and (has("connectionString") | not) and (has("database") | not)'
}

@test "a failure in the plugin does not fail the user's create" {
  # the hook runs as the dokku user, which cannot write here now
  chmod 0550 "$ENTRIES_DIR"
  run dokku postgres:create "$SERVICE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not update the connection for postgres service $SERVICE"* ]]
  dokku postgres:exists "$SERVICE"

  chmod 0750 "$ENTRIES_DIR"
  run dokku libredb-studio:sync
  [ "$status" -eq 0 ]
  [ -n "$(seed_entry "$(seed_id postgres "$SERVICE")")" ]
}

@test "an unsupported datastore type is skipped without an error" {
  run dokku plugin:trigger service-action post-create-complete clickhouse "$SERVICE"
  [ "$status" -eq 0 ]
  [ ! -f "${ENTRIES_DIR}/$(seed_id clickhouse "$SERVICE").json" ]
}

@test "Studio lists a new service and an admin queries it, without a Studio restart" {
  local jar="${BATS_TEST_TMPDIR}/jar" before
  wait_for 120 studio_curl -o /dev/null http://127.0.0.1/api/db/health
  before="$(studio_container_ids)"
  studio_login "$jar"

  dokku postgres:create "$SERVICE"
  wait_for 30 studio_lists "$jar" "$(seed_id postgres "$SERVICE")"
  run wait_for 60 studio_query "$jar" "$(seed_id postgres "$SERVICE")" "SELECT 1 AS ok"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok"'* ]]
  [ "$(studio_container_ids)" = "$before" ]
}

@test "an admin runs PING on a new redis service through Studio" {
  local jar="${BATS_TEST_TMPDIR}/jar"
  wait_for 120 studio_curl -o /dev/null http://127.0.0.1/api/db/health
  studio_login "$jar"
  dokku redis:create "$SERVICE"
  run wait_for 60 studio_query "$jar" "$(seed_id redis "$SERVICE")" "PING"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PONG"* ]]
}
