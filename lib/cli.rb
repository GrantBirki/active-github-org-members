# frozen_string_literal: true

require "optparse"

require_relative "active_github_org_members"

class ActiveGitHubOrgMembers
  class CLI
    def self.run(...)
      new(...).run
    end

    def initialize(argv: ARGV, stdout: $stdout, stderr: $stderr, github: nil, now: Time.now.utc)
      @argv = argv.dup
      @stdout = stdout
      @stderr = stderr
      @github = github
      @now = now
    end

    def run
      options = parse_options
      scanner = ActiveGitHubOrgMembers.new(
        org: options.fetch(:org),
        days: options.fetch(:days),
        github: @github || GitHub.new,
        all_branches: options.fetch(:all_branches),
        now: @now
      )
      result = scanner.scan

      if options.fetch(:json)
        @stdout.puts(result.to_json)
      else
        @stdout.puts(format_result(result))
      end

      0
    rescue OptionParser::ParseError, ArgumentError => e
      @stderr.puts("error: #{e.message}")
      @stderr.puts
      @stderr.puts(option_parser)
      1
    end

    private

    def parse_options
      options = {
        days: ActiveGitHubOrgMembers::DEFAULT_DAYS,
        json: false,
        all_branches: false,
      }

      parser = option_parser(options)
      parser.parse!(@argv)

      options[:org] = @argv.shift || raise(ArgumentError, "org is required")
      options[:days] = @argv.shift if @argv.first
      raise ArgumentError, "unexpected arguments: #{@argv.join(' ')}" unless @argv.empty?

      options[:days] = parse_days(options.fetch(:days))
      options
    end

    def option_parser(options = nil)
      OptionParser.new do |parser|
        parser.banner = "Usage: ruby lib/cli.rb ORG [DAYS] [options]"
        parser.separator("")
        parser.separator("Examples:")
        parser.separator("  ruby lib/cli.rb octo-org")
        parser.separator("  ruby lib/cli.rb octo-org 30 --json")
        parser.separator("")

        if options
          parser.on("-d", "--days DAYS", Integer, "Days to look back (default: 90)") do |days|
            options[:days] = days
          end
          parser.on("--all-branches", "Scan every branch in each repository") do
            options[:all_branches] = true
          end
          parser.on("--default-branch-only", "Only scan each repository's default branch") do
            options[:all_branches] = false
          end
          parser.on("--json", "Emit JSON output") do
            options[:json] = true
          end
        end

        parser.on("-h", "--help", "Show this help") do
          @stdout.puts(parser)
          exit(0)
        end
      end
    end

    def parse_days(days)
      Integer(days).tap do |value|
        raise ArgumentError, "days must be greater than 0" unless value.positive?
      end
    rescue ArgumentError, TypeError
      raise ArgumentError, "days must be a positive integer"
    end

    def format_result(result)
      lines = [
        "Active GitHub org members for #{result.org}",
        "Lookback: #{result.days} days (since #{result.since.iso8601})",
        "Active members: #{result.active_count} / #{result.total_members}",
        "Commits scanned: #{result.commits_scanned}",
        "Repositories scanned: #{result.repositories_scanned.length}",
      ]

      lines << "Repositories failed: #{result.repositories_failed.length}" if result.repositories_failed.any?
      lines << ""

      if result.active_members.empty?
        lines << "No active members found."
      else
        lines << "login\tcommits\trepositories"
        result.active_members.each do |member|
          lines << "#{member[:login]}\t#{member[:commits]}\t#{member[:repositories].join(',')}"
        end
      end

      lines.join("\n")
    end
  end
end

exit(ActiveGitHubOrgMembers::CLI.run) if $PROGRAM_NAME == __FILE__
