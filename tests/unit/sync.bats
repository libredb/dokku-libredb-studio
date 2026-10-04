#!/usr/bin/env bats

load 'test_helper'
bats_require_minimum_version 1.5.0

setup() {
  setup_sandbox
  install_studio
}

teardown() {
  if [[ -n "$LOCK_HOLDER" ]]; then
    kill "$LOCK_HOLDER" 2>/dev/null || true
    wait "$LOCK_HOLDER" 2>/dev/null || true
  fi
}

@test "sync connects every supported service and skips the others" {
  add_service postgres one
  add_service redis two
  mkdir -p "$STUB_STATE/services/clickhouse/three"

  run plugin_call fn-libredb-studio-sync
  [ "$status" -eq 0 ]
  [ "$(jq '.connections | length' "$SEED_FILE")" -eq 2 ]
  [ "$(jq -r '.connections[] | select(.type == "redis") | has("database")' "$SEED_FILE")" = "false" ]
}

@test "a failed service listing aborts sync and deletes nothing" {
  add_service postgres one
  plugin_call fn-libredb-studio-sync
  local before
  before="$(cat "$SEED_FILE")"
  touch "$STUB_STATE/service-list-fails"
  : >"$STUB_STATE/calls.log"

  run plugin_call fn-libredb-studio-sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"Could not list the datastore services"* ]]
  [ "$(entry_count)" -eq 1 ]
  [ "$(cat "$SEED_FILE")" = "$before" ]
  run ! grep -q 'datastore' "$STUB_STATE/calls.log"
}

@test "a failed service listing makes libredb-studio:sync exit non-zero" {
  touch "$STUB_STATE/service-list-fails"
  run command_call cmd-libredb-studio-sync
  [ "$status" -ne 0 ]
}

@test "a failed service listing makes libredb-studio:uninstall detach nothing" {
  add_service postgres one
  plugin_call fn-libredb-studio-sync
  touch "$STUB_STATE/service-list-fails"

  run command_call cmd-libredb-studio-uninstall
  [ "$status" -ne 0 ]
  [ "$(service_networks postgres one)" = "libredb-studio" ]
  [ -f "$SEED_FILE" ]
}

@test "a listing with no services removes every stale entry and the seed file" {
  add_service postgres one
  plugin_call fn-libredb-studio-sync
  remove_service postgres one

  run plugin_call fn-libredb-studio-sync
  [ "$status" -eq 0 ]
  [ "$(entry_count)" -eq 0 ]
  [ ! -f "$SEED_FILE" ]
}

@test "sync waits for the lock, and deletes nothing when it cannot get it" {
  add_service postgres one
  plugin_call fn-libredb-studio-sync
  remove_service postgres one
  flock "$LOCK_FILE" sleep 30 &
  LOCK_HOLDER=$!
  sleep 0.5

  run plugin_call fn-libredb-studio-sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"Timed out waiting for"* ]]
  [ "$(entry_count)" -eq 1 ]
}

@test "sync is idempotent and adds the network to a service only once" {
  add_service postgres one
  echo "mine" >"$STUB_STATE/services/postgres/one/post-create-network"

  plugin_call fn-libredb-studio-sync
  local before
  before="$(cat "$SEED_FILE")"
  run plugin_call fn-libredb-studio-sync
  [ "$status" -eq 0 ]
  [ "$(cat "$SEED_FILE")" = "$before" ]
  [ "$(service_networks postgres one)" = "mine,libredb-studio" ]
}
