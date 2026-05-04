# frozen_string_literal: true

require "json"
require "set"
require "time"

require_relative "github"

class ActiveGitHubOrgMembers
  DEFAULT_DAYS = 90
  SECONDS_PER_DAY = 86_400

  Result = Struct.new(
    :org,
    :days,
    :since,
    :total_members,
    :active_members,
    :repositories_scanned,
    :repositories_failed,
    :commits_scanned,
    keyword_init: true
  ) do
    def active_count
      active_members.length
    end

    def inactive_count
      total_members - active_count
    end

    def to_h
      {
        org: org,
        days: days,
        since: since.iso8601,
        total_members: total_members,
        active_members_count: active_count,
        inactive_members_count: inactive_count,
        commits_scanned: commits_scanned,
        repositories_scanned: repositories_scanned,
        repositories_failed: repositories_failed,
        active_members: active_members,
      }
    end

    def to_json(*args)
      JSON.pretty_generate(to_h, *args)
    end
  end

  def initialize(org:, days: DEFAULT_DAYS, github: GitHub.new, all_branches: false, now: Time.now.utc)
    @org = validate_org(org)
    @days = validate_days(days)
    @github = github
    @all_branches = all_branches
    @now = now.utc
    @since = @now - (@days * SECONDS_PER_DAY)
  end

  def scan
    members = fetch_org_members
    active_members = {}
    repositories_scanned = []
    repositories_failed = []
    commits_scanned = 0

    fetch_org_repositories.each do |repo|
      full_name = resource_value(repo, :full_name)
      begin
        commits_scanned += scan_repository(repo, members, active_members)
        repositories_scanned << full_name
      rescue StandardError => e
        repositories_failed << {
          full_name: full_name,
          error: "#{e.class}: #{e.message}",
        }
      end
    end

    Result.new(
      org: @org,
      days: @days,
      since: @since,
      total_members: members.length,
      active_members: format_active_members(active_members),
      repositories_scanned: repositories_scanned.sort,
      repositories_failed: repositories_failed.sort_by { |repo| repo[:full_name].to_s },
      commits_scanned: commits_scanned
    )
  end

  private

  def validate_org(org)
    org = org.to_s.strip
    raise ArgumentError, "org is required" if org.empty?

    org
  end

  def validate_days(days)
    days = Integer(days)
    raise ArgumentError, "days must be greater than 0" unless days.positive?

    days
  rescue ArgumentError, TypeError
    raise ArgumentError, "days must be a positive integer"
  end

  def fetch_org_members
    @github.get("orgs/#{@org}/members", per_page: 100).filter_map do |member|
      resource_value(member, :login)
    end.to_set
  end

  def fetch_org_repositories
    @github.get("orgs/#{@org}/repos", type: "all", per_page: 100)
  end

  def scan_repository(repo, members, active_members)
    full_name = resource_value(repo, :full_name)
    seen_shas = Set.new
    commits_scanned = 0

    branch_names(repo).each do |branch_name|
      fetch_commits(full_name, branch_name).each do |commit|
        sha = resource_value(commit, :sha)
        next if sha && seen_shas.include?(sha)

        seen_shas << sha if sha
        commits_scanned += 1

        commit_logins(commit).each do |login|
          next unless members.include?(login)

          record_active_member(active_members, login, full_name)
        end
      end
    end

    commits_scanned
  end

  def branch_names(repo)
    return [resource_value(repo, :default_branch)].compact unless @all_branches

    full_name = resource_value(repo, :full_name)
    @github.get("repos/#{full_name}/branches", per_page: 100).filter_map do |branch|
      resource_value(branch, :name)
    end
  end

  def fetch_commits(full_name, branch_name)
    @github.get(
      "repos/#{full_name}/commits",
      sha: branch_name,
      since: @since.iso8601,
      per_page: 100
    )
  end

  def commit_logins(commit)
    author = resource_value(commit, :author)
    author_login = resource_value(author, :login)
    committer = resource_value(commit, :committer)
    committer_login = resource_value(committer, :login)

    [author_login, committer_login].compact.uniq
  end

  def record_active_member(active_members, login, full_name)
    active_members[login] ||= {
      login: login,
      commits: 0,
      repositories: Set.new,
    }
    active_members[login][:commits] += 1
    active_members[login][:repositories] << full_name
  end

  def format_active_members(active_members)
    active_members.values
      .map do |member|
        {
          login: member[:login],
          commits: member[:commits],
          repositories: member[:repositories].to_a.sort,
        }
      end
      .sort_by { |member| [-member[:commits], member[:login]] }
  end

  def resource_value(resource, key)
    return nil unless resource
    return resource[key] if resource.is_a?(Hash) && resource.key?(key)
    return resource[key.to_s] if resource.is_a?(Hash) && resource.key?(key.to_s)

    resource[key] || resource[key.to_s] if resource.respond_to?(:[])
  end
end
