---
name: "static-web-deploy-aws"
displayName: "Static Web Deploy (AWS)"
description: "Production-grade static website deployment to AWS using S3 (private origin), CloudFront with OAC, and GitOps CI/CD via CodeBuild. Secure by default, opinionated for real teams."
keywords: ["static site", "static web app", "website", "S3", "CloudFront", "CDN", "OAC", "origin access control", "deploy", "deployment", "CI/CD", "pipeline", "CodeBuild", "CodePipeline", "GitOps", "pull request", "invalidation", "cache-control", "SPA", "index.html", "headers", "cache busting"]
author: "Carlos Cano"
---

# Static Web Deploy (AWS)

Production-grade static website deployment using Amazon S3 as a private origin, CloudFront with Origin Access Control (OAC), and GitOps-driven CI/CD via AWS CodeBuild.

## Non-Negotiable Security Rules

These rules are enforced throughout this power. **The agent must refuse any request that violates them** and propose the secure alternative.

1. **NEVER make the S3 bucket public** — All access flows through CloudFront
2. **Use CloudFront + OAC** — Origin Access Control (not legacy OAI)
3. **Enable S3 Block Public Access** — All four settings enabled
4. **Enforce HTTPS only** — CloudFront viewer protocol policy: redirect-to-https or https-only
5. **Least privilege IAM** — CodeBuild role scoped to specific bucket and distribution
6. **No secrets in Git** — Use Parameter Store, Secrets Manager, or CodeBuild environment variables

## When to Load Steering Files

- Setting up S3 bucket or CloudFront distribution → `00-architecture-security-baseline.md`
- Configuring Git branching, PRs, or deployment workflow → `01-gitops-workflow.md`
- Setting up CodeBuild, CodePipeline, or IAM policies → `02-ci-cd-codebuild.md`
- Configuring cache headers or CloudFront invalidation → `03-caching-and-headers.md`
- Deploying a Single Page Application (React, Vue, Angular) → `04-spa-routing.md`
- Debugging AccessDenied, stale content, or 404 errors → `05-troubleshooting.md`
- Need buildspec.yml, deploy scripts, or Kiro hooks → `06-templates.md`

## Available Steering Files

| File | Purpose |
|------|---------|
| `00-architecture-security-baseline` | OAC setup, S3 bucket policy, CloudFront security, WAF |
| `01-gitops-workflow` | Branching strategy, PR requirements, no manual deploys |
| `02-ci-cd-codebuild` | CodeBuild/CodePipeline patterns, IAM policies, buildspec |
| `03-caching-and-headers` | Cache-Control rules, invalidation strategy |
| `04-spa-routing` | SPA routing with CloudFront custom error responses |
| `05-troubleshooting` | Common issues: stale content, AccessDenied, 404s |
| `06-templates` | Ready-to-use buildspec.yml, deploy scripts, Kiro hooks |

## Onboarding

### Step 1: Gather Project Information

Before setup, confirm the following:

**Repository Provider:**
- [ ] GitHub
- [ ] AWS CodeCommit
- [ ] GitLab
- [ ] Bitbucket

**Site Type:**
- [ ] Static HTML/CSS/JS
- [ ] Single Page Application (React, Vue, Angular)
- [ ] Static Site Generator (Next.js export, Gatsby, Hugo, Jekyll)

**Build Configuration:**
- Build output directory: _____________ (e.g., `dist`, `build`, `out`, `public`)
- Build command: _____________ (e.g., `npm run build`)
- Node version (if applicable): _____________

**Environment Strategy:**
- [ ] Single environment (production only)
- [ ] Multi-environment (dev/stage/prod)

**Custom Domain:**
- [ ] Yes — Domain: _____________
- [ ] No — Use CloudFront default domain

### Step 2: Validate Prerequisites

Run these checks before proceeding:

```bash
# 1. AWS CLI configured and authenticated
aws sts get-caller-identity

# 2. Verify required permissions (or confirm IAM admin access for initial setup)
aws iam get-user

# 3. Build toolchain available (if Node.js project)
node --version
npm --version
```

**Required IAM Permissions for Setup:**
- `s3:CreateBucket`, `s3:PutBucketPolicy`, `s3:PutPublicAccessBlock`
- `cloudfront:CreateDistribution`, `cloudfront:CreateOriginAccessControl`
- `codebuild:CreateProject`, `iam:CreateRole`, `iam:PutRolePolicy`
- `codepipeline:CreatePipeline` (if using CodePipeline)

### Step 3: Choose Your Path

**Option A: Full Setup (New Project)**
1. Read `00-architecture-security-baseline` — Create S3 bucket and CloudFront distribution
2. Read `01-gitops-workflow` — Establish branching and PR strategy
3. Read `02-ci-cd-codebuild` — Set up CodeBuild project
4. Read `03-caching-and-headers` — Configure cache rules
5. (If SPA) Read `04-spa-routing` — Configure error responses

**Option B: Existing Infrastructure**
1. Audit existing setup against `00-architecture-security-baseline`
2. Migrate from OAI to OAC if needed
3. Review `02-ci-cd-codebuild` for CI/CD integration

### Step 4: Security Baseline Checklist

Before deploying, verify:

- [ ] S3 bucket has Block Public Access enabled (all 4 settings)
- [ ] S3 bucket policy only allows CloudFront via OAC
- [ ] CloudFront uses OAC (not OAI or public bucket)
- [ ] CloudFront viewer protocol: redirect-to-https
- [ ] CloudFront TLS: TLSv1.2_2021 minimum
- [ ] CodeBuild IAM role follows least privilege
- [ ] No AWS credentials committed to repository
- [ ] Build artifacts excluded from Git (.gitignore)

## Templates

This power includes ready-to-use templates. Load the `06-templates` steering file for:

- `buildspec.yml` — CodeBuild build specification
- `deploy.sh` — S3 sync with proper cache headers  
- `invalidate.sh` — Safe CloudFront invalidation
- Kiro hooks — Automation for common tasks

## Hooks

Example Kiro hooks are provided in the `06-templates` steering file:

| Hook | Purpose |
|------|---------|
| `deploy-static-site` | Full deployment workflow |
| `security-audit` | S3 + CloudFront audit |
| `pre-merge-checklist` | PR gating checks |

## Quick Reference

### S3 Bucket Policy (OAC)

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowCloudFrontOAC",
    "Effect": "Allow",
    "Principal": {"Service": "cloudfront.amazonaws.com"},
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::BUCKET_NAME/*",
    "Condition": {
      "StringEquals": {
        "AWS:SourceArn": "arn:aws:cloudfront::ACCOUNT_ID:distribution/DISTRIBUTION_ID"
      }
    }
  }]
}
```

### CodeBuild IAM Policy (Least Privilege)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::BUCKET_NAME",
        "arn:aws:s3:::BUCKET_NAME/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "cloudfront:CreateInvalidation",
      "Resource": "arn:aws:cloudfront::ACCOUNT_ID:distribution/DISTRIBUTION_ID"
    }
  ]
}
```

### Cache-Control Quick Reference

| File Type | Cache-Control | Reason |
|-----------|---------------|--------|
| `index.html` | `no-cache` or `max-age=60` | Always fetch latest |
| `*.html` | `no-cache` or `max-age=300` | Short cache for content |
| Hashed assets (`*.abc123.js`) | `max-age=31536000, immutable` | 1 year, never changes |
| Non-hashed assets | `max-age=86400` | 1 day, balance freshness |

---

**Next Step:** Read `00-architecture-security-baseline` to begin infrastructure setup.
