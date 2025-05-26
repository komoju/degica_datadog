# frozen_string_literal: true

RSpec.describe DegicaDatadog::Config do
  before(:example) do
    described_class.init
  end

  describe ".init" do
    context "full initialisation" do
      let(:service_name) { "komoju" }
      let(:version) { "1.0.0" }
      let(:environment) { "production" }
      let(:repository_url) { "https://github.com/komoju/degica_datadog" }
      let(:aws_region) { "ap-northeast-1" }

      before do
        described_class.init(
          service_name: service_name,
          version: version,
          environment: environment,
          repository_url: repository_url,
          aws_region: aws_region
        )
      end

      it "sets service_name correctly" do
        expect(described_class.service).to eq(service_name)
      end

      it "sets version correctly" do
        expect(described_class.version).to eq(version)
      end

      it "sets environment correctly" do
        expect(described_class.environment).to eq(environment)
      end

      it "sets repository_url correctly" do
        expect(described_class.repository_url).to eq(repository_url)
      end

      it "sets aws_region correctly" do
        expect(described_class.aws_region).to eq(aws_region)
      end
    end

    context "fetches from env" do
      let(:service_name) { "mocked_service_name" }
      let(:version) { "mocked_version" }
      let(:environment) { "mocked_environment" }

      before do
        described_class.init

        allow(ENV).to receive(:fetch).with("SERVICE_NAME", nil).and_return(service_name)
        allow(ENV).to receive(:fetch).with("PLATFORM", "").and_return("")
        allow(ENV).to receive(:fetch).with("_GIT_REVISION", "unknown").and_return(version)
        allow(ENV).to receive(:fetch).with("O11Y_ENV", nil).and_return(environment)
        allow(ENV).to receive(:fetch).with("DD_AWS_REGION", nil).and_return("ap-northeast-1")
      end

      it "sets service_name correctly" do
        expect(described_class.service).to eq(service_name)
      end

      it "sets version correctly" do
        expect(described_class.version).to eq(version)
      end

      it "sets environment correctly" do
        expect(described_class.environment).to eq(environment)
      end

      it "sets repository_url correctly" do
        expect(described_class.repository_url).to eq("github.com/komoju/#{service_name}")
      end
    end

    context "fetches from env on codepipeline" do
      let(:version) { "mocked_version" }
      let(:platform) { "cpp" } # codepipeline prefix

      before do
        described_class.init

        allow(ENV).to receive(:fetch).with("PLATFORM", "").and_return(platform)
        allow(ENV).to receive(:fetch).with("_GIT_REVISION", "unknown").and_return(version)
      end

      it "sets version correctly" do
        expect(described_class.version).to eq("#{version}-#{platform}")
      end
    end
  end

  describe ".enabled?" do
    it "is true on production" do
      allow(ENV).to receive(:fetch) { |key|
        { "RAILS_ENV" => "production" }.fetch(key, nil)
      }
      expect(!described_class.enabled?.nil?).to be(true)
    end

    it "is true on staging" do
      allow(ENV).to receive(:fetch) { |key|
        { "RAILS_ENV" => "staging" }.fetch(key, nil)
      }
      expect(!described_class.enabled?.nil?).to be(true)
    end

    it "is false on development" do
      allow(ENV).to receive(:fetch) { |key|
        { "RAILS_ENV" => "development" }.fetch(key, nil)
      }
      expect(!described_class.enabled?.nil?).to be(false)
    end

    it "is true if DD_AGENT_URI is set" do
      allow(ENV).to receive(:fetch) { |key|
        {
          "RAILS_ENV" => "development",
          "DD_AGENT_URI" => "some-uri"
        }.fetch(key, nil)
      }
      expect(!described_class.enabled?.nil?).to be(true)
    end

    it "is false when the env var flag is set" do
      allow(described_class).to receive(:disable_env_var_flag).and_return(true)
      expect(described_class.enabled?).to eq(false)
    end
  end

  describe ".environment" do
    before(:example) do
      described_class.init
    end

    it "prefers O11Y_ENV over RAILS_ENV" do
      allow(ENV).to receive(:fetch) { |key|
        {
          "RAILS_ENV" => "staging",
          "O11Y_ENV" => "load-test"
        }.fetch(key, nil)
      }
      expect(described_class.environment).to eq("load-test")
    end

    it "falls back to RAILS_ENV" do
      allow(ENV).to receive(:fetch) { |key|
        {
          "RAILS_ENV" => "staging",
          "O11Y_ENV" => nil
        }.fetch(key, nil)
      }
      expect(described_class.environment).to eq("staging")
    end
  end

  describe ".statsd_client" do
    it "returns the statsd client" do
      allow(described_class).to receive(:enabled?).and_return(true)
      expect(described_class.statsd_client).to be_kind_of(Datadog::Statsd)
    end
  end

  describe ".datadog_agent_uri" do
    it "returns nil if described_class is disabled" do
      allow(described_class).to receive(:enabled?).and_return(false)
      expect(described_class.datadog_agent_uri).to be(nil)
    end

    it "returns the ECS IP + port 9126 on ECS" do
      allow(described_class).to receive(:enabled?).and_return(true)
      allow(ENV).to receive(:fetch) { |key|
        { "ECS_CONTAINER_METADATA_FILE" => "/somewhere" }.fetch(key, nil)
      }
      allow(File).to receive(:read).and_return('{"HostPrivateIPv4Address":"127.0.0.1"}')
      expect(described_class.datadog_agent_uri).to eq(URI.parse("http://127.0.0.1:9126"))
    end

    it "returns the URI from DD_AGENT_URI" do
      allow(described_class).to receive(:enabled?).and_return(true)
      allow(ENV).to receive(:fetch) { |key|
        { "DD_AGENT_URI" => "http://127.0.0.1:9126" }.fetch(key, nil)
      }
      expect(described_class.datadog_agent_uri).to eq(URI.parse("http://127.0.0.1:9126"))
    end

    it "prefers ECS settings over env vars" do
      allow(described_class).to receive(:enabled?).and_return(true)
      allow(ENV).to receive(:fetch) { |key|
        {
          "ECS_CONTAINER_METADATA_FILE" => "/somewhere",
          "DD_AGENT_URI" => "http://somewhere:1234"
        }.fetch(key, nil)
      }
      allow(File).to receive(:read).and_return('{"HostPrivateIPv4Address":"127.0.0.1"}')
      expect(described_class.datadog_agent_uri).to eq(URI.parse("http://127.0.0.1:9126"))
    end
  end

  describe ".datadog_agent_host" do
    it "defaults to localhst" do
      expect(described_class.datadog_agent_host).to eq("localhost")
    end

    it "uses the hsot from the URI" do
      allow(described_class).to receive(:datadog_agent_uri) { URI.parse("http://somewhere:1234") }
      expect(described_class.datadog_agent_host).to eq("somewhere")
    end
  end

  describe ".statsd_port" do
    it "defaults to 8125" do
      expect(described_class.statsd_port).to eq(8125)
    end

    it "uses the port one below the one from the URI" do
      allow(described_class).to receive(:datadog_agent_uri) { URI.parse("http://localhost:1234") }
      expect(described_class.statsd_port).to eq(1233)
    end
  end

  describe ".tracing_port" do
    it "defaults to 8126" do
      expect(described_class.tracing_port).to eq(8126)
    end

    it "uses the port from the URI" do
      allow(described_class).to receive(:datadog_agent_uri) { URI.parse("http://localhost:1234") }
      expect(described_class.tracing_port).to eq(1234)
    end
  end

  describe ".aws_region" do
    before(:example) do
      described_class.init
    end

    it "returns the AWS region from environment variable" do
      allow(ENV).to receive(:fetch).with("DD_AWS_REGION", nil).and_return("ap-northeast-1")
      expect(described_class.aws_region).to eq("ap-northeast-1")
    end

    it "returns nil when DD_AWS_REGION is not set" do
      allow(ENV).to receive(:fetch).with("DD_AWS_REGION", nil).and_return(nil)
      expect(described_class.aws_region).to be_nil
    end
  end

  describe ".inspect" do
    it "returns a string representation of the config" do
      allow(described_class).to receive(:enabled?).and_return(true)
      allow(described_class).to receive(:statsd_client) { double("statsd_client") }
      expect(described_class.inspect).to eq("DegicaDatadog::Config<enabled?=true service=unknown version=unknown environment=unknown repository_url=github.com/komoju/unknown datadog_agent_host=localhost statsd_port=8125 tracing_port=8126 aws_region=nil>") # rubocop:disable Layout/LineLength
    end
  end
end
# rubocop:enable Metrics/BlockLength
