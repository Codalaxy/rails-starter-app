# Deployment

What happens between merging a PR and the app running on the server.

- [The path a deploy takes](#the-path-a-deploy-takes)
- [Why there is no deploy script in this repo](#why-there-is-no-deploy-script-in-this-repo)
- [What this repo provides](#what-this-repo-provides)
- [Secrets](#secrets)
- [Post-deploy steps](#post-deploy-steps)
- [Two things the generated Rails config gets wrong](#two-things-the-generated-rails-config-gets-wrong)
- [Where it can fail](#where-it-can-fail)

---

## The path a deploy takes

```
merge to main  (or push a vX.Y.Z tag)
   │
   ├─ 1. GitHub Actions (.github/workflows/aws.yml)
   │     calls the shared workflow in Codalaxy/aws-infra
   │
   ├─ 2. Authenticate to AWS via OIDC
   │     no credentials are stored in this repo
   │
   ├─ 3. Build app-latest and nginx-latest, push to ECR
   │     nginx is built FROM the app image, so it serves exactly
   │     the assets that build produced
   │
   ├─ 4. Tar docker-compose-vps.yml, .env.tpl, services/, deploy/
   │     and invoke the deployBackendCode Lambda
   │
   ├─ 5. Lambda finds the EC2 instance by tag and sends the
   │     deploy-app SSM document to it
   │
   └─ 6. On the instance:
         unpack → provision secrets → pull images → restart
         containers → run migrations → delete .env
```

Steps 1–4 run on a GitHub runner. Steps 5–6 run on the instance, and their
output is **not** in the GitHub Actions log.

## Why there is no deploy script in this repo

Every app used to carry its own copy of `deploy/aws.sh`. They drifted — a fix in
one never reached the others. The logic now lives once, in
[`aws-infra/.github/workflows/deploy-app.yml`](https://github.com/Codalaxy/aws-infra/blob/main/.github/workflows/deploy-app.yml).
This repo's `.github/workflows/aws.yml` only says *which images to build*:

```yaml
uses: Codalaxy/aws-infra/.github/workflows/deploy-app.yml@main
with:
  images: |
    app-latest:build/app/Dockerfile
    nginx-latest:build/nginx/Dockerfile
secrets: inherit
```

**The trade-off:** a change to the shared workflow affects every app at once.
When a deploy breaks, the cause may be in `aws-infra` rather than here.

**One requirement that is easy to miss:** the calling workflow must declare
`id-token: write`. A called workflow cannot grant itself more permission than
its caller holds, so without it the run fails at startup with **no jobs and no
log**.

## What this repo provides

| File | Purpose |
|---|---|
| `.github/workflows/aws.yml` | Names the images to build; calls the shared workflow |
| `build/app/Dockerfile` | Production image. Gems install in their own layer, so a code change rebuilds in seconds |
| `build/nginx/Dockerfile` | Built `FROM` the app image so it serves the assets that build produced |
| `docker-compose-vps.yml` | app + nginx (+ a commented worker) |
| `services/nginx/conf.d/default.conf.vps.template` | Production nginx: gzip, immutable asset caching, security headers |
| `deploy/hooks.sh` | Post-deploy commands |
| `.env.tpl` | Names the secrets this app needs — never their values |
| `build/rails/cache_store.production.rb` | Points `config.cache_store` at `redis` on `vps_internal` |
| `.dockerignore` | Governs the build context, which is the repository **root** |

## Secrets

`.env.tpl` is a list of names with empty values. It is committed and holds no
secrets. Its only job is to declare what this app needs:

```
.env.tpl in this repo          names WHICH secrets are needed
        ▼
AWS Secrets Manager            prod/main — one JSON blob shared by every
  RAILS_MASTER_KEY_<app>       app, namespaced per app
        ▼
provision_secrets.sh           maps the namespaced name back to the plain
        ▼                      name the app reads
.env on the instance           written at deploy, DELETED once containers are up
        ▼
container environment
```

Two entries are also **generated** if they do not exist: the SSM document greps
`.env.tpl` for `RAILS_MASTER_KEY=` and `SECRET_KEY_BASE=` and mints them once.
Once generated they are never touched again — a key that changed per deploy
would invalidate every encrypted value and every session.

`RAILS_MASTER_KEY` is an AES-128 key: **exactly 32 hex characters**. A wrong
length is a hard failure by design. It used to be generated at 64, Rails refused
to boot with `key must be 16 bytes`, the container crash-looped, and the deploy
reported `TimedOut` — pointing nowhere near the cause.

To add a secret: add the name to `.env.tpl` with an empty value, then put the
value in Secrets Manager under `prod/main`, namespaced if it is app-specific.

## Post-deploy steps

`deploy/hooks.sh` declares what runs after the containers start. The deployment
script sources it and calls `post_deploy`, providing a `run` function that
executes inside the app container.

**The migration is unguarded, so a failure fails the deploy.** A half-migrated
app serving traffic is worse than a deployment that visibly stopped.

**There is only the one migration.** The app has a single database — the
generator runs with `--skip-solid` and caching goes to the Redis the instance
already runs, so there is no cache, queue or cable schema to migrate. Adding
solid_queue later means a line here *and* a `queue:` entry in
`config/database.yml`; the two have to move together.

**Any long-lived container other than the web one must be restarted
explicitly.** It holds Rails' class cache from before the migration, so it will
not see new columns. The web container was already replaced by the compose up.

## Two things the generated Rails config gets wrong

Both only appear in production:

- **`database.yml`** hardcodes `username: app`, reads a bespoke
  `APP_DATABASE_PASSWORD`, and ignores `DB_HOST` — so the container looks for a
  local MySQL socket that does not exist inside it. `bin/setup` installs
  `build/rails/database.yml` instead, where every environment inherits
  `DB_USER`, `DB_PASSWORD` and `DB_HOST`.
- **Rails' stock `bin/docker-entrypoint`** runs `db:prepare` whenever the
  command is `./bin/rails server`. That migrates on every container start, and
  races any second container from the same image. `build/app/Dockerfile` sets no
  entrypoint; migrations run once, from `deploy/hooks.sh`.

## Where it can fail

The GitHub Actions log covers steps 1–4 only. **A green tick means the deploy
was dispatched, not that it succeeded** — the Lambda returns as soon as SSM
accepts the command.

| Symptom | Where to look |
|---|---|
| Run fails at startup, no jobs, no log | Missing `id-token: write` in the caller |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | OIDC trust policy in `aws-infra` |
| Build fails | GitHub Actions log — normal Docker build output |
| Green tick, app not updated | The SSM command history on the instance |
| App restarts in a loop | `docker logs`, not the deploy output |
| `network <app>_host_network is ambiguous` | A project-scoped network in `docker-compose-vps.yml` — there must only be the external one |
