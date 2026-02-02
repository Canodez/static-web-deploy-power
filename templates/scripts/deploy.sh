#!/bin/bash
# =============================================================================
# Static Site S3 Deployment Script
# =============================================================================
# Deploys static site to S3 with proper cache headers.
#
# Usage:
#   ./deploy.sh <bucket-name> [build-dir]
#
# Examples:
#   ./deploy.sh mysite-prod dist
#   ./deploy.sh mysite-staging build
#
# Environment Variables (optional):
#   DRY_RUN=true    - Show what would be uploaded without uploading
#   VERBOSE=true    - Show detailed output
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Arguments
BUCKET="$1"
BUILD_DIR="${2:-dist}"

# Validation
if [ -z "$BUCKET" ]; then
  echo -e "${RED}Error: Bucket name required${NC}"
  echo ""
  echo "Usage: ./deploy.sh <bucket-name> [build-dir]"
  echo ""
  echo "Examples:"
  echo "  ./deploy.sh mysite-prod dist"
  echo "  ./deploy.sh mysite-staging build"
  exit 1
fi

if [ ! -d "$BUILD_DIR" ]; then
  echo -e "${RED}Error: Build directory '$BUILD_DIR' does not exist${NC}"
  echo "Run your build command first (e.g., npm run build)"
  exit 1
fi

if [ ! -f "$BUILD_DIR/index.html" ]; then
  echo -e "${RED}Error: index.html not found in '$BUILD_DIR'${NC}"
  exit 1
fi

# Dry run flag
DRY_RUN_FLAG=""
if [ "$DRY_RUN" = "true" ]; then
  DRY_RUN_FLAG="--dryrun"
  echo -e "${YELLOW}DRY RUN MODE - No files will be uploaded${NC}"
  echo ""
fi

echo -e "${GREEN}Deploying $BUILD_DIR to s3://$BUCKET${NC}"
echo "=========================================="

# Step 1: Upload hashed assets (immutable, 1 year cache)
echo ""
echo -e "${YELLOW}[1/5] Uploading hashed assets (immutable cache)...${NC}"
aws s3 sync "$BUILD_DIR" "s3://$BUCKET" $DRY_RUN_FLAG \
  --exclude "*" \
  --include "*.*.js" \
  --include "*.*.css" \
  --include "*.*.woff" \
  --include "*.*.woff2" \
  --cache-control "max-age=31536000, immutable"

# Step 2: Upload images (1 week cache)
echo ""
echo -e "${YELLOW}[2/5] Uploading images and media...${NC}"
aws s3 sync "$BUILD_DIR" "s3://$BUCKET" $DRY_RUN_FLAG \
  --exclude "*" \
  --include "*.png" \
  --include "*.jpg" \
  --include "*.jpeg" \
  --include "*.gif" \
  --include "*.svg" \
  --include "*.webp" \
  --include "*.ico" \
  --cache-control "max-age=604800"

# Step 3: Upload other static assets (1 day cache)
echo ""
echo -e "${YELLOW}[3/5] Uploading other assets...${NC}"
aws s3 sync "$BUILD_DIR" "s3://$BUCKET" $DRY_RUN_FLAG \
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
  --exclude "*.woff" \
  --exclude "*.woff2" \
  --cache-control "max-age=86400"

# Step 4: Upload HTML files (short cache)
echo ""
echo -e "${YELLOW}[4/5] Uploading HTML files...${NC}"
find "$BUILD_DIR" -name "*.html" ! -name "index.html" -type f | while read file; do
  relative="${file#$BUILD_DIR/}"
  if [ "$DRY_RUN" = "true" ]; then
    echo "(dryrun) upload: $file to s3://$BUCKET/$relative"
  else
    aws s3 cp "$file" "s3://$BUCKET/$relative" \
      --cache-control "max-age=300"
  fi
done

# Step 5: Upload index.html LAST (no cache)
echo ""
echo -e "${YELLOW}[5/5] Uploading index.html (no cache)...${NC}"
if [ "$DRY_RUN" = "true" ]; then
  echo "(dryrun) upload: $BUILD_DIR/index.html to s3://$BUCKET/index.html"
else
  aws s3 cp "$BUILD_DIR/index.html" "s3://$BUCKET/index.html" \
    --cache-control "no-cache, no-store, must-revalidate"
fi

# Cleanup deleted files
echo ""
echo -e "${YELLOW}Cleaning up deleted files...${NC}"
aws s3 sync "$BUILD_DIR" "s3://$BUCKET" --delete $DRY_RUN_FLAG \
  --size-only

echo ""
echo "=========================================="
echo -e "${GREEN}Deployment complete!${NC}"
echo ""
echo "Bucket: s3://$BUCKET"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Run invalidate.sh to clear CloudFront cache"
echo "  2. Verify deployment at your CloudFront URL"
