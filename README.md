# dokku-libredb-studio

A [Dokku](https://dokku.com) plugin that runs [LibreDB Studio](https://github.com/libredb/libredb-studio), a web database IDE, already connected to the datastore services on the host.
Create a database with `dokku postgres:create`, and it appears in Studio for admins within a minute, with no copying of credentials and no restart.

## Requirements

- dokku 0.35.0+
- one or more of the official datastore plugins at 2.0.0 or later, which run on [dokku-datastore](https://github.com/dokku/dokku-datastore): `postgres`, `mysql`, `mariadb`, `mongo`, `redis`
- `jq`, which dokku itself depends on

## Installation

```shell
# on the Dokku host
sudo dokku plugin:install https://github.com/libredb/dokku-libredb-studio.git
dokku libredb-studio:install
```

`libredb-studio:install` creates the app `libredb-studio`, deploys `ghcr.io/libredb/libredb-studio:0.17.0`, connects every existing service and prints the admin email and a generated password.
The password is shown once; read it again with `dokku config:get libredb-studio ADMIN_PASSWORD`.

The login cookie is Secure, so sign-in needs https:

```shell
dokku letsencrypt:enable libredb-studio
```

On a trusted network only, plain http can be allowed instead, either with `--allow-http` at install or later with `dokku config:set libredb-studio AUTH_COOKIE_SECURE=false`.

## Commands

```
libredb-studio:info                       # Shows the Studio app, its network and the connections it is given
libredb-studio:install [<app>] [flags]    # Creates and deploys the Studio app and connects it to every datastore service
libredb-studio:sync                       # Rebuilds the connection list from every datastore service on the host
libredb-studio:uninstall                  # Detaches every datastore service from Studio and removes the connection list
```

`libredb-studio:install` flags:

- `--image <image>`: the Studio image to deploy (default: `ghcr.io/libredb/libredb-studio:0.17.0`)
- `--admin-email <email>`: the admin login (default: `admin@libredb.local`)
- `--allow-http`: set `AUTH_COOKIE_SECURE=false`, for a trusted network without TLS

## How it works

The datastore plugins fire the `service-action` trigger when a service is created and destroyed.
This plugin answers `post-create-complete` and `post-delete`, and ignores the link actions.

On create it reads `<type>:info <service> --format json`, turns the service's DSN into one Studio seed connection, and rewrites the seed file Studio reads.
Studio re-reads that file every `SEED_CACHE_TTL_MS` (60 seconds by default), so a new service shows up without a restart.

Studio is never linked to a service.
A linked service refuses `<type>:destroy` until it is unlinked, and every link restarts the app.
Instead, the service is put on a dedicated docker network, `libredb-studio`, that only Studio and the datastore services join:

- the service's `post-create-network` property gets `libredb-studio` added, so every container the datastore makes for it later (on upgrade, or on a start that replaces the container) joins the network with the service's DNS name as its alias
- the container running now is connected with `docker network connect --alias dokku-<type>-<service>`
- Studio reaches the service by that name, so an IP that changes on restart does not matter

A network you set on a service yourself is kept.
`libredb-studio:uninstall` takes `libredb-studio` back out of every service's list.

A failure in this plugin never fails your `create` or `destroy`.
It prints a warning, and `dokku libredb-studio:sync` retries.

## Security

Every account a dokku datastore hands out is the image's own, and for `postgres` that is the superuser.
So every connection this plugin writes is:

- `managed: true`: Studio keeps the credentials on the server and the connection is read-only in the UI
- `roles: ["admin"]`: users without the admin role do not see it

The seed file holds the passwords.
It lives in `/var/lib/dokku/data/libredb-studio/seed/`, a `0750` directory owned by `dokku:dokku`, and is written `0640`, the same modes dokku-datastore uses for a service's own secrets.
It is replaced by an atomic rename, so Studio never reads a half-written file.
The directory, not the file, is mounted read-only at `/run/libredb-seed`, so Studio sees each new file.

Studio runs as the image's user, `1001:1001`, with the `dokku` group added, which is what lets it read the seed file.
Its own data lives in `/var/lib/dokku/data/libredb-studio/storage/`, owned by `1001` with mode `0700`.

PostgreSQL connections use `ssl.mode: require`: each dokku postgres service has a self-signed certificate, so traffic is encrypted without verifying the certificate.

## Limitations

- One Studio app per host.
- `clickhouse`, `elasticsearch`, `couchdb` and other datastore types are skipped for now.
- Services are listed for the admin role only.
- The `service-action` trigger is implemented by dokku-datastore but not documented in dokku's plugin trigger list.

## License

MIT
