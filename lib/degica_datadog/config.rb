# frozen_string_literal: true

require "datadog/statsd"
require "json"
require "uri"

module DegicaDatadog
  # Configuration for the Datadog agent.
  module Config
    class << self
      def init(service_name: nil, version: nil, environment: nil, repository_url: nil)
        @service = service_name
        @version = version
        @environment = environment
        @repository_url = repository_url
      end

      def enabled?
        return false if disable_env_var_flag

        %w[production staging].include?(environment) || ENV.fetch("DD_AGENT_URI", nil)
      end

      def statsd_client
        @statsd_client ||= Datadog::Statsd.new(datadog_agent_host, statsd_port)
      end

      def service
        @service ||= ENV.fetch("SERVICE_NAME", nil) || "unknown"
      end

      def version
        return @version if @version

        platform = ENV.fetch("PLATFORM", "")
        git_revision = ENV.fetch("_GIT_REVISION", "unknown")
        @version = platform.empty? ? git_revision : "#{git_revision}-#{platform}"
      end

      def environment
        @environment ||= ENV.fetch("O11Y_ENV", nil) || ENV.fetch("RAILS_ENV", nil) || "unknown"
      end

      def repository_url
        @repository_url ||= "github.com/degica/#{service}"
      end

      # URI including http:// prefix & port for the tracing endpoint, or nil.
      def datadog_agent_uri
        return unless enabled?

        ecs_meta_file = ENV.fetch("ECS_CONTAINER_METADATA_FILE", nil)
        if ecs_meta_file
          host_ip = JSON.parse(File.read(ecs_meta_file))&.dig("HostPrivateIPv4Address")
          return URI.parse(format("http://%s:9126", host_ip)) if host_ip
        end

        env_uri = ENV.fetch("DD_AGENT_URI", nil)
        URI.parse(env_uri) unless env_uri.nil?
      end

      def datadog_agent_host
        datadog_agent_uri&.host || "localhost"
      end

      def statsd_port
        tracing_port - 1
      end

      def tracing_port
        datadog_agent_uri&.port || 8126
      end

      def inspect
        "DegicaDatadog::Config<enabled?=#{!!enabled?} service=#{service} version=#{version} environment=#{environment} repository_url=#{repository_url} datadog_agent_host=#{datadog_agent_host} statsd_port=#{statsd_port} tracing_port=#{tracing_port}>" # rubocop:disable Layout/LineLength
      end

      private

      def disable_env_var_flag
        %w[true 1].include?(ENV["DISABLE_DEGICA_DATADOG"])
      end
    end
  end
end
