#!/usr/bin/env bats
# LibreDB Studio 0.18.0 and later keep their accounts in the storage directory,
# which outlives the app, and take ADMIN_EMAIL and ADMIN_PASSWORD only on the
# first start. A reinstall must therefore sign in with the login of the first
# install, never with a new one that Studio would ignore.

load 'test_helper'
bats_require_minimum_version 1.5.0

setup() {
  setup_sandbox
  LOGIN_FILE="$ROOT/login.env"
}

@test "a first install prints a new login and keeps nothing before its deploy" {
  run plugin_call fn-libredb-studio-login "" "first-password"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "admin@libredb.local" ]
  [ "${lines[1]}" = "first-password" ]
  [ ! -e "$LOGIN_FILE" ]
}

@test "an email given on the first install is the login's email" {
  run plugin_call fn-libredb-studio-login "ops@example.test" "first-password"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "ops@example.test" ]
}

@test "keeping a new login writes the file, readable by its owner only" {
  run plugin_call fn-libredb-studio-keep-login "ops@example.test" "first-password"
  [ "$status" -eq 0 ]
  [ "$(stat -c '%a' "$LOGIN_FILE")" = "600" ]
  [ "$(cat "$LOGIN_FILE")" = "$(printf 'admin_email=ops@example.test\nadmin_password=first-password')" ]
}

@test "a reinstall signs in with the kept login and ignores the new password" {
  printf 'admin_email=ops@example.test\nadmin_password=kept-password\n' >"$LOGIN_FILE"

  run plugin_call fn-libredb-studio-login "" "new-password"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "ops@example.test" ]
  [ "${lines[1]}" = "kept-password" ]
  grep -qx 'admin_password=kept-password' "$LOGIN_FILE"
}

@test "a reinstall that names the kept admin email is accepted" {
  printf 'admin_email=ops@example.test\nadmin_password=kept-password\n' >"$LOGIN_FILE"

  run plugin_call fn-libredb-studio-login "ops@example.test" "new-password"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "kept-password" ]
}

@test "a reinstall that asks for another admin email fails and names the kept one" {
  printf 'admin_email=ops@example.test\nadmin_password=kept-password\n' >"$LOGIN_FILE"

  run plugin_call fn-libredb-studio-login "other@example.test" "new-password"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ops@example.test"* ]]
  [[ "$output" != *"kept-password"* ]]
  grep -qx 'admin_email=ops@example.test' "$LOGIN_FILE"
}

@test "an incomplete login file fails without printing a password" {
  printf 'admin_password=kept-password\n' >"$LOGIN_FILE"

  run plugin_call fn-libredb-studio-login "" "new-password"
  [ "$status" -ne 0 ]
  [[ "$output" == *"$LOGIN_FILE"* ]]
  [[ "$output" != *"kept-password"* ]]
  [[ "$output" != *"new-password"* ]]
}

@test "a login file with a second password line fails without printing either" {
  printf 'admin_email=ops@example.test\nadmin_password=kept-password\nadmin_password=other-password\n' >"$LOGIN_FILE"

  run plugin_call fn-libredb-studio-login "" "new-password"
  [ "$status" -ne 0 ]
  [[ "$output" == *"$LOGIN_FILE"* ]]
  [[ "$output" != *"kept-password"* ]]
  [[ "$output" != *"other-password"* ]]
}

@test "a first install without a generated password fails" {
  run plugin_call fn-libredb-studio-login "" ""
  [ "$status" -ne 0 ]
  [ ! -e "$LOGIN_FILE" ]
}

@test "an admin email with a line break is refused" {
  run plugin_call fn-libredb-studio-login $'ops@example.test\nadmin_password=injected' "first-password"
  [ "$status" -ne 0 ]
  [[ "$output" != *"first-password"* ]]
}
