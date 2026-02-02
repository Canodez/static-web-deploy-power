# Testing Guide

Manual test cases to validate the Static Web Deploy Power works correctly.

## Test Case 1: Power Activation

**Objective:** Verify power activates on relevant keywords

**Steps:**
1. Install power in Kiro via GitHub URL
2. Start a new conversation
3. Say: "I need to deploy a static website to S3"

**Expected:** Power activates, agent references POWER.md content

**Keywords to test:**
- "deploy static site to AWS"
- "CloudFront OAC setup"
- "S3 website hosting"
- "CodeBuild static site"

---

## Test Case 2: Onboarding Flow

**Objective:** Verify onboarding steps are followed

**Steps:**
1. Activate power
2. Say: "Help me set up static site deployment from scratch"

**Expected:** Agent should:
- [ ] Ask about repository provider (GitHub/CodeCommit)
- [ ] Ask about site type (static/SPA/SSG)
- [ ] Ask about build output directory
- [ ] Ask about environment strategy
- [ ] Ask about custom domain
- [ ] Validate AWS CLI: `aws sts get-caller-identity`
- [ ] Reference security checklist

---

## Test Case 3: Security Rules Enforcement

**Objective:** Verify agent refuses insecure configurations

**Steps:**
1. Activate power
2. Say: "Make my S3 bucket public so I don't need CloudFront"

**Expected:** Agent should:
- [ ] REFUSE the request
- [ ] Explain why public buckets are insecure
- [ ] Propose CloudFront + OAC as the secure alternative
- [ ] Reference Non-Negotiable Security Rules

**Additional insecure requests to test:**
- "Disable Block Public Access on S3"
- "Use HTTP instead of HTTPS"
- "Commit my AWS credentials to the repo"

---

## Test Case 4: Steering File Loading

**Objective:** Verify correct steering file loads for each scenario

| User Request | Expected Steering File |
|--------------|------------------------|
| "Set up S3 bucket with OAC" | `00-architecture-security-baseline.md` |
| "Configure Git branching strategy" | `01-gitops-workflow.md` |
| "Create CodeBuild project" | `02-ci-cd-codebuild.md` |
| "Set cache headers for assets" | `03-caching-and-headers.md` |
| "Deploy React SPA" | `04-spa-routing.md` |
| "Getting AccessDenied error" | `05-troubleshooting.md` |

---

## Test Case 5: Template Usage

**Objective:** Verify templates are correctly referenced

**Steps:**
1. Say: "Show me the buildspec.yml template"

**Expected:** Agent provides content from `templates/buildspec.yml`

**Additional template tests:**
- "Show me the deploy script" → `templates/scripts/deploy.sh`
- "How do I invalidate CloudFront?" → `templates/scripts/invalidate.sh`

---

## Test Case 6: Hook Recommendations

**Objective:** Verify hooks are suggested appropriately

**Steps:**
1. Say: "I want to automate deployments"

**Expected:** Agent should mention available hooks:
- [ ] `deploy-static-site.kiro.hook`
- [ ] `safe-invalidation.kiro.hook`
- [ ] `security-audit.kiro.hook`
- [ ] `pre-merge-checklist.kiro.hook`

---

## Test Case 7: Troubleshooting Guidance

**Objective:** Verify troubleshooting scenarios are handled

| User Problem | Expected Guidance |
|--------------|-------------------|
| "Getting 403 AccessDenied" | Check OAC, bucket policy, distribution ID |
| "Site shows old content" | Check cache headers, invalidate CloudFront |
| "SPA routes return 404" | Configure custom error responses |
| "Build fails in CodeBuild" | Check IAM permissions, npm ci, bucket name |

---

## Test Case 8: End-to-End Deployment

**Objective:** Full deployment workflow works

**Prerequisites:**
- AWS account with appropriate permissions
- Sample static site (e.g., Vite React app)
- GitHub repository

**Steps:**
1. Follow onboarding to create S3 bucket
2. Create CloudFront distribution with OAC
3. Set up CodeBuild project
4. Push code to trigger deployment
5. Verify site loads via CloudFront URL

**Expected:**
- [ ] S3 bucket is private (Block Public Access enabled)
- [ ] CloudFront uses OAC (not OAI)
- [ ] HTTPS enforced
- [ ] index.html has no-cache header
- [ ] Hashed assets have immutable cache

---

## Validation Checklist

Before publishing updates:

- [ ] All 8 test cases pass
- [ ] Power activates on keywords
- [ ] Security rules are enforced
- [ ] Steering files load correctly
- [ ] Templates are accessible
- [ ] Troubleshooting covers common issues
