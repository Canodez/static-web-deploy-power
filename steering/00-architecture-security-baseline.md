# Architecture & Security Baseline

This document establishes the foundational architecture and security requirements for static web deployment on AWS.

## Architecture Overview

```
┌─────────────┐     ┌─────────────────┐     ┌──────────────┐
│   Users     │────▶│   CloudFront    │────▶│  S3 Bucket   │
│  (HTTPS)    │     │   (OAC + TLS)   │     │  (Private)   │
└─────────────┘     └─────────────────┘     └──────────────┘
                            │
                    ┌───────┴───────┐
                    │  Origin Access │
                    │  Control (OAC) │
                    └───────────────┘
```

## OAC vs OAI: Why OAC

| Feature | OAC (Use This) | OAI (Legacy) |
|---------|----------------|--------------|
| AWS Recommendation | ✅ Current standard | ⚠️ Deprecated |
| SSE-KMS Support | ✅ Yes | ❌ No |
| All S3 Regions | ✅ Yes | ❌ Limited |
| Granular Permissions | ✅ SourceArn condition | ❌ Principal only |
| Security | ✅ Stronger isolation | ⚠️ Weaker |

**Decision: Always use OAC for new deployments. Migrate existing OAI to OAC.**

## S3 Bucket Configuration

### Block Public Access (Required)

All four settings must be enabled:

```bash
aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
    BlockPublicAcls=true,\
    IgnorePublicAcls=true,\
    BlockPublicPolicy=true,\
    RestrictPublicBuckets=true
```

### Bucket Policy for OAC

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontOACReadOnly",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${DISTRIBUTION_ID}"
        }
      }
    }
  ]
}
```

**Key Points:**
- Principal is `cloudfront.amazonaws.com` service (not a specific OAC ARN)
- `AWS:SourceArn` condition restricts to your specific distribution
- Only `s3:GetObject` — no write permissions needed for serving

### Create S3 Bucket

```bash
# Set variables
BUCKET_NAME="mysite-static-prod"
REGION="us-east-1"

# Create bucket
aws s3api create-bucket \
  --bucket $BUCKET_NAME \
  --region $REGION

# Enable versioning (recommended for rollback)
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled

# Block public access
aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

## CloudFront Configuration

### Create Origin Access Control

```bash
# Create OAC
aws cloudfront create-origin-access-control \
  --origin-access-control-config \
    Name="oac-${BUCKET_NAME}",\
    Description="OAC for ${BUCKET_NAME}",\
    SigningProtocol=sigv4,\
    SigningBehavior=always,\
    OriginAccessControlOriginType=s3
```

### CloudFront Distribution Settings

**Origin Configuration:**
- Origin domain: `${BUCKET_NAME}.s3.${REGION}.amazonaws.com`
- Origin access: Origin access control settings (recommended)
- Select the OAC created above

**Default Cache Behavior:**
- Viewer protocol policy: `Redirect HTTP to HTTPS`
- Allowed HTTP methods: `GET, HEAD` (static sites don't need POST)
- Cache policy: `CachingOptimized` or custom policy
- Origin request policy: `CORS-S3Origin` (if needed)

**Security Settings:**
- Minimum TLS version: `TLSv1.2_2021`
- Security policy: `TLSv1.2_2021`

**Default Root Object:** `index.html`

### Create Distribution (CLI)

```bash
# Create distribution config file
cat > cf-config.json << 'EOF'
{
  "CallerReference": "static-site-$(date +%s)",
  "Origins": {
    "Quantity": 1,
    "Items": [{
      "Id": "S3Origin",
      "DomainName": "${BUCKET_NAME}.s3.${REGION}.amazonaws.com",
      "S3OriginConfig": {
        "OriginAccessIdentity": ""
      },
      "OriginAccessControlId": "${OAC_ID}"
    }]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "S3Origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"]
    },
    "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
    "Compress": true
  },
  "DefaultRootObject": "index.html",
  "Enabled": true,
  "HttpVersion": "http2and3",
  "PriceClass": "PriceClass_100"
}
EOF

aws cloudfront create-distribution --distribution-config file://cf-config.json
```

## Security Hardening

### Response Headers Policy

Add security headers via CloudFront:

```bash
aws cloudfront create-response-headers-policy \
  --response-headers-policy-config '{
    "Name": "SecurityHeaders",
    "SecurityHeadersConfig": {
      "StrictTransportSecurity": {
        "Override": true,
        "AccessControlMaxAgeSec": 31536000,
        "IncludeSubdomains": true,
        "Preload": true
      },
      "ContentTypeOptions": {
        "Override": true
      },
      "FrameOptions": {
        "Override": true,
        "FrameOption": "DENY"
      },
      "XSSProtection": {
        "Override": true,
        "Protection": true,
        "ModeBlock": true
      },
      "ReferrerPolicy": {
        "Override": true,
        "ReferrerPolicy": "strict-origin-when-cross-origin"
      },
      "ContentSecurityPolicy": {
        "Override": true,
        "ContentSecurityPolicy": "default-src '\''self'\''; script-src '\''self'\''; style-src '\''self'\'' '\''unsafe-inline'\''"
      }
    }
  }'
```

### Optional: AWS WAF

For additional protection, attach WAF to CloudFront:

```bash
# Create WAF Web ACL with AWS Managed Rules
aws wafv2 create-web-acl \
  --name "static-site-waf" \
  --scope CLOUDFRONT \
  --region us-east-1 \
  --default-action Allow={} \
  --rules '[
    {
      "Name": "AWSManagedRulesCommonRuleSet",
      "Priority": 1,
      "Statement": {
        "ManagedRuleGroupStatement": {
          "VendorName": "AWS",
          "Name": "AWSManagedRulesCommonRuleSet"
        }
      },
      "OverrideAction": {"None": {}},
      "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "CommonRules"
      }
    }
  ]' \
  --visibility-config SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=StaticSiteWAF
```

### Enable Access Logging

```bash
# Create logging bucket
aws s3api create-bucket --bucket ${BUCKET_NAME}-logs --region $REGION

# Enable CloudFront logging
aws cloudfront update-distribution \
  --id $DISTRIBUTION_ID \
  --distribution-config "$(aws cloudfront get-distribution-config --id $DISTRIBUTION_ID | jq '.DistributionConfig.Logging = {"Enabled": true, "Bucket": "${BUCKET_NAME}-logs.s3.amazonaws.com", "Prefix": "cf-logs/"}')"
```

## Security Checklist

Before proceeding to CI/CD setup, verify:

- [ ] S3 bucket created with Block Public Access enabled
- [ ] S3 bucket versioning enabled
- [ ] OAC created and attached to CloudFront distribution
- [ ] S3 bucket policy allows only CloudFront via OAC
- [ ] CloudFront viewer protocol: redirect-to-https
- [ ] CloudFront minimum TLS: TLSv1.2_2021
- [ ] Default root object set to index.html
- [ ] Response headers policy attached (security headers)
- [ ] (Optional) WAF Web ACL attached
- [ ] (Optional) Access logging enabled

## Migrating from OAI to OAC

If you have an existing distribution using OAI:

1. Create new OAC
2. Update distribution to use OAC instead of OAI
3. Update S3 bucket policy to use new format with `AWS:SourceArn`
4. Remove old OAI
5. Test access

```bash
# Get current distribution config
aws cloudfront get-distribution-config --id $DISTRIBUTION_ID > dist-config.json

# Edit to replace OAI with OAC (manual step)
# Update S3OriginConfig.OriginAccessIdentity to ""
# Add OriginAccessControlId

# Update distribution
aws cloudfront update-distribution --id $DISTRIBUTION_ID --distribution-config file://updated-config.json --if-match $ETAG
```

---

**Next:** Read `01-gitops-workflow` to establish your branching and deployment strategy.
