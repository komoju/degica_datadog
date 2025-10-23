# frozen_string_literal: true

require "datadog"

module DegicaDatadog
  # Tracing related functionality.
  module Tracing
    class << self
      # Initialize Datadog tracing. Call this in from config/application.rb.
      def init(rake_tasks: [])
        return unless Config.enabled?

        # These are for source code linking. We define them as env vars instead of tags because
        # parts of the Datadog instrumentation also use these, and they don't know about the tags.
        ENV["DD_GIT_COMMIT_SHA"] ||= Config.version
        ENV["DD_GIT_REPOSITORY_URL"] ||= Config.repository_url

        # Disable ActiveRecord instrumentation, it duplicates SQL query spans.
        # This is a bit cumbersome because of the instrumentation API.
        # We keep instrumentation on for Postgres, as that has less useful spans for automatically
        # prepared statements.
        ENV["DD_TRACE_ACTIVE_RECORD_ENABLED"] ||= "false" unless defined?(PG)

        require "datadog/auto_instrument"

        Datadog.configure do |c|
          c.service = Config.service
          c.env = Config.environment
          c.version = Config.version
          c.tags = {
            "aws.region" => Config.aws_region
          }

          c.agent.host = Config.datadog_agent_host
          c.agent.port = Config.tracing_port

          c.runtime_metrics.enabled = true
          c.runtime_metrics.statsd = Statsd.client

          c.tracing.partial_flush.enabled = true
          c.tracing.partial_flush.min_spans_threshold = 2_000
          c.tracing.contrib.global_default_service_name.enabled = true

          # Enabling additional settings for these instrumentations.
          c.tracing.instrument :rails, request_queuing: true
          c.tracing.instrument :rack, request_queuing: true, web_service_name: Config.service
          c.tracing.instrument :sidekiq, distributed_tracing: true, quantize: { args: { show: :all } }
          c.tracing.instrument :mysql2, comment_propagation: "full"
          c.tracing.instrument :pg, comment_propagation: "full"

          # If initialised with rake tasks, instrument those.
          c.tracing.instrument(:rake, tasks: rake_tasks) if rake_tasks

          # Enable application security tracing.
          c.appsec.enabled = true
          c.appsec.instrument :rails

          # Enable dynamic instrumentation.
          c.dynamic_instrumentation.enabled = true
        end

        # This block is called before traces are sent to the agent, and allows
        # us to modify or filter them.
        Datadog::Tracing.before_flush(
          # Filter out health check spans.
          Datadog::Tracing::Pipeline::SpanFilter.new do |span|
            span.name == "rack.request" && span.get_tag("http.url")&.start_with?("/health_check")
          end,
          # Filter out static assets.
          Datadog::Tracing::Pipeline::SpanFilter.new do |span|
            span.name == "rack.request" &&
              (span.get_tag("http.url")&.start_with?("/assets") ||
               span.get_tag("http.url")&.start_with?("/packs"))
          end,
          # Filter out NewRelic reporter.
          Datadog::Tracing::Pipeline::SpanFilter.new do |span|
            span.get_tag("peer.hostname") == "collector.newrelic.com"
          end,
          # Group subdomains in service tags together.
          Datadog::Tracing::Pipeline::SpanProcessor.new do |span|
            span.set_tag("peer.hostname", "myshopify.com") if span.get_tag("peer.hostname")&.end_with?("myshopify.com")
            span.set_tag("peer.hostname", "ngrok.io") if span.get_tag("peer.hostname")&.end_with?("ngrok.io")
            if span.get_tag("peer.hostname")&.end_with?("ngrok-free.app")
              span.set_tag("peer.hostname", "ngrok-free.app")
            end
          end,
          # Use method + path as the resource name for outbound HTTP requests.
          Datadog::Tracing::Pipeline::SpanProcessor.new do |span|
            if %w[ethon faraday net/http httpclient httprb].include?(span.get_tag("component"))
              # The path group is normally generated in the agent, later on. We
              # don't want to use the raw path in the resource name, as that
              # would create a lot of resources for any path that contains an
              # ID. The logic seems to be at least vaguely to replace any path
              # segment that contains a digit with a ?, so we're reproducing
              # that here.
              path_group = DegicaDatadog::Util.path_group(span.get_tag("http.url"))
              span.resource = "#{span.get_tag("http.method")} #{path_group}"
            end
          end,
          # Remove AWS metadata fetches
          Datadog::Tracing::Pipeline::SpanFilter.new do |span|
            %w[/metadata/instance/compute /latest/api/token].include?(span.get_tag("http.url"))
          end
        )
      end

      # Start a new span.
      def span!(name, **options, &block)
        enrich_span_options!(options)
        Datadog::Tracing.trace(name, **options, &block)
      end

      # Set tags on the current tracing span.
      def span_tags!(**tags)
        return unless Config.enabled?

        tags.each do |k, v|
          current_span&.set_tag(k.to_s, v)
        end
      end

      # Add an exception to the current span and mark it as errored.
      def error!(err)
        return unless Config.enabled? && err.is_a?(Exception)

        current_span&.set_error(err)
        root_span&.set_error(err)
      end

      # Returns the current span.
      def current_span
        Datadog::Tracing.active_span if Config.enabled?
      end

      # Returns the current root span. Root here meaning within the service, not necessarily the
      # actual trace root span if that is from a different service.
      def root_span
        # forgive me my friends
        Datadog::Tracing.active_trace.instance_variable_get(:@root_span) if Config.enabled?
      end

      # Please don't use this. It's just a temporary thing until we can get the
      # statsd agent installed
      def root_span_tags!(**tags)
        tags.each do |k, v|
          root_span&.set_tag(k.to_s, v)
        end
      end

      # To pass in nested data to DD we need to pass keys separated with a "."
      # eg, "outer.inner". This method takes a nested hash and flattens it by
      # creating DD compatible key names.
      def flatten_hash_for_span(hsh, key = nil)
        flattened_hash = {}
        hsh.each do |k, v|
          flattened_key = [key, k].compact.join(".")

          if v.is_a? Hash
            flattened_sub_hash = flatten_hash_for_span(v, flattened_key)
            flattened_hash.merge! flattened_sub_hash
          else
            flattened_hash.merge! "#{flattened_key}": v
          end
        end

        flattened_hash
      end

      # Merge in default tags and service name.
      def enrich_span_options!(options)
        options[:service] = Config.service

        if options[:tags]
          options[:tags].merge!(default_span_tags)
        else
          options[:tags] = default_span_tags
        end
      end

      # Default span tags that get attached automatically.
      def default_span_tags
        {
          "component" => "degica_datadog",
          "span.kind" => "internal",
          "operation" => "custom_span"
        }
      end
    end
  end
end
