# CodeReviewer

AI-powered code reviewer that thinks and reviews like Tim. Built with Elixir, using OpenAI's GPT-4 and GitHub's CLI.

## Features

- Reviews GitHub pull requests using 9 focused rule groups based on actual review patterns
- Generates draft PR comments with specific file/line suggestions
- Creates summary notes highlighting areas of concern and praise
- Supports selective rule group application
- Can post reviews directly to GitHub or output for manual review

## Prerequisites

- Elixir 1.18+ and Erlang 27+
- GitHub CLI (`gh`) authenticated with your account
- OpenAI API key

## Installation

### Local Development

```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Run quality checks
mix quality

# Run full precommit suite
mix precommit
```

### Docker Deployment

Build the production image:

```bash
docker build -f Dockerfile.production -t code-reviewer:latest .
```

Run a review:

```bash
docker run --rm \
  -e GITHUB_TOKEN="your-github-token" \
  -e OPENAI_API_KEY="your-openai-key" \
  -e OPENAI_MODEL="gpt-4o" \
  code-reviewer:latest \
  review owner/repo 123
```

## Usage

### Command Line

Review a PR and display results:

```bash
mix review owner/repo 123
```

Review and post comments to GitHub:

```bash
mix review owner/repo 123 --post
```

Review with specific rule groups:

```bash
mix review owner/repo 123 --groups blocking,testing,database
```

Available rule groups:
- `blocking` - Critical blocking issues (N+1 queries, schema changes, etc.)
- `testing` - Testing strategy and coverage
- `organization` - Code organization and structure
- `database` - Database and performance patterns
- `api` - API design and contracts
- `rails` - Rails-specific patterns
- `elixir` - Elixir/Phoenix patterns
- `errors` - Error handling
- `quality` - General code quality

### Environment Variables

Required:
- `GITHUB_TOKEN` - GitHub personal access token (for gh CLI)
- `OPENAI_API_KEY` - OpenAI API key

Optional:
- `OPENAI_MODEL` - OpenAI model to use (default: "gpt-4o")

## Architecture

- **RuleGroups** - 9 focused rule groups derived from 1,241 analyzed PR comments
- **GitHubClient** - Wrapper around `gh` CLI for fetching PR data
- **LLMClient** - OpenAI API integration for code review
- **Reviewer** - Main orchestrator coordinating the review workflow
- **OutputFormatter** - Formats findings into GitHub-ready comments and summaries

## Development

This project follows Test-Driven Development (TDD) using the Red-Green-Refactor cycle:

1. Write failing test (RED)
2. Implement minimum code to pass (GREEN)
3. Refactor while keeping tests green

Run tests with:

```bash
# All tests
mix test

# Exclude integration tests
mix test --exclude integration

# Only integration tests
mix test --only integration
```

Quality checks:

```bash
# Format code
mix format

# Run Credo (code quality)
mix credo --strict

# Run Sobelow (security)
mix sobelow --config

# Run all quality checks
mix quality

# Run everything (format + quality + tests)
mix precommit
```

## Project Status

See [STATUS.md](STATUS.md) for detailed project status and development roadmap.

