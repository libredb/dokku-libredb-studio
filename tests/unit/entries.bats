#!/usr/bin/env bats

load 'test_helper'
bats_require_minimum_version 1.5.0

setup() {
  setup_sandbox
  install_studio
}

@test "the create hook writes a managed, admin-only entry and the destroy hook removes the file with the last entry" {
  add_service postgres one

  run "$REPO_ROOT/scripts/service-action" post-create-complete postgres one
  [ "$status" -eq 0 ]
  jq -e '.connections[0] | .id == "dokku-postgres-one" and .host == "dokku-postgres-one" and .port == 5432
    and .user == "postgres" and .password == "secret-one" and .database == "one"
    and .managed == true and .roles == ["admin"] and .ssl.mode == "require"' "$SEED_FILE"
  [ "$(stat -c '%a' "$SEED_FILE")" = "640" ]
  [ "$(find "$ROOT/seed" -mindepth 1 | wc -l)" -eq 1 ]

  run "$REPO_ROOT/scripts/service-action" post-delete postgres one
  [ "$status" -eq 0 ]
  [ ! -f "$SEED_FILE" ]
}

@test "a service name too long for Studio's 128 character name is cut, keeping the type" {
  local long
  long="$(printf 'a%.0s' {1..200})"
  add_service postgres "$long"

  run plugin_call fn-libredb-studio-add-service postgres "$long"
  [ "$status" -eq 0 ]
  local name
  name="$(jq -r .name "$ENTRIES_DIR"/*.json)"
  [ "${#name}" -le 128 ]
  [[ "$name" == *"... (postgres)" ]]
  [ "$(jq -r '.id | length' "$ENTRIES_DIR"/*.json)" -le 64 ]
}

@test "assembly refuses an entry Studio would reject and keeps the previous file, without printing secrets" {
  add_service postgres one
  plugin_call fn-libredb-studio-sync
  local before
  before="$(cat "$SEED_FILE")"
  jq -c '.id = "dokku-postgres-bad" | .port = 0 | .password = "do-not-print"' "$ENTRIES_DIR/dokku-postgres-one.json" >"$ENTRIES_DIR/dokku-postgres-bad.json"

  run plugin_call fn-libredb-studio-assemble
  [ "$status" -ne 0 ]
  [[ "$output" == *"dokku-postgres-bad"* ]]
  [[ "$output" != *"do-not-print"* ]]
  [ "$(cat "$SEED_FILE")" = "$before" ]
}

@test "assembly refuses an entry with no roles" {
  add_service postgres one
  plugin_call fn-libredb-studio-sync
  jq -c '.roles = []' "$ENTRIES_DIR/dokku-postgres-one.json" >"$BATS_TEST_TMPDIR/e" && mv "$BATS_TEST_TMPDIR/e" "$ENTRIES_DIR/dokku-postgres-one.json"

  run plugin_call fn-libredb-studio-assemble
  [ "$status" -ne 0 ]
}

@test "the create hook never fails the user's create" {
  add_service postgres one
  touch "$STUB_STATE/services/postgres/one/set-fails"

  run "$REPO_ROOT/service-action" post-create-complete postgres one
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not update the connection for postgres service one"* ]]
}

@test "the service-action script refuses to run as a user other than dokku" {
  add_service postgres one
  DOKKU_SYSTEM_USER="lt-not-this-user" run "$REPO_ROOT/scripts/service-action" post-create-complete postgres one
  [ "$status" -ne 0 ]
  [[ "$output" == *"must run as lt-not-this-user"* ]]
  [ "$(entry_count)" -eq 0 ]
}
