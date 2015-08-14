require 'octokit'

module Lita
  module Handlers
    class GithubOrgWatcher < Handler
      config :watchers, type: Array, required: true
      config :access_token, type: String, required: true
      config :poll_interval, type: Integer, default: 300

      on :connected, :setup
      on :github_refresh_orgs, :refresh_orgs

      def setup(payload)
        Octokit.auto_paginate = true

        every poll_interval do
          robot.trigger(:github_refresh_orgs)
        end
      end

      def refresh_orgs(payload)
        base_redis_key = "seen_list_%s_%s"
        watchers.each do |watcher|
          org = watcher[:org]
          channel = watcher[:channel]
          target = Source.new(room: channel)

          log.info("lita-github-org-watcher: updating orgs for #{org}")

          redis_key = format(base_redis_key, channel, org)
          seen_repos = redis.lrange(redis_key, 0, -1)

          repos(org).reverse.each do |repo|
            unless seen_repos.include?(repo.name)
              message = "New repo: %{full_name} | %{url}" % repo
              robot.send_message(target, message)
              redis.lpush(redis_key, repo.name)
            end
          end

        end
      rescue Exception => ex
        log.error("lita-github-org-watcher: exception during update #{ex}")
      end

      def access_token
        config.access_token
      end

      def watchers
        config.watchers
      end

      def poll_interval
        config.poll_interval
      end

      def repos(org)
        client.org_repos(org)
      end

      def client
        @client ||= Octokit::Client.new(access_token: access_token)
      end
    end

    Lita.register_handler(GithubOrgWatcher)
  end
end
