# Templates

Ready-to-use templates for static site deployment. Copy these into your project.

## buildspec.yml (CodeBuild)

Create `buildspec.yml` in your project root:

```yaml
version: 0.2

# =============================================================================
# Static Site Deployment Buildspec
# =============================================================================
# Required Environment Variables (set in CodeBuild project):
#   - S3_BUCKET: Target S3 bucket name
#   - CLOUDFRONT_DISTRIBUTION_ID: CloudFront distribution ID
#   - BUILD_DIR: Build output directory (default: dist)
#   - SITE_TYPE: "static" or "spa" (affects cache headers)
#
# Optional Environment Variables:
#   - NODE_VERSION: Node.js version (default: 20)
#   - INVALIDATE_ALL: Set to "true" to invalidate /* (use sparingly)
# =============================================================================

env:
  variables:
    BUILD_DIR: "dist"
    SITE_TYPE: "static"
    NODE_VERSION: "20"
  # Uncomment to use Parameter Store for secrets:
  # parameter-store:
  #   API_KEY: "/mysite/api-key"

phases:
  install:
    runtime-versions:
      nodejs: $NODE_VERSION
    commands:
      - echo "Node version:" && node --version
      - echo "npm version:" && npm --version
      - echo "Installing dependencies..."
      - npm ci --prefer-offline

  pre_build:
    commands:
      - echo "Running pre-build checks..."
      - npm run lint 2>/dev/null || echo "Linting skipped or failed"
      - npm run test -- --passWithNoTests 2>/dev/null || echo "Tests skipped or failed"
      - npm audit --audit-level=high 2>/dev/null || echo "Audit warnings present"

  build:
    commands:
      - echo "Building site..."
      - npm run build
      - echo "Build complete. Contents of $BUILD_DIR:"
      - ls -la $BUILD_DIR/

  post_build:
    commands:
      - echo "Starting deployment to S3..."
      
      # Validate required variables
      - |
        if [ -z "$S3_BUCKET" ]; then
          echo "ERROR: S3_BUCKET environment variable not set"
          exit 1
        fi
        if [ -z "$CLOUDFRONT_DISTRIBUTION_ID" ]; then
          echo "ERROR: CLOUDFRONT_DISTRIBUTION_ID environment variable not set"
          exit 1
        fi
      
      # Step 1: Upload hashed assets with immutable cache (1 year)
      - echo "Uploading hashed assets (immutable cache)..."
      - |
        aws s3 sync $BUILD_DIR s3://$S3_BUCKET \
          --exclude "*" \
          --include "*.*.js" \
          --include "*.*.css" \
          --include "*.*.woff" \
          --include "*.*.woff2" \
          --cache-control "max-age=31536000, immutable"
      
      # Step 2: Upload images and media (1 week cache)
      - echo "Uploading images and media..."
      - |
        aws s3 sync $BUILD_DIR s3://$S3_BUCKET \
          --exclude "*" \
          --include "*.png" \
          --include "*.jpg" \
          --include "*.jpeg" \
          --include "*.gif" \
          --include "*.svg" \
          --include "*.webp" \
          --include "*.ico" \
          --include "*.mp4" \
          --include "*.webm" \
          --cache-control "max-age=604800"
      
      # Step 3: Upload non-hashed JS/CSS (1 day cache)
      - echo "Uploading non-hashed assets..."
      - |
        aws s3 sync $BUILD_DIR s3://$S3_BUCKET \
          --exclude "*.html" \
          --exclude "*.*.js" \
          --exclude "*.*.css" \
          --exclude "*.png" \
          --exclude "*.jpg" \
          --exclude "*.jpeg" \
          --exclude "*.gif" \
          --exclude "*.svg" \
          --exclude "*.webp" \
          --exclude "*.ico" \
          --exclude "*.mp4" \
          --exclude "*.webm" \
          --exclude "*.woff" \
          --exclude "*.woff2" \
          --cache-control "max-age=86400"
      
      # Step 4: Upload HTML files (except index.html) with short cache
      - echo "Uploading HTML files..."
      - |
        find $BUILD_DIR -name "*.html" ! -name "index.html" -type f | while read file; do
          relative="${file#$BUILD_DIR/}"
          aws s3 cp "$file" "s3://$S3_BUCKET/$relative" \
            --cache-control "max-age=300"
        done
      
      # Step 5: Upload index.html LAST with no-cache
      - echo "Uploading index.html (no cache)..."
      - |
        aws s3 cp $BUILD_DIR/index.html s3://$S3_BUCKET/index.html \
          --cache-control "no-cache, no-store, must-revalidate"
      
      # Step 6: Clean up deleted files
      - echo "Cleaning up deleted files..."
      - |
        aws s3 sync $BUILD_DIR s3://$S3_BUCKET --delete \
          --exclude "*" \
          --include "*.html" \
          --include "*.js" \
          --include "*.css" \
          --include "*.png" \
          --include "*.jpg" \
          --include "*.jpeg" \
          --include "*.gif" \
          --include "*.svg" \
          --include "*.webp" \
          --include "*.ico" \
          --include "*.woff" \
          --include "*.woff2" \
          --include "*.json" \
          --include "*.xml" \
          --include "*.txt"
      
      # Step 7: CloudFront Invalidation
      - echo "Creating CloudFront invalidation..."
      - |
        if [ "$INVALIDATE_ALL" = "true" ]; then
          echo "WARNING: Invalidating all paths (/*)"
          PATHS="/*"
        else
          PATHS="/index.html"
        fi
        
        INVALIDATION_ID=$(aws cloudfront create-invalidation \
          --distribution-id $CLOUDFRONT_DISTRIBUTION_ID \
          --paths $PATHS \
          --query 'Invalidation.Id' \
          --output text)
        
        echo "Invalidation created: $INVALIDATION_ID"
      
      - echo "Deployment complete!"

cache:
  paths:
    - node_modules/**/*
    - .npm/**/*
```

---

## deploy.sh (S3 Sync Script)

Create `scripts/deploy.sh`:

```bash
#!/bin/bash
# Static Site S3 Deployment Script
# Usage: ./deploy.sh <bucket-name> [build-dir]

set -e

BUCKET="$1"
BUILD_DIR="${2:-dist}"

if [ -z "$BUCKET" ]; then
  echo "Usage: ./deploy.sh <bucket-name> [build-dir]"
  exit 1
fi

if [ ! -d "$BUILD_DIR" ] || [ ! -f "$BUILD_DIR/index.html" ]; then
  echo "Error: Build directory or index.html not found"
  exit 1
fi

echo "Deploying $BUILD_DIR to s3://$BUCKET"

# Hashed assets (immutable, 1 year)
aws s3 sync "$BUILD_DIR" "s3://$BUCKET" \
  --exclude "*" \
  --include "*.*.js" \
  --include "*.*.css" \
  --cache-control "max-age=31536000, immutable"

# Images (1 week)
aws s3 sync "$BUILD_DIR" "s3://$BUCKET" \
  --exclude "*" \
  --include "*.png" \
  --include "*.jpg" \
  --include "*.svg" \
  --include "*.webp" \
  --cache-control "max-age=604800"

# Other assets (1 day)
aws s3 sync "$BUILD_DIR" "s3://$BUCKET" \
  --exclude "*.html" \
  --exclude "*.*.js" \
  --exclude "*.*.css" \
  --exclude "*.png" \
  --exclude "*.jpg" \
  --exclude "*.svg" \
  --exclude "*.webp" \
  --cache-control "max-age=86400"

# HTML files (short cache)
find "$BUILD_DIR" -name "*.html" ! -name "index.html" -type f | while read file; do
  relative="${file#$BUILD_DIR/}"
  aws s3 cp "$file" "s3://$BUCKET/$relative" --cache-control "max-age=300"
done

# index.html LAST (no cache)
aws s3 cp "$BUILD_DIR/index.html" "s3://$BUCKET/index.html" \
  --cache-control "no-cache, no-store, must-revalidate"

# Cleanup deleted files
aws s3 sync "$BUILD_DIR" "s3://$BUCKET" --delete --size-only

echo "Deployment complete!"
```

---

## invalidate.sh (CloudFront Invalidation)

Create `scripts/invalidate.sh`:

```bash
#!/bin/bash
# CloudFront Invalidation Script
# Usage: ./invalidate.sh <distribution-id> [paths]

set -e

DISTRIBUTION_ID="$1"
PATHS="${2:-/index.html}"

if [ -z "$DISTRIBUTION_ID" ]; then
  echo "Usage: ./invalidate.sh <distribution-id> [paths]"
  echo "Example: ./invalidate.sh E1234567890ABC /index.html"
  exit 1
fi

if [ "$PATHS" = "/*" ]; then
  echo "WARNING: Invalidating /* is expensive. Consider /index.html only."
  read -p "Continue? (y/N) " -n 1 -r
  echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
fi

echo "Creating invalidation for: $PATHS"

INVALIDATION_ID=$(aws cloudfront create-invalidation \
  --distribution-id "$DISTRIBUTION_ID" \
  --paths $PATHS \
  --query 'Invalidation.Id' \
  --output text)

echo "Invalidation created: $INVALIDATION_ID"
echo "Check status: aws cloudfront get-invalidation --distribution-id $DISTRIBUTION_ID --id $INVALIDATION_ID"
```

---

## Kiro Hooks

Add these hooks to `.kiro/hooks/` in your project:

### deploy-static-site.kiro.hook

```json
{
  "name": "Deploy Static Site",
  "version": "1.0.0",
  "when": { "type": "userTriggered" },
  "then": {
    "type": "askAgent",
    "prompt": "Execute static site deployment: validate AWS CLI, build project, sync to S3 with proper cache headers, invalidate CloudFront /index.html. Follow security rules: never make S3 public, always use OAC."
  }
}
```

### security-audit.kiro.hook

```json
{
  "name": "Security Audit",
  "version": "1.0.0",
  "when": { "type": "userTriggered" },
  "then": {
    "type": "askAgent",
    "prompt": "Audit S3 bucket and CloudFront: check Block Public Access, bucket policy allows only CloudFront OAC, viewer protocol is HTTPS, TLS 1.2+. Report pass/fail for each check."
  }
}
```

### pre-merge-checklist.kiro.hook

```json
{
  "name": "Pre-Merge Checklist",
  "version": "1.0.0",
  "when": { "type": "userTriggered" },
  "then": {
    "type": "askAgent",
    "prompt": "Run pre-merge checks: npm ci, npm run build, npm run lint, npm test, scan for secrets in code, verify no AWS credentials committed. Report pass/fail summary."
  }
}
```
