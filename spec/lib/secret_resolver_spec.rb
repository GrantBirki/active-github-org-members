# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/secret_resolver"

describe SecretResolver do
  describe ".supported_reference?" do
    it "accepts registered URI schemes" do
      expect(described_class.supported_reference?("op://ExampleVault/item/private-key.pem")).to be true
    end

    it "rejects unregistered URI schemes" do
      expect(described_class.supported_reference?("vault://secret/path")).to be false
    end

    it "rejects plain strings" do
      expect(described_class.supported_reference?("literal-key")).to be false
    end

    it "rejects invalid URI strings" do
      expect(described_class.supported_reference?("https://[not-valid")).to be false
    end
  end

  describe ".read" do
    it "routes registered references to the matching provider" do
      provider = instance_double(SecretResolver::OnePassword)
      stub_const("SecretResolver::PROVIDERS", { "op" => provider }.freeze)
      allow(provider).to receive(:read)
        .with("op://ExampleVault/item/private-key.pem")
        .and_return("private-key")

      expect(described_class.read("op://ExampleVault/item/private-key.pem")).to eq("private-key")
    end

    it "raises for unsupported references" do
      expect {
        described_class.read("vault://secret/path")
      }.to raise_error("Unsupported secret reference")
    end
  end

  describe SecretResolver::OnePassword do
    let(:provider) { described_class.new }

    it "reads a secret through the op CLI" do
      status = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture3)
        .with("op", "read", "op://ExampleVault/item/private-key.pem")
        .and_return(["private-key", "", status])

      expect(provider.read("op://ExampleVault/item/private-key.pem")).to eq("private-key")
    end

    it "raises when op read fails" do
      status = instance_double(Process::Status, success?: false)
      allow(Open3).to receive(:capture3)
        .with("op", "read", "op://ExampleVault/item/private-key.pem")
        .and_return(["", "not signed in", status])

      expect {
        provider.read("op://ExampleVault/item/private-key.pem")
      }.to raise_error("Unable to read secret from 1Password: not signed in")
    end

    it "raises with a fallback message when op read fails silently" do
      status = instance_double(Process::Status, success?: false)
      allow(Open3).to receive(:capture3)
        .with("op", "read", "op://ExampleVault/item/private-key.pem")
        .and_return(["", "", status])

      expect {
        provider.read("op://ExampleVault/item/private-key.pem")
      }.to raise_error("Unable to read secret from 1Password: op read failed")
    end

    it "raises when op read returns an empty secret" do
      status = instance_double(Process::Status, success?: true)
      allow(Open3).to receive(:capture3)
        .with("op", "read", "op://ExampleVault/item/private-key.pem")
        .and_return(["", "", status])

      expect {
        provider.read("op://ExampleVault/item/private-key.pem")
      }.to raise_error("Secret from 1Password is empty")
    end
  end
end
