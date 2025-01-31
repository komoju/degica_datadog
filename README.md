# Degica Datadog

Internal library for StatsD and tracing.

## Setup

1. Grab the gem from GitHub:
    ```ruby
    gem 'degica_datadog', git: "https://github.com/komoju/degica_datadog.git", branch: "main"
    ```
1. Then add this to your `config/application.rb` to enable tracing:
    ```ruby
    require "degica_datadog"

    DegicaDatadog::Config.init(
      service_name: "hats",
      version: "abc123", # optional, ideally a git SHA
      environment: "staging", # optional, see note below
      repository_url: "github.com/komoju/my-service"
    )
    DegicaDatadog::Tracing.init
    ```

The environment is sourced from `RAILS_ENV`, but can be overridden using the 
`O11Y_ENV` environment variable, in cases where we want to distinguish specific
environments (e.g. different staging environments).

### Custom Logging

Note that you will need to manually setup log correlation for tracing if you use a custom logging setup. This is the relevant bit from `hats`:

```ruby
structured_log.merge!({
  "dd.env" => Datadog::Tracing.correlation.env,
  "dd.service" => Datadog::Tracing.correlation.service,
  "dd.version" => Datadog::Tracing.correlation.version,
  "dd.trace_id" => Datadog::Tracing.correlation.trace_id,
  "dd.span_id" => Datadog::Tracing.correlation.span_id
}.compact)
```

### Rake Tasks

If you want to instrument rake tasks, you will need to add this snippet to your `Rakefile`:

```ruby
require "degica_datadog"
DegicaDatadog::Config.init(service_name: "hats")
DegicaDatadog::Tracing.init(rake_tasks: Rake::Task.tasks.map(&:name))
```

This is because you might not want to instrument all rake tasks, though there should be no significant overhead from doing so. Alternatively you can pass an array of strings containing the task names to instrument.

## StatsD

This library exposes various different metric types. Please see the [Datadog Handbook](https://www.notion.so/The-Datadog-Handbook-b69e58b686f54bf795b36f97746a31ea) for details.

```ruby
tags: {
    "some_tag" => 42,
}

DegicaDatadog::Statsd.with_timing("my_timing", tags: tags) do
    do_a_thing
end
DegicaDatadog::Statsd.count("my_count", amount: 1, tags: tags)
DegicaDatadog::Statsd.gauge("my_gauge", 4, tags: tags)
DegicaDatadog::Statsd.distribution("my_distribution", 8, tags: tags)
DegicaDatadog::Statsd.set("my_distribution", payment, tags: tags)
```

## Tracing

The setup above auto-instruments many components of the system, but you can add additional spans or span tags:

```ruby
# Create a new span.
DegicaDatadog::Tracing.span!("hats.process_payment") do
  # Process a payment.
end

# Optionally specify a resource and/or tags.
resource = webhook.provider.name
tags = {
    "merchant.uuid" => merchant.uuid,
    "merchant.name" => merchant.name,
}
DegicaDatadog::Tracing.span!("hats.send_webhook", resource: resource, tags: tags) do
  # Send a webhook.
end

# Add tags to the current span.
DegicaDatadog::Tracing.span_tags!(**tags)

# Add tags to the current root span.
DegicaDatadog::Tracing.root_span_tags!(**tags)

# Record an exception on the current span. This is only required if the 
# exception is caught and swallowed, so we return a 200 or similar, but we 
# still want to report the exception to Datadog for tracking purposes.
DegicaDatadog::Tracing.error!(e)
```

## Profiling

We have support for detailed CPU and memory profiling, which can give us
detailed insights into resources spent on every single method call. This is not
free, both in terms of a small performance overhead, and in terms of money paid
to Datadog, so we do not have this enabled by default.

Price-wise, it is fine to enable profiling on a reviewapp or staging. Should you
require profiling on production, you should probably clear that with Engineering
leadership.

There are several steps to enable profiling, regardless of the environment:

1. Set the `DD_PROFILING_ENABLED=true` environment variable.
1. (Optionally) set the `DD_PROFILING_ALLOCATION_ENABLED=true` if you want to profile memory use.
1. Instead of running your command directly, wrap it in `bundle exec ddprofrb exec`, for example `bundle exec ddprofrb exec bin/rails s -p 50130`.

## Collecting data from local environments

By default we do not collect data from local environments, but we can.

First install the Datadog agent [following the
instructions](https://app.datadoghq.com/account/settings/agent/latest?platform=overview),
and ensure it is running.

Set the `DD_AGENT_URI` environment variable to `http://localhost:8126` (pointing
to the tracing port) to start collecting both StatsD and tracing data:

```shell
DD_AGENT_URI=http://localhost:8126 bin/rails s -p 50130
```

If you want to collect data from alternative processes such as Sidekiq workers,
set the environment variable before starting those. The easiest way to do this
is to `export` them, but be aware that you will continue collecting data until
you unset the variable.

For profiling local environments, set both the agent URI environment variable,
and follow the steps to enable profiling. Note that profiling is currently not
supported on macOS. It does work on Codespaces though.

The data will show up on Datadog under the `development` `env` tag, and will
also use your local machine hostname for the `host` tag. The `version` tag will
be `unknown`.

### Codespaces

Codespaces works similarly to regular local environments. Insert the following
snippet into the `docker-compose.yml` to add a Datadog agent:

```yaml
  datadog_agent:
    image: datadog/agent:latest
    environment:
      - DD_API_KEY=<enter your API key here>
    ports:
      - "8126:8126"
      - "8125:8125/udp"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /proc/:/host/proc/:ro
      - /sys/fs/cgroup/:/host/sys/fs/cgroup:ro
```

Of course, do not commit your API key.

Next, add this line to `.devcontainer/devcontainer.json`:

```json
  "runServices": ["dev", "datadog_agent"],
```

Then similarly to the local setup, set the correct agent URI inside codespaces:

```shell
DD_AGENT_URI=http://datadog_agent:8126 bin/rails s -p 50130
```

### Disabling

By default statsd and tracing are enabled by simply including this gem into an environment that has the `ECS_ENABLE_CONTAINER_METADATA` or `DD_AGENT_URI` environment variables enabled above, and the `RAILS_ENV` is set to either `production` or `staging`. If there are cases where you do want to disable it, you can set the ENV var `DISABLE_DEGICA_DATADOG=true` and you will force disable this gem.
