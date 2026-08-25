# syntax=docker/dockerfile:1
# Production image for this app.
#
# The build context is the REPOSITORY ROOT, not app/ -- the deploy workflow
# builds with `.` so that build/, deploy/ and services/ are all reachable in
# one context. Every path below therefore carries the app/ prefix.
#
# This is not app/Dockerfile. That file is what `rails new` generated: it
# assumes the app is the context root, boots through bin/docker-entrypoint,
# and serves via Thruster on port 80. This one is the image the deployment
# actually runs -- see the notes on the entrypoint at the bottom.

# Keep in step with app/.ruby-version.
ARG RUBY_VERSION=4.0.4
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /var/www/app

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl default-mysql-client libjemalloc2 libvips tzdata && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
    RAILS_LOG_TO_STDOUT="1" \
    RAILS_SERVE_STATIC_FILES="1"

# ---------------------------------------------------------------------------
# Build stage
# ---------------------------------------------------------------------------
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential default-libmysqlclient-dev git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Gems first: this layer is only invalidated when the lockfile changes, so
# ordinary code changes rebuild in seconds rather than reinstalling everything.
COPY app/Gemfile app/Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3 && \
    rm -rf "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

COPY app/ ./

# Bootsnap precompilation keeps boot time down in production. Tolerated as a
# failure because it is an optimisation -- a missing cache costs milliseconds,
# not correctness.
RUN bundle exec bootsnap precompile app/ lib/ || true

# SECRET_KEY_BASE_DUMMY tells Rails this is a build-time invocation, so it does
# not demand the real key just to compile assets. The real one arrives at
# runtime from Secrets Manager.
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile

# ---------------------------------------------------------------------------
# Final image
# ---------------------------------------------------------------------------
FROM base

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /var/www/app /var/www/app

# Non-root. Anything else sharing this image (a worker, a scheduler) writes
# only to tmp/ and log/, both owned below.
RUN groupadd --system --gid 1000 rails && \
    useradd --uid 1000 --gid rails --create-home --shell /bin/bash rails && \
    mkdir -p tmp log storage && \
    chown -R rails:rails /var/www/app
USER 1000:1000

EXPOSE 3000

# No ENTRYPOINT on purpose. Rails' stock bin/docker-entrypoint runs `db:prepare`
# whenever the command is exactly "./bin/rails server", which migrates on every
# container start -- and would race a second container started from the same
# image. Migrations run once, from deploy/hooks.sh, where a failure fails the
# deployment instead of scrolling past in container logs.
CMD ["./bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
