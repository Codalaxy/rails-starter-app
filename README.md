# Rails starter

A Rails 8 application in `app/`, wrapped in the deployment shape every app in
this organisation uses: nginx in front of Puma, images built in CI, pushed to
ECR, and deployed to EC2 over SSM by the shared workflow in
[`Codalaxy/aws-infra`](https://github.com/Codalaxy/aws-infra).

The Rails app is **not** the repository root. It lives in `app/`, beside
`build/`, `deploy/` and `services/` — which is why several config files carry an
`app/` prefix that would otherwise look redundant.

## Getting started

MySQL and Redis are not part of this stack. They run once for the whole machine
in `../dev-infra`, shared with every other project on it, on the external
`apps_local` network. Start that first:

```shell
cd ../dev-infra && docker compose up -d
```

Then:

```shell
bin/setup            # or: APP_NAME=myapp bin/setup
make bundle          # install gems
make migrate         # create <app>_development on the shared server, then migrate
```

`bin/setup` generates the Rails app into `app/`, installs a container-ready
`config/database.yml`, points the cache at the shared Redis, writes a `.env`,
and starts the stack on <http://localhost:8282>.

The generator runs with `--skip-solid --skip-kamal --skip-thruster`. Rails 8
defaults to solid_cache, solid_queue and solid_cable, which want three
databases of their own — on a MySQL server shared with every other project,
created and migrated on every deploy, for a cache the instance already
provides as Redis. Kamal and Thruster describe a deployment and a proxy this
setup does not use.

`bin/setup` is safe to re-run: it skips the generator once `app/Gemfile`
exists, leaves a customised `database.yml` or cache store alone, and will not
overwrite `.env`.

```shell
make help            # every target
make up              # start          make logs     follow app logs
make down            # stop           make console  rails console
make check           # what CI runs   make sh       shell in the container
                                    # make db      mysql shell on the shared server
```

Nothing here drops a database. The server holds every project's, so remove this
app's by name (`make db`, then `DROP DATABASE <app>_development;`) rather than
with `docker compose down -v`.

## Layout

| Path | |
|---|---|
| `app/` | the Rails application |
| `build/app/Dockerfile` | production image — **not** `app/Dockerfile`, see below |
| `build/nginx/Dockerfile` | nginx, built `FROM` the app image so it serves the assets that build produced |
| `build/rails/database.yml` | the `database.yml` `bin/setup` installs, and why |
| `build/rails/cache_store.*.rb` | the Redis cache config `bin/setup` reads into the environment files |
| `services/nginx/conf.d/` | nginx config: `default.conf` for development, `default.conf.vps.template` for production |
| `deploy/hooks.sh` | what runs after the containers start |
| `docker-compose.yml` | development stack — nginx and Rails only |
| `docker-compose-vps.yml` | production stack |
| `.env.tpl` | names the secrets this app needs — never their values |

`app/Dockerfile` is what `rails new` generated. It is left in place because
Rails' own tooling expects it, but the deployment does not use it: it assumes
the app is the build context root and boots through `bin/docker-entrypoint`,
which runs `db:prepare` on every container start. `build/app/Dockerfile` is the
one that ships.

Both compose files join an **external** network they do not own — `apps_local`
in development, `vps_internal` in production. That is deliberate symmetry: the
backing services outlive any one app in both environments, and neither file can
create or destroy them.

## Deploying

See **[docs/deployment.md](docs/deployment.md)**. The short version: merging to
`main` (or pushing a `vX.Y.Z` tag) builds two images, pushes them to ECR, and
asks a Lambda to run the deployment on the instance over SSM.

**Not in this repository, though.** All three workflows — `ci.yml`, `aws.yml`
and `claude-code-review.yml` — have their triggers commented out, because a
template has no app to test and nowhere to deploy. Each keeps
`workflow_dispatch`, so uncommenting the triggers is the first edit an app cut
from this template makes.

Before the first deploy:

1. Set `APP_NAME` on the instance side to match what you passed to `bin/setup` —
   it names the containers, the database and the Secrets Manager entries.
2. Check `.env.tpl` lists every secret the app reads.
3. Confirm the instance runs Redis on the `vps_internal` network under the name
   `redis` — that is what `config.cache_store` defaults to. Every other app
   there uses the same one.
4. Uncomment the triggers in `.github/workflows/aws.yml` and `ci.yml`.
