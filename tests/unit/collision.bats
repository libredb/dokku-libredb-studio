#!/usr/bin/env bats
# dokku-datastore turns underscores into dashes for a service's DNS name and
# keeps the case, while DNS ignores case. Two services can therefore share one
# alias on the shared network, and Docker would answer with either container.

load 'test_helper'
bats_require_minimum_version 1.5.0

setup() {
  setup_sandbox
  install_studio
}

@test "a service whose DNS name another service holds is refused, naming both" {
  add_service postgres a_b
  add_service postgres a-b
  plugin_call fn-libredb-studio-add-service postgres a_b

  run plugin_call fn-libredb-studio-add-service postgres a-b
  [ "$status" -ne 0 ]
  [[ "$output" == *"a-b"* ]]
  [[ "$output" == *"a_b"* ]]
  [[ "$output" == *"dokku-postgres-a-b"* ]]
  [ "$(entry_count)" -eq 1 ]
  [ -z "$(service_networks postgres a-b)" ]
  run ! container_on_network postgres a-b
  container_on_network postgres a_b
}

@test "DNS names that differ only in case collide" {
  add_service postgres mydb
  add_service postgres MyDB
  plugin_call fn-libredb-studio-add-service postgres mydb

  run plugin_call fn-libredb-studio-add-service postgres MyDB
  [ "$status" -ne 0 ]
  [[ "$output" == *"MyDB"* ]]
  [ "$(entry_count)" -eq 1 ]
  run ! container_on_network postgres MyDB
}

@test "the same DNS name in two datastore types does not collide" {
  add_service postgres shared
  add_service redis shared

  run plugin_call fn-libredb-studio-sync
  [ "$status" -eq 0 ]
  [ "$(entry_count)" -eq 2 ]
}

@test "sync keeps the service that already holds the name and reports the other" {
  add_service postgres a-b
  plugin_call fn-libredb-studio-sync
  add_service postgres a_b

  run plugin_call fn-libredb-studio-sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"postgres:a_b"* ]]
  [ "$(entry_count)" -eq 1 ]
  [ "$(jq -r '.connections[0].name' "$SEED_FILE")" = "a-b (postgres)" ]
  container_on_network postgres a-b
  run ! container_on_network postgres a_b
}

@test "a refused service connects once the other one is gone" {
  add_service postgres a_b
  add_service postgres a-b
  plugin_call fn-libredb-studio-add-service postgres a_b
  plugin_call fn-libredb-studio-add-service postgres a-b || true
  remove_service postgres a_b

  run plugin_call fn-libredb-studio-sync
  [ "$status" -eq 0 ]
  [ "$(jq -r '.connections[0].name' "$SEED_FILE")" = "a-b (postgres)" ]
  container_on_network postgres a-b
}
