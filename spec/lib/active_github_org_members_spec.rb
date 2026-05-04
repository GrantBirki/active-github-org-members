# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/active_github_org_members"

describe ActiveGitHubOrgMembers do
  let(:now) { Time.utc(2026, 5, 4, 12, 0, 0) }
  let(:github) { double("github") }

  def commit(sha:, author: nil, committer: nil)
    {
      sha: sha,
      author: author && { login: author },
      committer: committer && { login: committer },
    }
  end

  def stub_org_scan
    allow(github).to receive(:get)
      .with("orgs/acme/members", per_page: 100)
      .and_return([{ login: "alice" }, { login: "bob" }, { login: "carol" }])

    allow(github).to receive(:get)
      .with("orgs/acme/repos", type: "all", per_page: 100)
      .and_return([
        { full_name: "acme/api", default_branch: "main" },
        { full_name: "acme/web", default_branch: "trunk" },
      ])

    allow(github).to receive(:get)
      .with("repos/acme/api/branches", per_page: 100)
      .and_return([{ name: "main" }, { name: "feature" }])

    allow(github).to receive(:get)
      .with("repos/acme/web/branches", per_page: 100)
      .and_return([{ name: "trunk" }])

    allow(github).to receive(:get)
      .with("repos/acme/api/commits", sha: "main", since: "2026-02-03T12:00:00Z", per_page: 100)
      .and_return([
        commit(sha: "a1", author: "alice"),
        commit(sha: "bot", author: "dependabot"),
      ])

    allow(github).to receive(:get)
      .with("repos/acme/api/commits", sha: "feature", since: "2026-02-03T12:00:00Z", per_page: 100)
      .and_return([
        commit(sha: "a1", author: "alice"),
        commit(sha: "b1", author: "bob", committer: "carol"),
      ])

    allow(github).to receive(:get)
      .with("repos/acme/web/commits", sha: "trunk", since: "2026-02-03T12:00:00Z", per_page: 100)
      .and_return([
        commit(sha: "c1", author: "carol"),
      ])
  end

  describe "#scan" do
    it "returns active org members with commit and repository counts" do
      stub_org_scan

      result = described_class.new(org: "acme", days: 90, github: github, all_branches: true, now: now).scan

      expect(result.to_h).to include(
        org: "acme",
        days: 90,
        since: "2026-02-03T12:00:00Z",
        total_members: 3,
        active_members_count: 3,
        inactive_members_count: 0,
        commits_scanned: 4,
        repositories_scanned: ["acme/api", "acme/web"],
        repositories_failed: []
      )
      expect(result.active_members).to eq([
        { login: "carol", commits: 2, repositories: ["acme/api", "acme/web"] },
        { login: "alice", commits: 1, repositories: ["acme/api"] },
        { login: "bob", commits: 1, repositories: ["acme/api"] },
      ])
    end

    it "scans only default branches by default" do
      user_resource = Struct.new(:login, keyword_init: true)
      repo_resource = Struct.new(:full_name, :default_branch, keyword_init: true)
      commit_resource = Struct.new(:sha, :author, :committer, keyword_init: true)

      allow(github).to receive(:get)
        .with("orgs/acme/members", per_page: 100)
        .and_return([user_resource.new(login: "alice")])
      allow(github).to receive(:get)
        .with("orgs/acme/repos", type: "all", per_page: 100)
        .and_return([repo_resource.new(full_name: "acme/api", default_branch: "main")])
      allow(github).to receive(:get)
        .with("repos/acme/api/commits", sha: "main", since: "2026-02-03T12:00:00Z", per_page: 100)
        .and_return([commit_resource.new(sha: "a1", author: user_resource.new(login: "alice"))])

      result = described_class.new(org: "acme", days: 90, github: github, now: now).scan

      expect(result.active_members).to eq([
        { login: "alice", commits: 1, repositories: ["acme/api"] },
      ])
    end

    it "tracks repositories that fail without stopping the scan" do
      allow(github).to receive(:get)
        .with("orgs/acme/members", per_page: 100)
        .and_return([{ login: "alice" }])
      allow(github).to receive(:get)
        .with("orgs/acme/repos", type: "all", per_page: 100)
        .and_return([{ full_name: "acme/api", default_branch: "main" }])
      allow(github).to receive(:get)
        .with("repos/acme/api/commits", sha: "main", since: "2026-02-03T12:00:00Z", per_page: 100)
        .and_raise(StandardError, "nope")

      result = described_class.new(org: "acme", github: github, now: now).scan

      expect(result.repositories_scanned).to eq([])
      expect(result.repositories_failed).to eq([
        { full_name: "acme/api", error: "StandardError: nope" },
      ])
      expect(result.active_members).to eq([])
    end
  end

  describe "#initialize" do
    it "defaults to a 90 day lookback" do
      allow(github).to receive(:get)
        .with("orgs/acme/members", per_page: 100)
        .and_return([])
      allow(github).to receive(:get)
        .with("orgs/acme/repos", type: "all", per_page: 100)
        .and_return([])

      result = described_class.new(org: " acme ", github: github, now: now).scan

      expect(result.days).to eq(90)
      expect(result.since).to eq(Time.utc(2026, 2, 3, 12, 0, 0))
    end

    it "rejects missing orgs" do
      expect do
        described_class.new(org: " ", github: github)
      end.to raise_error(ArgumentError, "org is required")
    end

    it "rejects invalid days" do
      expect do
        described_class.new(org: "acme", days: 0, github: github)
      end.to raise_error(ArgumentError, "days must be a positive integer")
    end
  end
end
