#!/usr/bin/env bash
# Post-deploy steps, sourced by the deploy-app SSM document after the
# containers are up.
#
# The document provides `run <cmd>`, which executes inside the running app
# container. Declaring FRAMEWORK skips its own detection -- worth doing because
# detection happens before any container exists and is only a guess from the
# compose file.
#
# Without this file the document auto-detects Rails and runs db:migrate, which
# is exactly what this app needs. It exists to say so explicitly -- detection
# happens before any container exists and is only a guess from the compose
# file -- and to be the place a worker restart or an extra migration goes when
# one is added.

FRAMEWORK=rails

post_deploy() {
  # Primary schema first. Unguarded on purpose: if this fails the deployment
  # fails, because a half-migrated app serving traffic is worse than a
  # deployment that visibly stopped.
  run "./bin/rails db:migrate"

  # No cache, queue or cable migrations: this app has one database. The
  # generator runs with --skip-solid, caching goes to the Redis the instance
  # already runs, and nothing enqueues jobs. Adding solid_queue later means a
  # `run "./bin/rails db:migrate:queue"` line here AND a queue entry in
  # config/database.yml -- the two have to move together.

  # Any long-lived container other than the web one holds Rails' class cache
  # from before the migration, so it has to restart to see new columns. The web
  # container was already replaced by the compose up.
  #
  # su - admin: the document runs as root, and the docker socket belongs to the
  # admin user on these instances.
  #
  # su - admin -c "docker restart ${APP_NAME}-worker" >/dev/null 2>&1 \
  #   || echo "WARNING: could not restart worker"
}
