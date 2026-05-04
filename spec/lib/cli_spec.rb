# frozen_string_literal: true

require "json"
require "stringio"

require "spec_helper"
require_relative "../../lib/cli"

describe ActiveGitHubOrgMembers::CLI do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:github) { double("github") }
  let(:now) { Time.utc(2026, 5, 4, 12, 0, 0) }

  def empty_scan_stubs(org: "acme", days: 90, branch_mode: :default)
    since = now - (days * ActiveGitHubOrgMembers::SECONDS_PER_DAY)
    branch_request_count = branch_mode == :all ? 1 : 0

    allow(github).to receive(:get)
      .with("orgs/#{org}/members", per_page: 100)
      .and_return([{ login: "alice" }])
    allow(github).to receive(:get)
      .with("orgs/#{org}/repos", type: "all", per_page: 100)
      .and_return([{ full_name: "#{org}/api", default_branch: "main" }])
    branch_stub = allow(github).to receive(:get)
      .with("repos/#{org}/api/branches", per_page: 100)
      .exactly(branch_request_count).times
    branch_stub.and_return([{ name: "main" }]) if branch_request_count.positive?
    allow(github).to receive(:get)
      .with("repos/#{org}/api/commits", sha: "main", since: since.iso8601, per_page: 100)
      .and_return([{ sha: "a1", author: { login: "alice" } }])
  end

  it "prints the text summary for an org with the default lookback" do
    empty_scan_stubs

    exit_code = described_class.run(argv: ["acme"], stdout: stdout, stderr: stderr, github: github, now: now)

    expect(exit_code).to eq(0)
    expect(stderr.string).to eq("")
    expect(stdout.string).to include("Active GitHub org members for acme")
    expect(stdout.string).to include("Lookback: 90 days")
    expect(stdout.string).to include("Active members: 1 / 1")
    expect(stdout.string).to include("alice\t1\tacme/api")
  end

  it "prints json output with positional days" do
    empty_scan_stubs(days: 30)

    exit_code = described_class.run(argv: ["acme", "30", "--json"], stdout: stdout, stderr: stderr, github: github, now: now)
    parsed = JSON.parse(stdout.string)

    expect(exit_code).to eq(0)
    expect(parsed).to include(
      "org" => "acme",
      "days" => 30,
      "active_members_count" => 1
    )
  end

  it "supports the --days option" do
    empty_scan_stubs(days: 7)

    exit_code = described_class.run(argv: ["--days", "7", "acme"], stdout: stdout, stderr: stderr, github: github, now: now)

    expect(exit_code).to eq(0)
    expect(stdout.string).to include("Lookback: 7 days")
  end

  it "supports all branch scans" do
    empty_scan_stubs(branch_mode: :all)

    exit_code = described_class.run(
      argv: ["acme", "--all-branches"],
      stdout: stdout,
      stderr: stderr,
      github: github,
      now: now
    )

    expect(exit_code).to eq(0)
    expect(stdout.string).to include("alice")
  end

  it "keeps default branch only scans explicit for compatibility" do
    empty_scan_stubs(branch_mode: :default)

    exit_code = described_class.run(
      argv: ["acme", "--default-branch-only"],
      stdout: stdout,
      stderr: stderr,
      github: github,
      now: now
    )

    expect(exit_code).to eq(0)
    expect(stdout.string).to include("alice")
  end

  it "prints usage errors" do
    exit_code = described_class.run(argv: [], stdout: stdout, stderr: stderr, github: github, now: now)

    expect(exit_code).to eq(1)
    expect(stdout.string).to eq("")
    expect(stderr.string).to include("error: org is required")
    expect(stderr.string).to include("Usage: ruby lib/cli.rb ORG [DAYS] [options]")
  end

  it "prints invalid day errors" do
    exit_code = described_class.run(argv: ["acme", "soon"], stdout: stdout, stderr: stderr, github: github, now: now)

    expect(exit_code).to eq(1)
    expect(stderr.string).to include("error: days must be a positive integer")
  end

  it "prints the empty active member state" do
    allow(github).to receive(:get)
      .with("orgs/acme/members", per_page: 100)
      .and_return([{ login: "alice" }])
    allow(github).to receive(:get)
      .with("orgs/acme/repos", type: "all", per_page: 100)
      .and_return([])

    exit_code = described_class.run(argv: ["acme"], stdout: stdout, stderr: stderr, github: github, now: now)

    expect(exit_code).to eq(0)
    expect(stdout.string).to include("No active members found.")
  end

  it "prints help and exits successfully" do
    expect do
      described_class.run(argv: ["--help"], stdout: stdout, stderr: stderr, github: github, now: now)
    end.to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }

    expect(stdout.string).to include("Usage: ruby lib/cli.rb ORG [DAYS] [options]")
  end
end
