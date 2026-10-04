# Test suite

There are two suites.

`tests/unit` runs the plugin's own scripts against stand-ins for dokku, docker, plugn and the datastore plugins in `tests/unit/stubs`.
It needs bash, bats 1.5 or later, jq and flock, and no docker: run it with `make unit`.
It covers the file, lock, network and listing logic, including the failure paths that are hard to cause on a real host.

The files directly under `tests/` are the end to end suite.
The bats suite runs the plugin end to end inside a docker-compose stack built from the `dokku/dokku` image.
Tests run inside the dokku container as root and call `dokku ...` directly, the way an operator would.
The datastore and Studio containers run on the host's docker daemon through the mounted socket, so the suite is Linux only.

## Running the suite locally

```shell
make setup   # build the dokku image, start it, install dokku-postgres, dokku-redis and this plugin
make test    # shellcheck, then every bats file
make clean   # stop the stack and remove its containers, network and state directory
```

Run one file with `make unit-tests UNIT_TESTS=libredb_studio_sync.bats`, or one test with `UNIT_TESTS_FILTER='sync is idempotent'`.
Pick the dokku release with `DOKKU_VERSION=0.38.31 make setup`.

The first run pulls `ghcr.io/libredb/libredb-studio:0.17.0`, `postgres` and `redis` images, a few hundred megabytes in all.
