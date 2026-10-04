#!/usr/bin/env bats

load 'test_helper'

@test "libredb-studio:help lists all subcommands" {
  run dokku libredb-studio:help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: dokku libredb-studio"* ]]
  [[ "$output" == *"libredb-studio:info"* ]]
  [[ "$output" == *"libredb-studio:install"* ]]
  [[ "$output" == *"libredb-studio:sync"* ]]
  [[ "$output" == *"libredb-studio:uninstall"* ]]
}

@test "dokku libredb-studio without a subcommand prints help" {
  run dokku libredb-studio
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: dokku libredb-studio"* ]]
}

@test "dokku help includes the libredb-studio summary" {
  run dokku help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Run LibreDB Studio connected to this host's datastore services"* ]]
}

@test "the install trigger creates the plugin directories with private modes" {
  [ "$(stat -c '%U:%G %a' "${PLUGIN_ROOT}/seed")" = "dokku:dokku 750" ]
  [ "$(stat -c '%U:%G %a' "${PLUGIN_ROOT}/entries")" = "dokku:dokku 750" ]
  [ "$(stat -c '%u:%g %a' "${PLUGIN_ROOT}/storage")" = "1001:1001 700" ]
}

@test "libredb-studio:sync refuses to run before install" {
  run dokku libredb-studio:sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"LibreDB Studio is not installed"* ]]
}
