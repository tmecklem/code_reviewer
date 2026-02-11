#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'time'

class PreferenceAnalyzer
  def initialize(json_file)
    @data = JSON.parse(File.read(json_file))
    @all_comments = []
    @findings = {
      testing_preferences: [],
      code_organization: [],
      architecture: [],
      code_quality: [],
      style_conventions: [],
      tone_patterns: [],
      common_phrases: Hash.new(0),
      approval_patterns: []
    }
  end

  def analyze
    extract_all_comments
    analyze_testing_preferences
    analyze_code_organization
    analyze_architecture_preferences
    analyze_code_quality
    analyze_style_and_tone
    analyze_approval_patterns

    generate_report
  end

  private

  def extract_all_comments
    @data['prs'].each do |pr|
      # Extract inline review comments
      pr['review_comments'].each do |comment|
        @all_comments << {
          type: 'review_comment',
          body: comment['body'],
          path: comment['path'],
          diff_hunk: comment['diff_hunk'],
          pr_title: pr['pr_title'],
          pr_url: pr['pr_url'],
          repository: pr['repository']
        }
      end

      # Extract general review comments
      pr['reviews'].each do |review|
        next unless review['body'] && !review['body'].strip.empty?

        @all_comments << {
          type: 'review',
          body: review['body'],
          state: review['state'],
          pr_title: pr['pr_title'],
          pr_url: pr['pr_url'],
          repository: pr['repository']
        }
      end
    end

    warn "Extracted #{@all_comments.length} total comments"
  end

  def analyze_testing_preferences
    test_keywords = [
      'test', 'spec', 'request spec', 'system spec', 'feature spec',
      'integration test', 'unit test', 'mock', 'stub', 'factory',
      'coverage', 'test case', 'testing', 'rspec', 'capybara'
    ]

    test_comments = @all_comments.select do |comment|
      body_lower = comment[:body].downcase
      test_keywords.any? { |keyword| body_lower.include?(keyword) }
    end

    warn "Found #{test_comments.length} testing-related comments"

    test_comments.each do |comment|
      # Look for specific patterns
      body = comment[:body]

      finding = {
        comment: body,
        context: comment[:pr_title],
        url: comment[:pr_url],
        pattern: identify_testing_pattern(body)
      }

      @findings[:testing_preferences] << finding if finding[:pattern]
    end
  end

  def identify_testing_pattern(body)
    body_lower = body.downcase

    patterns = []

    # Test hierarchy preferences
    if body_lower.match?(/request spec|controller spec/) && body_lower.match?(/system spec|feature spec/)
      patterns << "prefers_request_specs_over_system_specs"
    end

    if body_lower.include?('push') && body_lower.match?(/test|spec/)
      patterns << "push_tests_down_hierarchy"
    end

    if body_lower.match?(/move.*test|test.*move/) || body_lower.match?(/should be.*test/)
      patterns << "test_organization"
    end

    if body_lower.include?('mock') || body_lower.include?('stub')
      patterns << "mocking_stubbing_preference"
    end

    if body_lower.include?('cover') || body_lower.include?('test case')
      patterns << "test_coverage"
    end

    patterns.empty? ? nil : patterns.join(", ")
  end

  def analyze_code_organization
    org_keywords = [
      'extract', 'refactor', 'move', 'separate', 'consolidate',
      'module', 'class', 'method', 'concern', 'service', 'helper',
      'organize', 'structure', 'split'
    ]

    org_comments = @all_comments.select do |comment|
      body_lower = comment[:body].downcase
      org_keywords.any? { |keyword| body_lower.include?(keyword) }
    end

    warn "Found #{org_comments.length} organization-related comments"

    org_comments.each do |comment|
      body = comment[:body]

      finding = {
        comment: body,
        context: comment[:pr_title],
        url: comment[:pr_url],
        pattern: identify_organization_pattern(body)
      }

      @findings[:code_organization] << finding if finding[:pattern]
    end
  end

  def identify_organization_pattern(body)
    body_lower = body.downcase

    patterns = []

    if body_lower.match?(/extract.*method|method.*extract/)
      patterns << "extract_methods"
    end

    if body_lower.match?(/service|service object/)
      patterns << "service_objects"
    end

    if body_lower.match?(/concern|module/)
      patterns << "modules_concerns"
    end

    if body_lower.match?(/separate|split/)
      patterns << "separation_concerns"
    end

    patterns.empty? ? nil : patterns.join(", ")
  end

  def analyze_architecture_preferences
    arch_keywords = [
      'architecture', 'pattern', 'design', 'dependency', 'coupling',
      'solid', 'dry', 'responsibility', 'interface', 'abstraction'
    ]

    arch_comments = @all_comments.select do |comment|
      body_lower = comment[:body].downcase
      arch_keywords.any? { |keyword| body_lower.include?(keyword) }
    end

    warn "Found #{arch_comments.length} architecture-related comments"

    arch_comments.each do |comment|
      @findings[:architecture] << {
        comment: comment[:body],
        context: comment[:pr_title],
        url: comment[:pr_url]
      }
    end
  end

  def analyze_code_quality
    quality_keywords = [
      'naming', 'variable', 'clarity', 'readable', 'clean',
      'duplication', 'duplicate', 'dry', 'magic', 'constant',
      'edge case', 'error handling', 'validation', 'nil check'
    ]

    quality_comments = @all_comments.select do |comment|
      body_lower = comment[:body].downcase
      quality_keywords.any? { |keyword| body_lower.include?(keyword) }
    end

    warn "Found #{quality_comments.length} code quality comments"

    quality_comments.each do |comment|
      @findings[:code_quality] << {
        comment: comment[:body],
        context: comment[:pr_title],
        url: comment[:pr_url],
        pattern: identify_quality_pattern(comment[:body])
      }
    end
  end

  def identify_quality_pattern(body)
    body_lower = body.downcase

    patterns = []

    if body_lower.match?(/naming|name|called|rename/)
      patterns << "naming_conventions"
    end

    if body_lower.include?('nil') || body_lower.include?('null')
      patterns << "nil_handling"
    end

    if body_lower.include?('edge case') || body_lower.include?('corner case')
      patterns << "edge_cases"
    end

    if body_lower.include?('magic') || body_lower.include?('constant')
      patterns << "magic_values"
    end

    patterns.empty? ? nil : patterns.join(", ")
  end

  def analyze_style_and_tone
    # Analyze tone by looking at review states and language
    approval_count = 0
    request_changes_count = 0
    comment_only_count = 0

    @all_comments.each do |comment|
      case comment[:state]
      when 'APPROVED'
        approval_count += 1
      when 'CHANGES_REQUESTED'
        request_changes_count += 1
      when 'COMMENTED'
        comment_only_count += 1
      end

      # Track common phrases
      body = comment[:body]
      extract_phrases(body)

      # Analyze tone
      @findings[:tone_patterns] << analyze_tone(body, comment)
    end

    @findings[:tone_patterns] = @findings[:tone_patterns].compact.uniq

    @findings[:review_stats] = {
      approvals: approval_count,
      changes_requested: request_changes_count,
      comments: comment_only_count
    }
  end

  def extract_phrases(body)
    # Look for common starting phrases
    body.scan(/^(.*?)[.!?]/).flatten.each do |sentence|
      sentence = sentence.strip
      next if sentence.length < 10 || sentence.length > 100

      # Normalize
      normalized = sentence.downcase
      @findings[:common_phrases][normalized] += 1
    end
  end

  def analyze_tone(body, comment)
    body_lower = body.downcase

    tone = {
      comment: body,
      characteristics: []
    }

    # Direct vs suggestive
    if body_lower.match?(/should|must|need to/)
      tone[:characteristics] << "directive"
    elsif body_lower.match?(/could|might|consider|what about|how about/)
      tone[:characteristics] << "suggestive"
    end

    # Questioning
    if body.include?('?')
      tone[:characteristics] << "questioning"
    end

    # Praising
    if body_lower.match?(/nice|good|great|love|excellent/)
      tone[:characteristics] << "positive"
    end

    # Concerned
    if body_lower.match?(/concern|worry|careful|watch out/)
      tone[:characteristics] << "cautionary"
    end

    tone[:characteristics].empty? ? nil : tone
  end

  def analyze_approval_patterns
    # Group by review state
    approval_reviews = @all_comments.select { |c| c[:state] == 'APPROVED' }
    changes_reviews = @all_comments.select { |c| c[:state] == 'CHANGES_REQUESTED' }

    @findings[:approval_patterns] = {
      approval_comments: approval_reviews.map { |r| r[:body] }.compact,
      changes_requested_comments: changes_reviews.map { |r| r[:body] }.compact
    }
  end

  def generate_report
    output = {
      username: @data['username'],
      analysis_date: Time.now.iso8601,
      total_comments_analyzed: @all_comments.length,
      findings: @findings,
      top_phrases: @findings[:common_phrases].sort_by { |_, count| -count }.first(20).to_h
    }

    File.write('preferences_analysis.json', JSON.pretty_generate(output))

    # Also create a markdown report
    create_markdown_report(output)

    warn "\n#{'=' * 60}"
    warn "✓ Analysis complete"
    warn "  - JSON report: preferences_analysis.json"
    warn "  - Markdown report: preferences_analysis.md"
    warn "#{'=' * 60}"
  end

  def create_markdown_report(output)
    md = []
    md << "# Code Review Preferences Analysis"
    md << ""
    md << "**Reviewer:** #{output[:username]}"
    md << "**Analysis Date:** #{output[:analysis_date]}"
    md << "**Total Comments Analyzed:** #{output[:total_comments_analyzed]}"
    md << ""

    md << "## Testing Preferences"
    md << ""
    if @findings[:testing_preferences].empty?
      md << "No specific testing patterns identified."
    else
      @findings[:testing_preferences].group_by { |f| f[:pattern] }.each do |pattern, findings|
        md << "### #{pattern}"
        md << ""
        findings.first(5).each do |finding|
          md << "- **#{finding[:context]}**"
          md << "  ```"
          md << "  #{finding[:comment]}"
          md << "  ```"
          md << "  [Link](#{finding[:url]})"
          md << ""
        end
      end
    end

    md << "## Code Organization Preferences"
    md << ""
    if @findings[:code_organization].empty?
      md << "No specific organization patterns identified."
    else
      @findings[:code_organization].group_by { |f| f[:pattern] }.each do |pattern, findings|
        md << "### #{pattern}"
        md << ""
        findings.first(5).each do |finding|
          md << "- **#{finding[:context]}**"
          md << "  ```"
          md << "  #{finding[:comment]}"
          md << "  ```"
          md << ""
        end
      end
    end

    md << "## Code Quality Patterns"
    md << ""
    @findings[:code_quality].group_by { |f| f[:pattern] }.each do |pattern, findings|
      next unless pattern
      md << "### #{pattern}"
      md << ""
      findings.first(3).each do |finding|
        md << "- #{finding[:comment]}"
        md << ""
      end
    end

    md << "## Top 20 Common Phrases"
    md << ""
    output[:top_phrases].each do |phrase, count|
      md << "- (#{count}x) #{phrase}"
    end
    md << ""

    md << "## Tone Characteristics"
    md << ""
    tone_summary = @findings[:tone_patterns]
      .flat_map { |t| t[:characteristics] }
      .tally
      .sort_by { |_, count| -count }

    tone_summary.each do |characteristic, count|
      md << "- **#{characteristic}**: #{count} instances"
    end
    md << ""

    File.write('preferences_analysis.md', md.join("\n"))
  end
end

if __FILE__ == $PROGRAM_NAME
  analyzer = PreferenceAnalyzer.new('pr_comments.json')
  analyzer.analyze
end
