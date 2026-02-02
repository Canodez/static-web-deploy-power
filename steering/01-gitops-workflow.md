# GitOps Workflow

Git is the single source of truth. All deployments flow from Git. No manual deploys to production.

## Core Principles

1. **Git is the source of truth** — Infrastructure and application state defined in code
2. **Pull requests gate all changes** — No direct commits to main/production branches
3. **Automated deployments** — CI/CD triggers on merge, not manual intervention
4. **Immutable artifacts** — Build once, deploy to multiple environments
5. **Audit trail** — Every deployment traceable to a commit and PR

## Branching Strategy

### Recommended: Trunk-Based Development

```
main (production)
  │
  ├── feature/add-contact-form
  ├── feature/update-hero-section
  ├── fix/broken-link-footer
  └── chore/update-dependencies
```

**Rules:**
- `main` is always deployable
- Feature branches are short-lived (< 1 week)
- All changes via PR to main
- Merge triggers production deployment

### Alternative: Environment Branches

```
main (production)
  │
  └── develop (staging)
        │
        ├── feature/add-contact-form
        └── fix/broken-link-footer
```

**Rules:**
- `develop` deploys to staging
- `main` deploys to production
- PRs: feature → develop → main
- Use for teams requiring staging approval gate

### Multi-Environment Strategy

| Branch | Environment | Trigger | Auto-Deploy |
|--------|-------------|---------|-------------|
| `main` | Production | Merge | Yes |
| `develop` | Staging | Merge | Yes |
| `feature/*` | Preview (optional) | Push | Optional |

## Pull Request Requirements

### Required Checks (Enforce in GitHub/GitLab)

```yaml
# .github/branch-protection.yml (conceptual)
branches:
  main:
    required_status_checks:
      - build
      - lint
      - test
      - security-scan
    required_reviews: 1
    dismiss_stale_reviews: true
    require_code_owner_reviews: true
    restrict_pushes: true
```

### PR Checklist

Before merging, verify:

- [ ] Build succeeds (`npm run build` or equivalent)
- [ ] Linting passes (`npm run lint`)
- [ ] Tests pass (`npm test`)
- [ ] No secrets or credentials in code
- [ ] No console.log/debug statements in production code
- [ ] Assets optimized (images compressed, code minified)
- [ ] Accessibility checked (if applicable)
- [ ] Preview deployment reviewed (if available)

### CODEOWNERS

Create `.github/CODEOWNERS`:

```
# Default owners for everything
* @team-lead @senior-dev

# Frontend specific
/src/components/ @frontend-team
/src/styles/ @frontend-team

# Infrastructure
/buildspec.yml @devops-team
/.github/workflows/ @devops-team
```

## Deployment Flow

### Standard Flow (Trunk-Based)

```
1. Developer creates feature branch
   └── git checkout -b feature/new-page

2. Developer commits changes
   └── git commit -m "Add new landing page"

3. Developer opens PR to main
   └── CI runs: build, lint, test, security scan

4. Reviewer approves PR
   └── Required checks pass

5. PR merged to main
   └── Triggers production deployment

6. CodeBuild deploys to S3
   └── CloudFront invalidation (index.html only)

7. Verify deployment
   └── Check CloudFront URL
```

### Multi-Environment Flow

```
1. feature/* → develop (PR)
   └── Deploy to staging

2. Verify on staging
   └── QA/stakeholder review

3. develop → main (PR)
   └── Deploy to production

4. Tag release (optional)
   └── git tag v1.2.3
```

## Tagging Strategy

### Semantic Versioning (Optional)

For teams that need version tracking:

```bash
# After production deployment
git tag -a v1.2.3 -m "Release 1.2.3: Add contact form"
git push origin v1.2.3
```

**Version Format:** `vMAJOR.MINOR.PATCH`
- MAJOR: Breaking changes
- MINOR: New features
- PATCH: Bug fixes

### Automated Tagging

Add to buildspec.yml post-deploy:

```yaml
post_build:
  commands:
    - |
      if [ "$CODEBUILD_WEBHOOK_HEAD_REF" = "refs/heads/main" ]; then
        VERSION=$(date +%Y.%m.%d-%H%M)
        git tag -a "v$VERSION" -m "Auto-release $VERSION"
        git push origin "v$VERSION"
      fi
```

## Prohibited Actions

### Never Do These

1. **Manual production deploys from laptop**
   ```bash
   # ❌ NEVER DO THIS
   aws s3 sync ./dist s3://production-bucket
   ```
   
   **Why:** No audit trail, bypasses checks, risk of deploying untested code

2. **Direct commits to main**
   ```bash
   # ❌ NEVER DO THIS
   git push origin main
   ```
   
   **Why:** Bypasses code review and CI checks

3. **Force push to shared branches**
   ```bash
   # ❌ NEVER DO THIS
   git push --force origin main
   ```
   
   **Why:** Destroys history, breaks other developers

4. **Committing secrets**
   ```bash
   # ❌ NEVER DO THIS
   API_KEY=sk-12345 # in code
   ```
   
   **Why:** Secrets in Git history are permanent, even after deletion

### Emergency Procedures

If you must deploy urgently:

1. Create hotfix branch from main
2. Make minimal fix
3. Open PR with `[HOTFIX]` prefix
4. Get expedited review (1 reviewer minimum)
5. Merge and deploy via normal CI/CD
6. Document incident

```bash
git checkout main
git pull
git checkout -b hotfix/critical-security-fix
# Make fix
git commit -m "[HOTFIX] Fix XSS vulnerability in contact form"
git push origin hotfix/critical-security-fix
# Open PR immediately
```

## Repository Structure

Recommended structure for static site projects:

```
project-root/
├── .github/
│   ├── workflows/          # GitHub Actions (if using)
│   ├── CODEOWNERS
│   └── pull_request_template.md
├── .kiro/
│   └── hooks/              # Kiro agent hooks
├── src/                    # Source files
├── public/                 # Static assets
├── dist/                   # Build output (gitignored)
├── scripts/
│   ├── deploy.sh
│   └── invalidate.sh
├── buildspec.yml           # CodeBuild spec
├── package.json
├── .gitignore
└── README.md
```

### .gitignore Essentials

```gitignore
# Build output
dist/
build/
out/
.next/

# Dependencies
node_modules/

# Environment files with secrets
.env
.env.local
.env.*.local

# IDE
.idea/
.vscode/
*.swp

# OS
.DS_Store
Thumbs.db

# Logs
*.log
npm-debug.log*

# AWS
.aws/
```

## PR Template

Create `.github/pull_request_template.md`:

```markdown
## Description
<!-- What does this PR do? -->

## Type of Change
- [ ] New feature
- [ ] Bug fix
- [ ] Documentation
- [ ] Refactor
- [ ] Chore (dependencies, config)

## Checklist
- [ ] Build passes locally
- [ ] Linting passes
- [ ] Tests pass (if applicable)
- [ ] No secrets or credentials in code
- [ ] Reviewed my own code
- [ ] Added/updated documentation (if needed)

## Screenshots (if applicable)
<!-- Add screenshots for UI changes -->

## Testing Instructions
<!-- How can reviewers test this? -->
```

---

**Next:** Read `02-ci-cd-codebuild` to set up automated deployments.
