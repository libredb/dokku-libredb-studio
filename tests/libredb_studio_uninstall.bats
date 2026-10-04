#!/usr/bin/env bats

load 'test_helper'

setup() {
  install_studio
  SERVICE="$(new_service_name)"
  dokku postgres:create "$SERVICE"
}

teardown() {
  destroy_service postgres "$SERVICE"
  remove_studio
}

@test "uninstall detaches every service and removes the seed file" {
  run dokku libredb-studio:uninstall
  [ "$status" -eq 0 ]
  [ ! -f "$SEED_FILE" ]
  run dokku postgres:info "$SERVICE" --post-create-network
  [[ "$output" != *"libredb-studio"* ]]
  ! docker container inspect --format '{{json .NetworkSettings.Networks}}' "dokku.postgres.$SERVICE" |
    jq -e 'has("libredb-studio")'
}

@test "after uninstall a new service is left alone" {
  dokku libredb-studio:uninstall
  local other="${SERVICE}b"
  dokku postgres:create "$other"
  run dokku postgres:info "$other" --post-create-network
  [[ "$output" != *"libredb-studio"* ]]
  [ ! -f "$SEED_FILE" ]
  destroy_service postgres "$other"
}

@test "destroying the Studio app stops new services from being attached" {
  dokku --force apps:destroy "$STUDIO_APP"
  local other="${SERVICE}c"
  dokku postgres:create "$other"
  run dokku postgres:info "$other" --post-create-network
  [[ "$output" != *"libredb-studio"* ]]
  destroy_service postgres "$other"
}
