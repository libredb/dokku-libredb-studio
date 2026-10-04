#!/usr/bin/env bats

load 'test_helper'

setup_file() {
  load 'test_helper'
  # a service that exists before Studio does
  EARLY_SERVICE="ltearly${RANDOM}"
  export EARLY_SERVICE
  dokku postgres:create "$EARLY_SERVICE"
  install_studio
}

teardown_file() {
  load 'test_helper'
  destroy_service postgres "$EARLY_SERVICE"
  remove_studio
}

@test "install creates the app on the Studio network with the image's user and the dokku group" {
  run dokku network:report "$STUDIO_APP" --network-attach-post-create
  [ "$status" -eq 0 ]
  [[ "$output" == *"libredb-studio"* ]]

  run dokku docker-options:report "$STUDIO_APP" --docker-options-deploy
  [[ "$output" == *"--user 1001:1001"* ]]
  [[ "$output" == *"--group-add $(getent group dokku | cut -d: -f3)"* ]]
}

@test "install mounts the data directory and the seed directory read-only" {
  run dokku storage:list "$STUDIO_APP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/storage:/app/data"* ]]
  [[ "$output" == *"/seed:/run/libredb-seed:ro"* ]]
}

@test "install sets the login and storage configuration, with a JWT secret of 64 characters" {
  [ "$(dokku config:get "$STUDIO_APP" NEXT_PUBLIC_AUTH_PROVIDER)" = "local" ]
  [ "$(dokku config:get "$STUDIO_APP" STORAGE_PROVIDER)" = "sqlite" ]
  [ "$(dokku config:get "$STUDIO_APP" SEED_CONFIG_PATH)" = "/run/libredb-seed/connections.json" ]
  [ "$(dokku config:get "$STUDIO_APP" AUTH_COOKIE_SECURE)" = "false" ]
  [ "$(dokku config:get "$STUDIO_APP" JWT_SECRET | tr -d '\n' | wc -c)" -eq 64 ]
  [ -n "$(dokku config:get "$STUDIO_APP" ADMIN_PASSWORD)" ]
}

@test "install connects a service that existed before it" {
  local id
  id="$(seed_id postgres "$EARLY_SERVICE")"
  run seed_entry "$id"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  echo "$output" | jq -e '.managed == true and .roles == ["admin"] and .type == "postgres" and .user == "postgres"'
}

@test "Studio answers its health check" {
  wait_for 120 studio_curl -o /dev/null http://127.0.0.1/api/db/health
}

@test "a second install is refused" {
  run dokku libredb-studio:install
  [ "$status" -ne 0 ]
  [[ "$output" == *"already installed as app $STUDIO_APP"* ]]
}

@test "an admin runs a query on the pre-existing service through Studio" {
  local jar="${BATS_TEST_TMPDIR}/jar"
  wait_for 120 studio_curl -o /dev/null http://127.0.0.1/api/db/health
  studio_login "$jar"
  run wait_for 60 studio_query "$jar" "$(seed_id postgres "$EARLY_SERVICE")" "SELECT 1 AS ok"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ok"'* ]]
}
