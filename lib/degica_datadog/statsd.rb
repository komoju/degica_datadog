# frozen_string_literal: true

require "datadog_api_client"

module DegicaDatadog
  # StatsD related functionality.
  module Statsd
    class << self
      # Record a timing for the supplied block. Creates a series of
      # metrics:
      # - <name>.count
      # - <name>.max
      # - <name>.median
      # - <name>.avg
      # - <name>.95percentile
      #
      # The reported time is in milliseconds.
      def with_timing(name, tags: {})
        if Config.enabled?
          start = Time.now.to_f
          begin
            yield
          ensure
            finish = Time.now.to_f
            client.histogram(name, (finish - start) * 1_000, tags: format_tags(tags))
          end
        else
          yield
        end
      end

      # Record a count of something (e.g. a payment going through). Use
      # the amount parameter to register several of a thing, or to
      # decrement the counter with a negative amount. All recorded amounts
      # are summed together to calculate the metric.
      def count(name, amount: 1, tags: {}, timestamp: nil)
        return unless Config.enabled?

        tags = format_tags(tags)

        if timestamp.nil?
          client.count(name, amount, tags: tags)
        else
          record_historical_metric(:count, name, amount, tags, timestamp)
        end
      end

      # Record the current value of something (e.g. the depth of a queue).
      # The metric equals the last recorded value.
      def gauge(name, value, tags: {}, timestamp: nil)
        return unless Config.enabled?

        tags = format_tags(tags)

        if timestamp.nil?
          client.gauge(name, value, tags: tags)
        else
          record_historical_metric(:gauge, name, amount, tags, timestamp)
        end
      end

      # Record a value of something for a distribution (e.g. the size of a
      # file or a fraud risk score). This will create a metric that has
      # various percentiles enabled.
      def distribution(name, value, tags: {})
        return unless Config.enabled?

        client.distribution(name, value, tags: format_tags(tags))
      end

      # Record an item for a set size metric. This will create a
      # gauge-type metric that shows the count of unique set items over
      # time (but not the individual items).
      def set(name, item, tags: {})
        return unless Config.enabled?

        client.set(name, item, tags: format_tags(tags))
      end

      def client
        Config.statsd_client
      end

      def default_tags
        {
          "service" => Config.service,
          "env" => Config.environment,
          "version" => Config.version,
          # These are specifically for source code linking.
          "git.commit.sha" => Config.version,
          "git.repository_url" => Config.repository_url
        }
      end

      # Add in default tags and transform:
      #
      # { "foo" => 42, "bar" => 23 } => ["foo:42", "bar:23"]
      #
      # Default tags take precedence to avoid messing up metrics because
      # of name clashes.
      def format_tags(tags)
        tags.merge(default_tags).map { |k, v| "#{k}:#{v}" }
      end

      # Records a historical metric with an explicit timestamp.
      #
      # These metrics are not sent through the Datadog agent but instead sent directly to the
      # Datadog API, so they work somewhat differently. In theory, we could batch several points,
      # but with how our library interface works, we will only ever submit one point at a time.
      def record_historical_metric(type, name, value, tags, timestamp)
        raise "Invalid metric timestamp, use a Time" unless timestamp.is_a?(Time)

        type = case type
               when :count then DatadogAPIClient::V2::MetricIntakeType::COUNT
               when :rate then DatadogAPIClient::V2::MetricIntakeType::RATE
               when :gauge then DatadogAPIClient::V2::MetricIntakeType::GAUGE
               else raise "Invalid metric type: #{type}"
               end

        point = DatadogAPIClient::V2::MetricPoint.new({ timestamp: timestamp.to_i, value: value })

        # Tags here are the ["foo:42", "bar:23"] format, so we need to break them apart.
        tags = tags.map do |tag|
          k, v = tag.split(":")
          DatadogAPIClient::V2::MetricResource.new({ name: k, type: v })
        end.to_a

        metric = DatadogAPIClient::V2::MetricSeries.new({
                                                          metric: name,
                                                          type: type,
                                                          points: [point],
                                                          resources: tags
                                                        })

        body = DatadogAPIClient::V2::MetricPayload.new({ series: [metric] })

        metrics_api_client.submit_metrics(body)
      end

      def metrics_api_client
        raise "Missing DD_API_KEY environment variable" unless ENV["DD_API_KEY"]

        @metrics_api_client ||= DatadogAPIClient::V2::MetricsAPI.new
      end
    end
  end
end
