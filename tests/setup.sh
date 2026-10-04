#!/usr/bin/env bash
# Run inside the dokku container. Installs the pinned postgres and redis
# datastore plugins, then this plugin from the bind-mounted /plugin-src tree.
set -euo pipefail

PLUGIN_SRC="${PLUGIN_SRC:-/plugin-src}"
POSTGRES_PLUGIN_VERSION="${POSTGRES_PLUGIN_VERSION:-2.2.0}"
REDIS_PLUGIN_VERSION="${REDIS_PLUGIN_VERSION:-2.2.0}"

log() { echo "-----> $*"; }

for plugin in postgres:"$POSTGRES_PLUGIN_VERSION" redis:"$REDIS_PLUGIN_VERSION"; do
  name="${plugin%%:*}"
  version="${plugin#*:}"
  if ! dokku plugin:installed "$name"; then
    log "Installing dokku-$name $version"
    dokku plugin:install "https://github.com/dokku/dokku-$name.git" --committish "$version" --name "$name"
  fi
done

if dokku plugin:installed libredb-studio; then
  log "libredb-studio plugin already installed; uninstalling first"
  dokku plugin:uninstall libredb-studio
fi

# plugin:install names the plugin after the basename of the source, so the
# bind-mounted tree is staged at a path whose basename is the plugin name
log "Staging plugin source at /tmp/libredb-studio"
rm -rf /tmp/libredb-studio
cp -r "${PLUGIN_SRC}" /tmp/libredb-studio

log "Installing libredb-studio plugin from /tmp/libredb-studio"
dokku plugin:install "file:///tmp/libredb-studio"

log "Setup complete"
