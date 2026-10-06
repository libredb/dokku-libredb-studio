# dokku-libredb-studio

A [Dokku](https://dokku.com) plugin that runs [LibreDB Studio](https://github.com/libredb/libredb-studio), a web database IDE, already connected to the datastore services on the host.
Create a database with `dokku postgres:create`, and it appears in Studio for admins within a minute, with no copying of credentials and no restart.

## Requirements

- dokku 0.35.20+, the oldest version CI tests
- one or more of the official datastore plugins at 2.0.0 or later, which run on [dokku-datastore](https://github.com/dokku/dokku-datastore): `postgres`, `mysql`, `mariadb`, `mongo`, `redis`
- `jq`, which dokku itself depends on

## Installation

```shell
# on the Dokku host
sudo dokku plugin:install https://github.com/libredb/dokku-libredb-studio.git
dokku libredb-studio:install
```

`plugin:install` needs a running Docker daemon, because its install trigger creates the `libredb-studio` network.

`libredb-studio:install` creates the app `libredb-studio`, deploys `ghcr.io/libredb/libredb-studio:0.18.0`, connects every existing service and prints the admin email and a generated password.
Read it again with `dokku config:get libredb-studio ADMIN_PASSWORD`.
Studio 0.18.0 and later store that login in their own data on their first start, and take the admin password from the app's environment only then, so change it in Studio after that.
The plugin keeps the login of the first install in `/var/lib/dokku/data/libredb-studio/login.env`, so a later `libredb-studio:install`, after `dokku apps:destroy libredb-studio` for example, signs in with the same login and prints it again.
A later install with another `--admin-email` fails, because a login is already kept.

If the admin password is lost, run `dokku config:set libredb-studio ADMIN_PASSWORD_RESET=true`, sign in with the password `dokku config:get libredb-studio ADMIN_PASSWORD` prints, then run `dokku config:unset libredb-studio ADMIN_PASSWORD_RESET`.
While it is set, every restart applies the reset again, which also enables the admin account, removes its passkeys and, unless `ADMIN_TOTP_SECRET` is set, its second factor, and ends its sessions.

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

- `--image <image>`: the Studio image to deploy (default: `ghcr.io/libredb/libredb-studio:0.18.0`)
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

dokku-datastore cannot make a container whose `post-create-network` names a missing network, so the plugin keeps `libredb-studio` in existence for as long as any service names it:

- `plugin:install` creates it, and every attach creates it again first if it is gone
- `libredb-studio:uninstall`, `plugin:uninstall libredb-studio` and destroying the Studio app first take `libredb-studio` out of every service's list, and only then remove the network
- if a service cannot be detached, the command fails and the network is kept, so the service's next `upgrade` or recreated container still works

If you remove the network by hand anyway, run `dokku libredb-studio:sync`: it creates the network again and puts every service back on it.
Then put Studio back on it with `dokku ps:rebuild libredb-studio`.

The service list comes from dokku-datastore's `service-list` trigger.
If that listing fails, `sync` and `uninstall` stop with an error and change nothing, so a broken datastore plugin never makes Studio forget its connections.

A failure in this plugin never fails your `create` or `destroy`.
It prints a warning, and `dokku libredb-studio:sync` retries.

### Two services with the same DNS name

dokku-datastore turns `_` and `.` in a service name into `-` for its DNS name and keeps the case, while DNS ignores case.
So `my_db` and `my-db`, or `MyDB` and `mydb`, get the same name on the shared network, and Docker would answer with either container.
The plugin refuses the second one: it is not put on the network and gets no connection, and the warning names both services.
The service that already holds the name keeps it.
Rename or destroy one of the two, then run `dokku libredb-studio:sync`.

## Uninstalling

```shell
dokku libredb-studio:uninstall                # detach every service, remove the connection list, keep the app
dokku apps:destroy libredb-studio             # or: destroy the app, which also detaches every service and removes the network
sudo dokku plugin:uninstall libredb-studio    # detach every service, delete the stored connection files, remove the network
```

`plugin:uninstall` keeps the network while the Studio app still exists, because the app is attached to it, and prints the two commands that remove both.
Studio's own data in `/var/lib/dokku/data/libredb-studio/storage/` is always kept, and so is `login.env` beside it, because that data still holds the admin account the login signs in to.
To forget Studio entirely, remove both, with the glob expanded as root: `sudo sh -c 'rm -rf /var/lib/dokku/data/libredb-studio/storage/* /var/lib/dokku/data/libredb-studio/login.env'`.
Never remove `login.env` alone: the next install would print a new password that Studio's kept account ignores, and only the `ADMIN_PASSWORD_RESET` steps above would let the admin in again.

If one service is permanently broken and cannot be detached, each of these commands fails and names it.
Fix that service, or destroy it with `dokku <type>:destroy <service>`, or take `libredb-studio` out of its list by hand:

```shell
dokku <type>:info <service> --post-create-network                 # read the list, for example: other-net,libredb-studio
dokku <type>:set <service> post-create-network other-net          # write it back without libredb-studio
dokku <type>:set <service> post-create-network                    # or clear it, when libredb-studio was the only entry
```

Then run the command again; after a failed `apps:destroy` the app is already gone, so run `dokku libredb-studio:uninstall` instead.

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
The login of the first install is kept in `/var/lib/dokku/data/libredb-studio/login.env`, owned by `dokku` with mode `0600`.

`libredb-studio:install` passes the generated `JWT_SECRET` and `ADMIN_PASSWORD` to `dokku config:set` as arguments, as every `config:set` does, so a local user can see them in the process list while that one command runs.
Its output is discarded, so they are not printed with the rest of the configuration.
Running `dokku config:set libredb-studio ADMIN_PASSWORD=... JWT_SECRET=...` again to rotate them passes the new values as process arguments too, with the same exposure while it runs.
On a host shared with untrusted local users, mount `/proc` with `hidepid=2`, so a user sees only their own processes.

PostgreSQL connections use `ssl.mode: require`: each dokku postgres service has a self-signed certificate, so traffic is encrypted without verifying the certificate.

## Limitations

- One Studio app per host.
- `clickhouse`, `elasticsearch`, `couchdb` and other datastore types are skipped for now.
- Services are listed for the admin role only.
- The `service-action` trigger is implemented by dokku-datastore but not documented in dokku's plugin trigger list.

## Development

```shell
make unit        # the stubbed suite in tests/unit: bash, bats, jq and flock, no docker
make host-lint   # shellcheck over every shell file
make setup test  # the end to end suite against dokku in docker, see tests/README.md
```

## License

MIT
