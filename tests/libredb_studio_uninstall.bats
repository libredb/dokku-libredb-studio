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
  [ "$(docker container inspect --format '{{json .NetworkSettings.Networks}}' "dokku.postgres.$SERVICE" | jq 'has("libredb-studio")')" = "false" ]
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

@test "plugin:uninstall leaves no service naming the network, and the service can still be upgraded" {
  run dokku plugin:uninstall libredb-studio
  reinstall_plugin
  [ "$status" -eq 0 ]
  run dokku postgres:info "$SERVICE" --post-create-network
  [[ "$output" != *"libredb-studio"* ]]
  [ ! -f "$SEED_FILE" ]
  run dokku postgres:upgrade "$SERVICE"
  [ "$status" -eq 0 ]
}

@test "destroying the Studio app detaches every service and removes the network, and upgrades still work" {
  run env DOKKU_TRACE=1 dokku --force apps:destroy "$STUDIO_APP"
  # Diagnostics for the post-delete ordering: printed on fd 3, so they reach the CI log on success too.
  {
    echo "# apps:destroy status: $status"
    printf '%s\n' "$output" | grep -E "post-delete|libredb-studio|network (dis)?connect|network:destroy|container rm|Detached|Could not" | grep -v "^+ *source" | head -n 120 | sed 's/^/# /'
    echo "# containers still on the network:"
    docker network inspect libredb-studio --format '{{range .Containers}}{{.Name}} {{end}}' 2>&1 | sed 's/^/#   /'
    echo "# service property:"
    dokku postgres:info "$SERVICE" --post-create-network 2>&1 | sed 's/^/#   /'
  } >&3
  [ "$status" -eq 0 ]
  run dokku postgres:info "$SERVICE" --post-create-network
  [[ "$output" != *"libredb-studio"* ]]
  run docker network inspect libredb-studio
  [ "$status" -ne 0 ]
  run dokku postgres:upgrade "$SERVICE"
  [ "$status" -eq 0 ]
}

@test "destroying the Studio app stops new services from being attached" {
  dokku --force apps:destroy "$STUDIO_APP"
  local other="${SERVICE}c"
  dokku postgres:create "$other"
  run dokku postgres:info "$other" --post-create-network
  [[ "$output" != *"libredb-studio"* ]]
  destroy_service postgres "$other"
}
