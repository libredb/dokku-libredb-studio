#!/usr/bin/env bats
# The shared network must exist for as long as a service's post-create-network
# property names it, because dokku-datastore fails to create a container
# whose listed network is missing.

load 'test_helper'
bats_require_minimum_version 1.5.0

setup() {
  setup_sandbox
}

@test "the install trigger creates the network and the lock file, and runs again cleanly" {
  run "$REPO_ROOT/install"
  [ "$status" -eq 0 ]
  network_exists
  [ "$(stat -c '%a' "$LOCK_FILE")" = "640" ]

  run "$REPO_ROOT/install"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'docker network create' "$STUB_STATE/calls.log")" -eq 1 ]
}

@test "attaching a service recreates a network deleted by hand before it writes the property" {
  install_studio
  rm "$STUB_STATE/docker/networks/libredb-studio"
  add_service postgres one

  run plugin_call fn-libredb-studio-add-service postgres one
  [ "$status" -eq 0 ]
  network_exists
  [ "$(service_networks postgres one)" = "libredb-studio" ]
  container_on_network postgres one
  [ "$(call_line 'docker network create')" -lt "$(call_line 'datastore postgres:set')" ]
  # the running Studio container is not on a network created after it
  [[ "$output" == *"dokku ps:rebuild libredb-studio"* ]]
}

@test "attaching a service leaves its property alone when the network cannot be created" {
  install_studio
  rm "$STUB_STATE/docker/networks/libredb-studio"
  touch "$STUB_STATE/network-create-fails"
  add_service postgres one

  run plugin_call fn-libredb-studio-add-service postgres one
  [ "$status" -ne 0 ]
  [ -z "$(service_networks postgres one)" ]
  [ "$(entry_count)" -eq 0 ]
}

@test "plugin:uninstall takes the network out of every service before it removes the network" {
  install_studio
  add_service postgres one
  add_service redis two
  echo "mine" >"$STUB_STATE/services/postgres/one/post-create-network"
  plugin_call fn-libredb-studio-sync
  rm -r "$STUB_STATE/apps/libredb-studio"
  : >"$STUB_STATE/calls.log"

  run "$REPO_ROOT/uninstall" libredb-studio
  [ "$status" -eq 0 ]
  [ "$(service_networks postgres one)" = "mine" ]
  [ -z "$(service_networks redis two)" ]
  run ! container_on_network postgres one
  run ! container_on_network redis two
  run ! network_exists
  [ "$(grep -n 'datastore .*:set' "$STUB_STATE/calls.log" | tail -n1 | cut -d: -f1)" -lt "$(call_line 'docker network rm')" ]
  # the superuser passwords do not stay on disk
  [ ! -e "$ROOT/entries" ]
  [ ! -e "$ROOT/seed" ]
  [ -z "$(studio_app_property)" ]
}

@test "plugin:uninstall of another plugin changes nothing" {
  install_studio
  add_service postgres one
  plugin_call fn-libredb-studio-sync

  run "$REPO_ROOT/uninstall" postgres
  [ "$status" -eq 0 ]
  [ "$(service_networks postgres one)" = "libredb-studio" ]
  network_exists
  [ -f "$SEED_FILE" ]
}

@test "plugin:uninstall keeps the network while the Studio app still uses it" {
  install_studio
  add_service postgres one
  plugin_call fn-libredb-studio-sync

  run "$REPO_ROOT/uninstall" libredb-studio
  [ "$status" -eq 0 ]
  [ -z "$(service_networks postgres one)" ]
  network_exists
  [[ "$output" == *"dokku apps:destroy libredb-studio"* ]]
}

@test "plugin:uninstall fails and keeps the network when a service cannot be detached" {
  install_studio
  add_service postgres one
  add_service postgres two
  plugin_call fn-libredb-studio-sync
  rm -r "$STUB_STATE/apps/libredb-studio"
  touch "$STUB_STATE/services/postgres/two/set-fails"

  run "$REPO_ROOT/uninstall" libredb-studio
  [ "$status" -ne 0 ]
  [[ "$output" == *"postgres:two"* ]]
  [ "$(service_networks postgres two)" = "libredb-studio" ]
  network_exists
}

@test "destroying the Studio app detaches every service and then removes the network" {
  install_studio
  add_service postgres one
  plugin_call fn-libredb-studio-sync
  rm -r "$STUB_STATE/apps/libredb-studio"
  : >"$STUB_STATE/calls.log"

  run "$REPO_ROOT/post-delete" libredb-studio
  [ "$status" -eq 0 ]
  [ -z "$(service_networks postgres one)" ]
  run ! container_on_network postgres one
  run ! network_exists
  [ ! -f "$SEED_FILE" ]
  [ "$(entry_count)" -eq 0 ]
  [ -z "$(studio_app_property)" ]
  [ "$(call_line 'datastore postgres:set')" -lt "$(call_line 'docker network rm')" ]
}

@test "destroying the Studio app takes its retired container off the network before it removes the network" {
  install_studio
  add_service postgres one
  plugin_call fn-libredb-studio-sync
  rm -r "$STUB_STATE/apps/libredb-studio"
  # a deploy keeps the container it replaced running until it is retired, and
  # scheduler-docker-local removes it in its own post-delete, after this one
  add_app_container libredb-studio libredb-studio.web.1.1791127786
  : >"$STUB_STATE/calls.log"

  run "$REPO_ROOT/post-delete" libredb-studio
  [ "$status" -eq 0 ]
  run ! network_exists
  [ ! -f "$STUB_STATE/docker/containers/libredb-studio.web.1.1791127786/libredb-studio" ]
  [ "$(call_line 'docker network disconnect libredb-studio libredb-studio.web.1.1791127786')" -lt "$(call_line 'docker network rm')" ]
}

@test "destroying the Studio app leaves another app's container on the network, and fails naming the way out" {
  install_studio
  add_service postgres one
  plugin_call fn-libredb-studio-sync
  rm -r "$STUB_STATE/apps/libredb-studio"
  add_app_container other-app other-app.web.1

  run "$REPO_ROOT/post-delete" libredb-studio
  [ "$status" -ne 0 ]
  [[ "$output" == *"dokku --force network:destroy libredb-studio"* ]]
  [ -f "$STUB_STATE/docker/containers/other-app.web.1/libredb-studio" ]
  network_exists
  [ -z "$(service_networks postgres one)" ]
}

@test "destroying another app leaves Studio alone" {
  install_studio
  add_service postgres one
  plugin_call fn-libredb-studio-sync

  run "$REPO_ROOT/post-delete" other-app
  [ "$status" -eq 0 ]
  [ "$(service_networks postgres one)" = "libredb-studio" ]
  network_exists
  [ "$(studio_app_property)" = "libredb-studio" ]
}

@test "libredb-studio:sync recreates a missing network instead of failing" {
  install_studio
  rm "$STUB_STATE/docker/networks/libredb-studio"
  add_service postgres one
  echo "libredb-studio" >"$STUB_STATE/services/postgres/one/post-create-network"

  run command_call cmd-libredb-studio-sync
  [ "$status" -eq 0 ]
  network_exists
  container_on_network postgres one
}

@test "libredb-studio:uninstall detaches every service and keeps the network the app still uses" {
  install_studio
  add_service postgres one
  plugin_call fn-libredb-studio-sync

  run command_call cmd-libredb-studio-uninstall
  [ "$status" -eq 0 ]
  [ -z "$(service_networks postgres one)" ]
  [ ! -f "$SEED_FILE" ]
  network_exists
  [[ "$output" == *"dokku --force network:destroy libredb-studio"* ]]
}
