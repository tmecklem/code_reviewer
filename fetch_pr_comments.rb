#!/usr/bin/env ruby
# frozen_string_literal: true

# Fetch PR review comments from GitHub for the authenticated user.
# This script collects all PR review comments made in the last 5 years.

require 'json'
require 'date'
require 'open3'

class PRCommentFetcher
  def initialize
    @username = nil
  end

  def run_gh_command(*args)
    stdout, stderr, status = Open3.capture3('gh', *args)
    unless status.success?
      warn "Error running gh command: #{stderr}"
      raise "Command failed: gh #{args.join(' ')}"
    end
    stdout
  end

  def current_user
    @username ||= begin
      query = '{ viewer { login } }'
      result = run_gh_command('api', 'graphql', '-f', "query=query #{query}")
      data = JSON.parse(result)
      data['data']['viewer']['login']
    end
  end

  def fetch_reviewed_prs(username, created_after)
    warn "Searching for PRs reviewed by #{username} since #{created_after}..."

    # Use gh search prs with --reviewed-by flag
    # Fetch in batches using --limit, GitHub Search API has a 1000 result limit
    result = run_gh_command(
      'search', 'prs',
      '--reviewed-by', username,
      '--created', ">=#{created_after}",
      '--limit', '1000',
      '--json', 'number,title,url,repository,createdAt,author'
    )

    prs = JSON.parse(result)
    warn "Found #{prs.length} PRs reviewed by #{username}"
    prs
  rescue => e
    warn "Error searching for PRs: #{e.message}"
    []
  end

  def fetch_pr_review_comments(repo_name, pr_number)
    begin
      # Fetch review comments (comments on specific code lines)
      comments_result = run_gh_command(
        'api',
        "/repos/#{repo_name}/pulls/#{pr_number}/comments",
        '--paginate'
      )
      review_comments = JSON.parse(comments_result)

      # Fetch general PR review comments
      reviews_result = run_gh_command(
        'api',
        "/repos/#{repo_name}/pulls/#{pr_number}/reviews",
        '--paginate'
      )
      reviews = JSON.parse(reviews_result)

      {
        review_comments: review_comments.is_a?(Array) ? review_comments : [],
        reviews: reviews.is_a?(Array) ? reviews : []
      }
    rescue => e
      warn "Error fetching comments for PR #{repo_name}##{pr_number}: #{e.message}"
      { review_comments: [], reviews: [] }
    end
  end

  def fetch_all_comments
    warn "Fetching GitHub PR review comments..."

    username = current_user
    warn "Authenticated as: #{username}"

    # Calculate date from 5 years ago
    five_years_ago = Date.today - (5 * 365)
    date_str = five_years_ago.strftime('%Y-%m-%d')

    # Search for PRs reviewed by the user
    prs = fetch_reviewed_prs(username, date_str)

    # Collect all comments
    all_data = {
      username: username,
      fetch_date: DateTime.now.iso8601,
      search_from_date: date_str,
      total_prs: prs.length,
      prs: []
    }

    prs.each_with_index do |pr, i|
      warn "\nProcessing PR #{i + 1}/#{prs.length}: #{pr['title']}"
      warn "  Repo: #{pr['repository']['nameWithOwner']}"
      warn "  URL: #{pr['url']}"

      repo_name = pr['repository']['nameWithOwner']
      pr_number = pr['number']

      comments_data = fetch_pr_review_comments(repo_name, pr_number)

      # Filter to only include comments by the authenticated user
      user_review_comments = comments_data[:review_comments].select do |c|
        c.dig('user', 'login') == username
      end

      user_reviews = comments_data[:reviews].select do |r|
        r.dig('user', 'login') == username && r['body']
      end

      if user_review_comments.any? || user_reviews.any?
        all_data[:prs] << {
          pr_number: pr_number,
          pr_title: pr['title'],
          pr_url: pr['url'],
          repository: repo_name,
          pr_created_at: pr['createdAt'],
          pr_author: pr.dig('author', 'login'),
          review_comments: user_review_comments,
          reviews: user_reviews,
          total_comments: user_review_comments.length + user_reviews.length
        }
        warn "  Found #{user_review_comments.length} review comments and #{user_reviews.length} reviews"
      else
        warn "  No comments found from #{username}"
      end
    end

    # Calculate statistics
    total_review_comments = all_data[:prs].sum { |pr| pr[:review_comments].length }
    total_reviews = all_data[:prs].sum { |pr| pr[:reviews].length }

    all_data[:statistics] = {
      total_review_comments: total_review_comments,
      total_reviews: total_reviews,
      total_comments: total_review_comments + total_reviews,
      prs_with_comments: all_data[:prs].length
    }

    all_data
  end

  def save_to_file(data, filename = 'pr_comments.json')
    File.write(filename, JSON.pretty_generate(data))

    warn "\n#{'=' * 60}"
    warn "✓ Data saved to #{filename}"
    warn "\nStatistics:"
    warn "  Total PRs searched: #{data[:total_prs]}"
    warn "  PRs with your comments: #{data[:statistics][:prs_with_comments]}"
    warn "  Total review comments: #{data[:statistics][:total_review_comments]}"
    warn "  Total reviews: #{data[:statistics][:total_reviews]}"
    warn "  Total comments: #{data[:statistics][:total_comments]}"
    warn "#{'=' * 60}"
  end

  def run
    data = fetch_all_comments
    save_to_file(data)
  end
end

if __FILE__ == $PROGRAM_NAME
  fetcher = PRCommentFetcher.new
  fetcher.run
end
