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

@test "sync keeps a network the user set on the service" {
  dokku network:create "lt-user-net-${BATS_TEST_NUMBER}" || true
  dokku postgres:create "$SERVICE" --post-create-network "lt-user-net-${BATS_TEST_NUMBER}"
  run dokku postgres:info "$SERVICE" --post-create-network
  [[ "$output" == *"lt-user-net-${BATS_TEST_NUMBER}"* ]]
  [[ "$output" == *"libredb-studio"* ]]
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
