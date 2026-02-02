#!/bin/bash
# =============================================================================
# CloudFront Invalidation Script
# =============================================================================
# Creates CloudFront cache invalidation with safe defaults.
#
# Usage:
#   ./invalidate.sh <distribution-id> [paths]
#
# Examples:
#   ./invalidate.sh E1234567890ABC                    # Invalidates /index.html only
#   ./invalidate.sh E1234567890ABC "/index.html"     # Same as above
#   ./invalidate.sh E1234567890ABC "/about.html /contact.html"
#   ./invalidate.sh E1234567890ABC "/*"              # All paths (use sparingly!)
#
# Environment Variables:
#   WAIT=true       - Wait for invalidation to complete
#   VERBOSE=true    - Show detailed output
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Arguments
DISTRIBUTION_ID="$1"
PATHS="${2:-/index.html}"

# Validation
if [ -z "$DISTRIBUTION_ID" ]; then
  echo -e "${RED}Error: Distribution ID required${NC}"
  echo ""
  echo "Usage: ./invalidate.sh <distribution-id> [paths]"
  echo ""
  echo "Examples:"
  echo "  ./invalidate.sh E1234567890ABC                    # /index.html only (safe)"
  echo "  ./invalidate.sh E1234567890ABC \"/about.html\"     # Specific file"
  echo "  ./invalidate.sh E1234567890ABC \"/*\"              # All paths (costly)"
  echo ""
  echo "Find your distribution ID:"
  echo "  aws cloudfront list-distributions --query 'DistributionList.Items[*].[Id,DomainName]' --output table"
  exit 1
fi

# Warning for wildcard invalidation
if [ "$PATHS" = "/*" ]; then
  echo -e "${YELLOW}WARNING: Invalidating all paths (/*) is expensive and usually unnecessary.${NC}"
  echo ""
  echo "Consider:"
  echo "  - Invalidating only /index.html (default)"
  echo "  - Using cache busting (hashed filenames) instead"
  echo ""
  read -p "Continue with /* invalidation? (y/N) " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

echo -e "${CYAN}Creating CloudFront invalidation...${NC}"
echo "Distribution: $DISTRIBUTION_ID"
echo "Paths: $PATHS"
echo ""

# Create invalidation
RESULT=$(aws cloudfront create-invalidation \
  --distribution-id "$DISTRIBUTION_ID" \
  --paths $PATHS \
  --output json)

INVALIDATION_ID=$(echo "$RESULT" | grep -o '"Id": "[^"]*"' | head -1 | cut -d'"' -f4)
STATUS=$(echo "$RESULT" | grep -o '"Status": "[^"]*"' | head -1 | cut -d'"' -f4)

echo -e "${GREEN}Invalidation created!${NC}"
echo "  ID: $INVALIDATION_ID"
echo "  Status: $STATUS"

# Wait for completion if requested
if [ "$WAIT" = "true" ]; then
  echo ""
  echo -e "${YELLOW}Waiting for invalidation to complete...${NC}"
  echo "(This may take 1-5 minutes)"
  
  aws cloudfront wait invalidation-completed \
    --distribution-id "$DISTRIBUTION_ID" \
    --id "$INVALIDATION_ID"
  
  echo -e "${GREEN}Invalidation complete!${NC}"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Done!${NC}"
echo ""
echo "Check status:"
echo "  aws cloudfront get-invalidation --distribution-id $DISTRIBUTION_ID --id $INVALIDATION_ID"
echo ""
echo "List recent invalidations:"
echo "  aws cloudfront list-invalidations --distribution-id $DISTRIBUTION_ID --max-items 5"
