  # cache store -- managed by bin/setup
  #
  # REDIS_URL is set in docker-compose-vps.yml; "redis" is the container name
  # on the shared vps_internal network, so no host has to be provisioned as a
  # secret. The generated config/cable.yml reads the same variable, so both
  # move together.
  #
  # Without this, Rails 8 leaves cache_store commented out and production runs
  # on the default in-memory store -- per process, lost on every deploy.
  config.cache_store = :redis_cache_store, {
    url: ENV.fetch("REDIS_URL") { "redis://redis:6379/1" }
  }
