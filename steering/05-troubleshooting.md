# Troubleshooting

Common issues and solutions for static site deployments on AWS.

## Quick Diagnosis

| Symptom | Likely Cause | Jump To |
|---------|--------------|---------|
| 403 AccessDenied | Bucket policy, OAC config | [AccessDenied](#accessdenied-errors) |
| 404 Not Found | Missing file, wrong path | [404 Errors](#404-not-found) |
| Stale content | Caching, no invalidation | [Stale Content](#stale-content) |
| SPA routes 404 | Missing error responses | [SPA Routing](#spa-routing-issues) |
| Slow first load | Cold cache, no compression | [Performance](#performance-issues) |
| CORS errors | Missing headers | [CORS](#cors-issues) |
| SSL/TLS errors | Certificate issues | [SSL/TLS](#ssltls-issues) |

## AccessDenied Errors

### Symptom
```xml
<Error>
  <Code>AccessDenied</Code>
  <Message>Access Denied</Message>
</Error>
```

### Diagnosis Checklist

1. **Check S3 Block Public Access**
   ```bash
   aws s3api get-public-access-block --bucket $BUCKET
   ```
   All four should be `true` (this is correct for OAC setup).

2. **Check Bucket Policy**
   ```bash
   aws s3api get-bucket-policy --bucket $BUCKET
   ```
   
   Verify policy allows CloudFront:
   ```json
   {
     "Principal": {"Service": "cloudfront.amazonaws.com"},
     "Condition": {
       "StringEquals": {
         "AWS:SourceArn": "arn:aws:cloudfront::ACCOUNT:distribution/DIST_ID"
       }
     }
   }
   ```

3. **Check OAC is Attached**
   ```bash
   aws cloudfront get-distribution --id $DISTRIBUTION_ID \
     --query 'Distribution.DistributionConfig.Origins.Items[0]'
   ```
   
   Look for `OriginAccessControlId` (not empty).

4. **Check Distribution ID in Policy**
   The `AWS:SourceArn` in bucket policy must match your distribution ARN exactly.

### Common Fixes

**Wrong Distribution ID in Bucket Policy:**
```bash
# Get your distribution ARN
aws cloudfront get-distribution --id $DISTRIBUTION_ID \
  --query 'Distribution.ARN' --output text

# Update bucket policy with correct ARN
```

**OAC Not Attached:**
```bash
# List OACs
aws cloudfront list-origin-access-controls

# Update distribution to use OAC
# (See 00-architecture-security-baseline.md)
```

**Legacy OAI Instead of OAC:**
```bash
# Check if using OAI
aws cloudfront get-distribution --id $DISTRIBUTION_ID \
  --query 'Distribution.DistributionConfig.Origins.Items[0].S3OriginConfig'

# If OriginAccessIdentity is set, migrate to OAC
```

## 404 Not Found

### Symptom
```xml
<Error>
  <Code>NoSuchKey</Code>
  <Message>The specified key does not exist.</Message>
</Error>
```

### Diagnosis

1. **Check File Exists in S3**
   ```bash
   aws s3 ls s3://$BUCKET/path/to/file.html
   ```

2. **Check Default Root Object**
   ```bash
   aws cloudfront get-distribution --id $DISTRIBUTION_ID \
     --query 'Distribution.DistributionConfig.DefaultRootObject'
   ```
   Should be `index.html`.

3. **Check Path Case Sensitivity**
   S3 is case-sensitive: `/About.html` ≠ `/about.html`

4. **Check for Trailing Slashes**
   `/about/` looks for `/about/index.html`
   `/about` looks for `/about` file

### Common Fixes

**Missing Default Root Object:**
```bash
# Update distribution
aws cloudfront update-distribution --id $DISTRIBUTION_ID \
  --default-root-object index.html \
  --if-match $ETAG
```

**Wrong Build Directory Deployed:**
```bash
# Verify build output
ls -la dist/  # or build/, out/, etc.

# Check S3 contents
aws s3 ls s3://$BUCKET/ --recursive | head -20
```

## Stale Content

### Symptom
- Old version of site showing after deployment
- Changes not visible to users
- Works in incognito but not regular browser

### Diagnosis

1. **Check CloudFront Cache Status**
   ```bash
   curl -I https://your-site.cloudfront.net/index.html
   # Look for: X-Cache: Hit from cloudfront
   ```

2. **Check S3 Has New Content**
   ```bash
   aws s3api head-object --bucket $BUCKET --key index.html
   # Check LastModified timestamp
   ```

3. **Check Cache-Control Headers**
   ```bash
   aws s3api head-object --bucket $BUCKET --key index.html \
     --query 'CacheControl'
   ```

### Common Fixes

**Invalidate CloudFront Cache:**
```bash
aws cloudfront create-invalidation \
  --distribution-id $DISTRIBUTION_ID \
  --paths "/index.html"
```

**Fix Cache-Control on Upload:**
```bash
# Re-upload with correct headers
aws s3 cp dist/index.html s3://$BUCKET/index.html \
  --cache-control "no-cache, no-store, must-revalidate"
```

**Browser Cache (Client-Side):**
- Hard refresh: Ctrl+Shift+R (Windows) or Cmd+Shift+R (Mac)
- Clear browser cache
- Test in incognito mode

## SPA Routing Issues

### Symptom
- Direct URL access returns 403 or 404
- Refresh on `/dashboard` fails
- Only homepage works

### Diagnosis

1. **Check Custom Error Responses**
   ```bash
   aws cloudfront get-distribution --id $DISTRIBUTION_ID \
     --query 'Distribution.DistributionConfig.CustomErrorResponses'
   ```

2. **Test Direct Access**
   ```bash
   curl -I https://your-site.cloudfront.net/dashboard
   # Should return 200, not 403/404
   ```

### Fix

Add custom error responses (see `04-spa-routing.md`):

```bash
# Quick fix via CLI
aws cloudfront get-distribution-config --id $DISTRIBUTION_ID > config.json
# Edit to add CustomErrorResponses for 403 and 404
aws cloudfront update-distribution --id $DISTRIBUTION_ID \
  --distribution-config file://updated-config.json \
  --if-match $ETAG
```

## Performance Issues

### Symptom
- Slow initial page load
- Large file sizes
- No compression

### Diagnosis

1. **Check Compression**
   ```bash
   curl -I -H "Accept-Encoding: gzip, br" \
     https://your-site.cloudfront.net/main.js
   # Look for: Content-Encoding: gzip (or br)
   ```

2. **Check File Sizes**
   ```bash
   aws s3 ls s3://$BUCKET/ --recursive --human-readable | sort -k3 -h | tail -10
   ```

3. **Check Cache Hit Ratio**
   - CloudWatch → CloudFront → CacheHitRate metric

### Common Fixes

**Enable Compression:**
```bash
# Verify cache behavior has Compress: true
aws cloudfront get-distribution --id $DISTRIBUTION_ID \
  --query 'Distribution.DistributionConfig.DefaultCacheBehavior.Compress'
```

**Optimize Build:**
```bash
# Ensure production build
npm run build  # Not dev build

# Check for source maps in production
ls -la dist/*.map  # Should not exist in prod
```

**Use HTTP/2 or HTTP/3:**
```bash
aws cloudfront get-distribution --id $DISTRIBUTION_ID \
  --query 'Distribution.DistributionConfig.HttpVersion'
# Should be "http2" or "http2and3"
```

## CORS Issues

### Symptom
```
Access to fetch at 'https://...' from origin 'https://...' 
has been blocked by CORS policy
```

### Diagnosis

1. **Check Response Headers**
   ```bash
   curl -I -H "Origin: https://your-site.com" \
     https://your-site.cloudfront.net/api/data
   # Look for: Access-Control-Allow-Origin
   ```

2. **Check CloudFront Origin Request Policy**
   ```bash
   aws cloudfront get-distribution --id $DISTRIBUTION_ID \
     --query 'Distribution.DistributionConfig.DefaultCacheBehavior.OriginRequestPolicyId'
   ```

### Common Fixes

**Add CORS Headers via Response Headers Policy:**
```bash
aws cloudfront create-response-headers-policy --response-headers-policy-config '{
  "Name": "CORS-Headers",
  "CorsConfig": {
    "AccessControlAllowOrigins": {
      "Quantity": 1,
      "Items": ["https://your-site.com"]
    },
    "AccessControlAllowHeaders": {
      "Quantity": 1,
      "Items": ["*"]
    },
    "AccessControlAllowMethods": {
      "Quantity": 3,
      "Items": ["GET", "HEAD", "OPTIONS"]
    },
    "AccessControlAllowCredentials": false,
    "OriginOverride": true
  }
}'
```

**For S3 CORS (if accessing S3 directly):**
```bash
aws s3api put-bucket-cors --bucket $BUCKET --cors-configuration '{
  "CORSRules": [{
    "AllowedOrigins": ["https://your-site.com"],
    "AllowedMethods": ["GET", "HEAD"],
    "AllowedHeaders": ["*"],
    "MaxAgeSeconds": 3600
  }]
}'
```

## SSL/TLS Issues

### Symptom
- Certificate errors in browser
- `ERR_CERT_COMMON_NAME_INVALID`
- Mixed content warnings

### Diagnosis

1. **Check Certificate**
   ```bash
   aws cloudfront get-distribution --id $DISTRIBUTION_ID \
     --query 'Distribution.DistributionConfig.ViewerCertificate'
   ```

2. **Check Aliases Match Certificate**
   ```bash
   aws cloudfront get-distribution --id $DISTRIBUTION_ID \
     --query 'Distribution.DistributionConfig.Aliases'
   ```

3. **Check Certificate Status**
   ```bash
   aws acm describe-certificate --certificate-arn $CERT_ARN \
     --query 'Certificate.Status'
   # Should be "ISSUED"
   ```

### Common Fixes

**Certificate Not Covering Domain:**
- Request new certificate in ACM (us-east-1 for CloudFront)
- Include all required domains and subdomains
- Complete DNS validation

**Mixed Content:**
- Ensure all resources use HTTPS
- Update hardcoded HTTP URLs in code
- Use protocol-relative URLs: `//example.com/resource`

## CodeBuild Failures

### Symptom
- Build fails in CodeBuild
- Deployment doesn't complete

### Diagnosis

1. **Check Build Logs**
   ```bash
   aws codebuild list-builds-for-project --project-name $PROJECT \
     --query 'ids[0]' --output text | xargs \
     aws codebuild batch-get-builds --ids
   ```

2. **Check IAM Permissions**
   ```bash
   aws codebuild batch-get-projects --names $PROJECT \
     --query 'projects[0].serviceRole'
   ```

### Common Fixes

**npm ci Fails:**
```bash
# Ensure package-lock.json is committed
git add package-lock.json
git commit -m "Add package-lock.json"
```

**S3 Access Denied:**
- Verify CodeBuild role has S3 permissions
- Check bucket name in environment variables

**CloudFront Invalidation Fails:**
- Verify CodeBuild role has `cloudfront:CreateInvalidation`
- Check distribution ID is correct

## Debugging Commands

### Full Diagnostic Script

```bash
#!/bin/bash
BUCKET="$1"
DISTRIBUTION_ID="$2"

echo "=== S3 Bucket ==="
aws s3api get-bucket-location --bucket $BUCKET
aws s3api get-public-access-block --bucket $BUCKET
aws s3api get-bucket-policy --bucket $BUCKET 2>/dev/null || echo "No bucket policy"

echo ""
echo "=== CloudFront Distribution ==="
aws cloudfront get-distribution --id $DISTRIBUTION_ID \
  --query '{
    Status: Distribution.Status,
    DomainName: Distribution.DomainName,
    DefaultRootObject: Distribution.DistributionConfig.DefaultRootObject,
    OAC: Distribution.DistributionConfig.Origins.Items[0].OriginAccessControlId,
    HttpVersion: Distribution.DistributionConfig.HttpVersion,
    Compress: Distribution.DistributionConfig.DefaultCacheBehavior.Compress,
    ViewerProtocol: Distribution.DistributionConfig.DefaultCacheBehavior.ViewerProtocolPolicy,
    CustomErrorResponses: Distribution.DistributionConfig.CustomErrorResponses.Quantity
  }'

echo ""
echo "=== Test Access ==="
CF_DOMAIN=$(aws cloudfront get-distribution --id $DISTRIBUTION_ID \
  --query 'Distribution.DomainName' --output text)
curl -I "https://$CF_DOMAIN/" 2>/dev/null | head -5

echo ""
echo "=== Recent Invalidations ==="
aws cloudfront list-invalidations --distribution-id $DISTRIBUTION_ID \
  --query 'InvalidationList.Items[0:3]'
```

### Quick Health Check

```bash
# One-liner health check
curl -s -o /dev/null -w "Status: %{http_code}, Time: %{time_total}s\n" \
  https://your-site.cloudfront.net/
```

---

**Still stuck?** Check CloudWatch Logs for CodeBuild, CloudFront access logs, and S3 server access logs for detailed error information.
