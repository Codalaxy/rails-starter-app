  # cache store -- managed by bin/setup
  #
  # dev-redis from ../dev-infra: one cache shared by every process that boots
  # this app, and with the other projects on the machine (on separate Redis
  # databases). Replaces the generated :memory_store, which is per-process --
  # so the console and the server would each have had their own.
  #
  # Unreachable is survivable: the store logs and carries on, so a stopped
  # dev-redis costs speed rather than the app.
  config.cache_store = :redis_cache_store, {
    url: "redis://#{ENV.fetch("REDIS_HOST") { "dev-redis" }}:6379/1",
    error_handler: ->(method:, returning:, exception:) { Rails.logger.warn("redis: #{exception.message}") }
  }
