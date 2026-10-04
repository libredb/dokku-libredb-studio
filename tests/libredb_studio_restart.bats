#!/usr/bin/env bats

load 'test_helper'

setup_file() {
  load 'test_helper'
  install_studio
  SERVICE="ltrestart${RANDOM}"
  export SERVICE
  dokku postgres:create "$SERVICE"
}

teardown_file() {
  load 'test_helper'
  destroy_service postgres "$SERVICE"
  remove_studio
}

query_ok() {
  local jar="${BATS_TEST_TMPDIR}/jar"
  studio_login "$jar" >/dev/null &&
    studio_query "$jar" "$(seed_id postgres "$SERVICE")" "SELECT 1 AS ok" | grep -q '"ok"'
}

@test "the service stays reachable after postgres:restart" {
  wait_for 120 studio_curl -o /dev/null http://127.0.0.1/api/db/health
  dokku postgres:restart "$SERVICE"
  wait_for 60 query_ok
}

@test "the service stays reachable when its container is made again" {
  # Start replaces a container that is gone: the new one is placed by the
  # service's post-create-network property, not by anything this plugin runs
  docker container rm --force "dokku.postgres.$SERVICE"
  dokku postgres:start "$SERVICE"
  docker container inspect --format '{{json .NetworkSettings.Networks}}' "dokku.postgres.$SERVICE" |
    jq -e 'has("libredb-studio")'
  wait_for 60 query_ok
}

@test "the service stays reachable after Studio is rebuilt" {
  dokku ps:rebuild "$STUDIO_APP"
  wait_for 120 studio_curl -o /dev/null http://127.0.0.1/api/db/health
  wait_for 60 query_ok
}
