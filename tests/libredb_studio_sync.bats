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
  destroy_service postgres "$SERVICE"
}

@test "sync is idempotent" {
  dokku postgres:create "$SERVICE"
  local before
  before="$(cat "$SEED_FILE")"
  run dokku libredb-studio:sync
  [ "$status" -eq 0 ]
  run dokku libredb-studio:sync
  [ "$status" -eq 0 ]
  [ "$(cat "$SEED_FILE")" = "$before" ]
  run dokku postgres:info "$SERVICE" --post-create-network
  [ "$(echo "$output" | tr ',' '\n' | grep -c '^libredb-studio$')" -eq 1 ]
}

@test "sync keeps a network the user set on the service and adds its own once" {
  local user_net="lt-user-net-${BATS_TEST_NUMBER}"
  dokku network:exists "$user_net" || dokku network:create "$user_net"
  dokku postgres:create "$SERVICE" --post-create-network "$user_net"
  run dokku libredb-studio:sync
  [ "$status" -eq 0 ]
  run dokku libredb-studio:sync
  [ "$status" -eq 0 ]
  run dokku postgres:info "$SERVICE" --post-create-network
  [ "$(echo "$output" | tr ',' '\n' | grep -c "^${user_net}\$")" -eq 1 ]
  [ "$(echo "$output" | tr ',' '\n' | grep -c '^libredb-studio$')" -eq 1 ]
}

@test "a failed service listing aborts sync and keeps every entry" {
  dokku postgres:create "$SERVICE"
  local before
  before="$(cat "$SEED_FILE")"
  install_broken_service_list
  run dokku libredb-studio:sync
  remove_broken_service_list
  [ "$status" -ne 0 ]
  [[ "$output" == *"Could not list the datastore services"* ]]
  [ "$(cat "$SEED_FILE")" = "$before" ]
}

@test "a service whose DNS name another service holds is refused by name, and its create still succeeds" {
  local first="lt_dns_${BATS_TEST_NUMBER}" second="lt-dns-${BATS_TEST_NUMBER}"
  dokku postgres:create "$first"
  run dokku postgres:create "$second"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$second was not connected"* ]]
  [[ "$output" == *"$first (postgres)"* ]]
  [ "$(jq --arg h "dokku-postgres-$second" '[.connections[] | select(.host == $h)] | length' "$SEED_FILE")" -eq 1 ]
  [ "$(docker container inspect --format '{{json .NetworkSettings.Networks}}' "dokku.postgres.$second" | jq 'has("libredb-studio")')" = "false" ]
  destroy_service postgres "$second"
  destroy_service postgres "$first"
}

@test "sync drops an entry whose service is gone" {
  local stale="${ENTRIES_DIR}/dokku-postgres-gone.json"
  echo '{"id":"dokku-postgres-gone","name":"gone","type":"postgres","roles":["admin"]}' >"$stale"
  chown dokku:dokku "$stale"
  run dokku libredb-studio:sync
  [ "$status" -eq 0 ]
  [ ! -f "$stale" ]
}

@test "info lists connections without credentials" {
  dokku postgres:create "$SERVICE"
  run dokku libredb-studio:info
  [ "$status" -eq 0 ]
  [[ "$output" == *"dokku-postgres-$SERVICE"* ]]
  [[ "$output" != *"$(dsn_password postgres "$SERVICE")"* ]]
}
