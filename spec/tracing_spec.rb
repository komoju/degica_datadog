# frozen_string_literal: true

RSpec.describe DegicaDatadog::Tracing do
  describe ".init" do
    it "does nothing when disabled" do
      allow(DegicaDatadog::Config).to receive(:enabled?).and_return(false)
      expect(described_class.init).to be_nil
    end

    it "does not raise error" do
      allow(DegicaDatadog::Config).to receive(:enabled?).and_return(true)
      expect { described_class.init }.not_to raise_error
    end
  end

  describe ".current_span" do
    it "does nothing when disabled" do
      allow(DegicaDatadog::Config).to receive(:enabled?).and_return(false)
      described_class.span!("test") do
        expect(described_class.current_span).to be_nil
      end
    end

    it "returns the current span" do
      allow(DegicaDatadog::Config).to receive(:enabled?).and_return(true)
      described_class.span!("test") do
        expect(described_class.current_span).to_not be_nil
      end
    end
  end

  describe ".root_span" do
    it "does nothing when disabled" do
      allow(DegicaDatadog::Config).to receive(:enabled?).and_return(false)
      described_class.span!("test") do
        expect(described_class.root_span).to be_nil
      end
    end

    it "returns the current span" do
      allow(DegicaDatadog::Config).to receive(:enabled?).and_return(true)
      described_class.span!("test") do
        expect(described_class.root_span).to_not be_nil
      end
    end
  end

  describe ".span!" do
    it "starts a new span" do
      expect { described_class.span!("test") }.to change { Datadog::Tracing.active_span }.from(nil)
    end
  end

  describe ".span_tags!" do
    it "adds tags into running span" do
      allow(DegicaDatadog::Config).to receive(:enabled?).and_return(true)
      described_class.span!("test")
      described_class.span_tags!(foo: "bar")
      expect(Datadog::Tracing.active_span&.tags).to include("foo" => "bar")
    end
  end

  describe ".flatten_hash_for_span" do
    it "flattens the hash" do
      hash = { foo: { bar: "baz" } }
      expect(described_class.flatten_hash_for_span(hash)).to eq({ "foo.bar": "baz" })
    end
  end

  describe ".enrich_span_options!" do
    it "adds the service name" do
      options = {}
      described_class.enrich_span_options!(options)
      expect(options[:service]).to eq(DegicaDatadog::Config.service)
    end

    it "adds the default tags if none are present" do
      options = {}
      described_class.enrich_span_options!(options)
      expect(options[:tags]).to eq(DegicaDatadog::Tracing.default_span_tags)
    end

    it "merges the default tags with the provided tags" do
      options = { tags: { "foo" => "bar" } }
      described_class.enrich_span_options!(options)
      expect(options[:tags]).to eq(DegicaDatadog::Tracing.default_span_tags.merge("foo" => "bar"))
    end

    it "overrides the provided tags with default tags" do
      options = { tags: { "component" => "foobar" } }
      described_class.enrich_span_options!(options)
      expect(options[:tags]).to eq(DegicaDatadog::Tracing.default_span_tags)
    end
  end
end
