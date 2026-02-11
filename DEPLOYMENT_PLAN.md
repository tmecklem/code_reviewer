# Code Reviewer Deployment Strategy

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Review Engine (Core)                     │
│  - Loads REVIEW_PREFERENCES.md as context                   │
│  - Uses Claude API to analyze code changes                  │
│  - Generates review comments in your style                  │
└─────────────────────────────────────────────────────────────┘
                            ▲
                            │
            ┌───────────────┴───────────────┐
            │                               │
┌───────────▼──────────┐      ┌────────────▼─────────────┐
│  Local CLI           │      │  GitHub Action           │
│  (Claude Code)       │      │  (Automated)             │
│                      │      │                          │
│  • Manual trigger    │      │  • On PR tagged          │
│  • Test before push  │      │  • On PR opened          │
│  • Local changes     │      │  • On push to PR         │
│  • Specific PR       │      │  • Posts comments        │
└──────────────────────┘      └──────────────────────────┘
```

## Recommended Approach: Hybrid Deployment

### Phase 1: Core Review Engine (Ruby)
**File:** `lib/code_reviewer.rb`

**Responsibilities:**
- Load your preferences as context
- Call Claude API with preferences + code diff
- Parse response into actionable comments
- Format output (CLI vs GitHub comment format)

**Why Ruby?**
- You already have Ruby scripts here
- Easy to test locally
- Can be run in GitHub Actions (ruby/setup-ruby)
- Fast enough for this use case

### Phase 2: Local CLI
**File:** `bin/review`

**Usage:**
```bash
# Review current changes
./bin/review

# Review specific PR
./bin/review --pr 123

# Review specific files
./bin/review app/models/user.rb

# Dry run (don't post comments)
./bin/review --dry-run --pr 123
```

**Perfect for:**
- Testing your reviewer before pushing
- Quick local feedback while coding
- Iterating on the review logic

### Phase 3: GitHub Action
**File:** `.github/workflows/code-review.yml`

**Triggers:**
1. **When you're tagged** (most common for you)
   ```yaml
   on:
     pull_request_review_comment:
       types: [created]
   ```

2. **On PR events** (optional, can be noisy)
   ```yaml
   on:
     pull_request:
       types: [opened, synchronize]
   ```

3. **Manual trigger** (via workflow_dispatch)
   ```yaml
   on:
     workflow_dispatch:
   ```

**Flow:**
1. Checkout code
2. Fetch PR diff
3. Run review engine with your preferences
4. Post comments to PR (using `gh` CLI or GitHub API)

---

## Implementation Options

### Option A: Rule-Based + AI (Recommended)

**Two-tier approach:**

**Tier 1: Fast, Deterministic Checks**
- N+1 detection (via `bullet` gem or static analysis)
- Schema change detection (parse schema.rb diff)
- ENV usage detection (grep for `ENV[`)
- Magic number detection (AST parsing)
- Test type detection (count system vs request specs)

**Tier 2: AI Review**
- Send to Claude API with your preferences as context
- Only for complex/subjective feedback
- More expensive but captures your "style"

**Benefits:**
- Fast feedback on obvious issues
- Cheaper (deterministic checks are free)
- AI handles nuanced/contextual feedback

### Option B: Pure AI (Simpler, More Expensive)

**Send everything to Claude:**
- Include full REVIEW_PREFERENCES.md as context
- Include PR diff
- Ask Claude to review in your style

**Benefits:**
- Simpler implementation
- More comprehensive feedback
- Handles edge cases better

**Drawbacks:**
- More expensive (every PR costs tokens)
- Slower
- Harder to debug when it gets things wrong

### Option C: Hybrid with Human-in-Loop

**Best of both worlds:**
1. AI generates suggested comments
2. You review suggestions locally first
3. Approve/edit/reject before posting

**Perfect for:**
- Building trust in the system
- Avoiding embarrassing AI mistakes
- Learning what works and doesn't

---

## Cost Considerations

### Claude API Pricing (as of 2025)
- Claude Sonnet: ~$3 per million input tokens, ~$15 per million output tokens
- Typical PR review: ~10K tokens input (preferences + diff), ~2K tokens output
- **Cost per review:** ~$0.06

### GitHub Actions
- **Public repos:** Free unlimited minutes
- **Private repos:** 2,000 minutes/month free, then $0.008/minute
- Typical review job: ~2 minutes
- **Cost per review:** ~$0.02 (private repos only)

### Total Cost Estimate
- **100 PRs/month:** ~$8/month (pure AI approach)
- **100 PRs/month:** ~$2-3/month (hybrid approach with deterministic checks)

---

## Recommended Implementation Plan

### Week 1: Core Engine + Local CLI
1. Build `CodeReviewer` class with Claude API integration
2. Create CLI wrapper for local testing
3. Test against your actual PRs manually
4. Iterate on prompt engineering to match your style

### Week 2: Deterministic Checks
1. Add N+1 detection
2. Add schema change detection
3. Add ENV usage detection
4. Add magic number detection
5. Test against known "bad" PRs

### Week 3: GitHub Action
1. Create workflow file
2. Configure secrets (ANTHROPIC_API_KEY, GITHUB_TOKEN)
3. Test on a sample repo
4. Deploy to your active repos

### Week 4: Refinement
1. Monitor false positives/negatives
2. Tune thresholds
3. Add ignore patterns
4. Document for your team

---

## Security Considerations

### API Keys
- **ANTHROPIC_API_KEY:** Store in GitHub Secrets
- **GITHUB_TOKEN:** Auto-provided by GitHub Actions
- Never commit keys to the repo

### Rate Limiting
- Claude API: 50 requests/minute (Sonnet)
- GitHub API: 5,000 requests/hour (with token)
- Add exponential backoff retry logic

### Access Control
- GitHub Action runs with PR author's permissions by default
- Be careful with `pull_request_target` (runs with repo permissions)
- Use `pull_request` for safety (can't access secrets from forks)

---

## Alternative: GitHub App vs Action

### GitHub Action (Recommended)
**Pros:**
- Simpler to set up
- No hosting required
- Runs in GitHub's infrastructure
- Easy to configure per-repo

**Cons:**
- Limited to repos you own/admin
- Requires setup in each repo
- Can't be "installed" by others easily

### GitHub App
**Pros:**
- Can be installed across orgs/repos
- Better permissions model
- Can be used by others
- More professional

**Cons:**
- Requires hosting (webhook receiver)
- More complex setup
- Ongoing hosting costs
- Overkill for personal use

**Recommendation:** Start with GitHub Action, migrate to App if you want to share with others

---

## Next Steps

Would you like me to:

1. **Build the core review engine** (CodeReviewer class with Claude API)?
2. **Create the local CLI** for testing in Claude Code?
3. **Set up the GitHub Action** for automated reviews?
4. **Build deterministic checks** first (faster, cheaper)?
5. **All of the above** (full implementation)?

Let me know your priority and I'll start building!
