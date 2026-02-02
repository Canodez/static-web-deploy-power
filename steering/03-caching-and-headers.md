# Caching and Headers

Proper cache configuration is critical for performance and freshness. Get it wrong and users see stale content or your origin gets hammered.

## Cache-Control Strategy

### The Golden Rules

1. **HTML files:** Short or no cache — users must get latest content
2. **Hashed assets:** Long cache + immutable — filename changes on content change
3. **Non-hashed assets:** Medium cache — balance freshness and performance
4. **API responses:** No cache or very short — dynamic data

### Recommended Cache-Control Values

| File Type | Pattern | Cache-Control | TTL |
|-----------|---------|---------------|-----|
| index.html | `index.html` | `no-cache, no-store, must-revalidate` | 0 |
| Other HTML | `*.html` | `max-age=300` | 5 min |
| Hashed JS/CSS | `*.abc123.js` | `max-age=31536000, immutable` | 1 year |
| Non-hashed JS/CSS | `*.js`, `*.css` | `max-age=86400` | 1 day |
| Images | `*.png`, `*.jpg` | `max-age=604800` | 1 week |
| Fonts | `*.woff2` | `max-age=31536000, immutable` | 1 year |
| favicon | `favicon.ico` | `max-age=86400` | 1 day |

### Cache-Control Directives Explained

| Directive | Meaning |
|-----------|---------|
| `max-age=N` | Cache for N seconds |
| `no-cache` | Must revalidate with origin before using cached copy |
| `no-store` | Never cache, always fetch from origin |
| `must-revalidate` | Once stale, must revalidate (no stale-while-revalidate) |
| `immutable` | Content will never change, don't revalidate |
| `public` | Can be cached by CDN and browser |
| `private` | Only browser can cache, not CDN |

## S3 Upload with Headers

### Using AWS CLI

```bash
# Upload hashed assets (long cache)
aws s3 sync dist/assets s3://$BUCKET/assets \
  --cache-control "max-age=31536000, immutable" \
  --delete

# Upload index.html (no cache)
aws s3 cp dist/index.html s3://$BUCKET/index.html \
  --cache-control "no-cache, no-store, must-revalidate"

# Upload other HTML (short cache)
find dist -name "*.html" ! -name "index.html" -exec \
  aws s3 cp {} s3://$BUCKET/{} \
  --cache-control "max-age=300" \;

# Upload images (medium cache)
aws s3 sync dist/images s3://$BUCKET/images \
  --cache-control "max-age=604800"
```

### Complete Deploy Script

```bash
#!/bin/bash
set -e

BUCKET="$1"
BUILD_DIR="${2:-dist}"

if [ -z "$BUCKET" ]; then
  echo "Usage: deploy.sh <bucket-name> [build-dir]"
  exit 1
fi

echo "Deploying $BUILD_DIR to s3://$BUCKET"

# 1. Sync hashed assets (immutable)
echo "Uploading hashed assets..."
aws s3 sync "$BUILD_DIR" "s3://$BUCKET" \
  --exclude "*" \
  --include "*.*.js" \
  --include "*.*.css" \
  --include "*.*.woff2" \
  --cache-control "max-age=31536000, immutable" \
  --delete

# 2. Sync non-hashed assets
echo "Uploading static assets..."
aws s3 sync "$BUILD_DIR" "s3://$BUCKET" \
  --exclude "*.html" \
  --exclude "*.*.js" \
  --exclude "*.*.css" \
  --cache-control "max-age=86400"

# 3. Upload HTML files (short cache)
echo "Uploading HTML files..."
find "$BUILD_DIR" -name "*.html" ! -name "index.html" | while read file; do
  relative="${file#$BUILD_DIR/}"
  aws s3 cp "$file" "s3://$BUCKET/$relative" \
    --cache-control "max-age=300"
done

# 4. Upload index.html last (no cache)
echo "Uploading index.html..."
aws s3 cp "$BUILD_DIR/index.html" "s3://$BUCKET/index.html" \
  --cache-control "no-cache, no-store, must-revalidate"

echo "Deploy complete!"
```

## CloudFront Cache Behaviors

### Default Behavior

```json
{
  "PathPattern": "*",
  "TargetOriginId": "S3Origin",
  "ViewerProtocolPolicy": "redirect-to-https",
  "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
  "Compress": true
}
```

### Custom Cache Policy

Create a custom cache policy for fine-grained control:

```bash
aws cloudfront create-cache-policy --cache-policy-config '{
  "Name": "StaticSitePolicy",
  "DefaultTTL": 86400,
  "MaxTTL": 31536000,
  "MinTTL": 0,
  "ParametersInCacheKeyAndForwardedToOrigin": {
    "EnableAcceptEncodingGzip": true,
    "EnableAcceptEncodingBrotli": true,
    "HeadersConfig": {
      "HeaderBehavior": "none"
    },
    "CookiesConfig": {
      "CookieBehavior": "none"
    },
    "QueryStringsConfig": {
      "QueryStringBehavior": "none"
    }
  }
}'
```

### Path-Specific Behaviors

For different caching per path:

| Path Pattern | Cache Policy | Use Case |
|--------------|--------------|----------|
| `/assets/*` | Long TTL (1 year) | Hashed static assets |
| `/api/*` | No cache | API proxy (if applicable) |
| `*.html` | Short TTL (5 min) | HTML pages |
| Default (`*`) | Medium TTL (1 day) | Everything else |

## CloudFront Invalidation

### When to Invalidate

**DO Invalidate:**
- `index.html` — Always after deployment
- Non-hashed HTML files — After content changes
- Emergency fixes — When you can't wait for TTL

**DON'T Invalidate:**
- Hashed assets — Filename changes, no need
- Everything (`/*`) — Expensive and usually unnecessary
- Frequently — Indicates caching strategy problem

### Safe Invalidation

```bash
# Invalidate only index.html (recommended)
aws cloudfront create-invalidation \
  --distribution-id $DISTRIBUTION_ID \
  --paths "/index.html"

# Invalidate specific paths
aws cloudfront create-invalidation \
  --distribution-id $DISTRIBUTION_ID \
  --paths "/about.html" "/contact.html"

# Invalidate a directory (use sparingly)
aws cloudfront create-invalidation \
  --distribution-id $DISTRIBUTION_ID \
  --paths "/blog/*"
```

### Invalidation Costs

| Paths/Month | Cost |
|-------------|------|
| First 1,000 | Free |
| Additional | $0.005 per path |

**Wildcard (`/*`) counts as one path but invalidates everything.**

### Invalidation Script

```bash
#!/bin/bash
set -e

DISTRIBUTION_ID="$1"
PATHS="${2:-/index.html}"

if [ -z "$DISTRIBUTION_ID" ]; then
  echo "Usage: invalidate.sh <distribution-id> [paths]"
  echo "Example: invalidate.sh E1234567890ABC '/index.html /about.html'"
  exit 1
fi

echo "Creating invalidation for: $PATHS"

INVALIDATION_ID=$(aws cloudfront create-invalidation \
  --distribution-id "$DISTRIBUTION_ID" \
  --paths $PATHS \
  --query 'Invalidation.Id' \
  --output text)

echo "Invalidation created: $INVALIDATION_ID"

# Wait for completion (optional)
echo "Waiting for invalidation to complete..."
aws cloudfront wait invalidation-completed \
  --distribution-id "$DISTRIBUTION_ID" \
  --id "$INVALIDATION_ID"

echo "Invalidation complete!"
```

## Cache Busting Strategies

### Filename Hashing (Preferred)

Modern build tools add content hashes to filenames:

```
# Before build
main.js
styles.css

# After build (content hash)
main.a1b2c3d4.js
styles.e5f6g7h8.css
```

**Benefits:**
- No invalidation needed
- Guaranteed fresh content
- Parallel deployments safe

**Build Tool Configuration:**

Vite (vite.config.js):
```javascript
export default {
  build: {
    rollupOptions: {
      output: {
        entryFileNames: 'assets/[name].[hash].js',
        chunkFileNames: 'assets/[name].[hash].js',
        assetFileNames: 'assets/[name].[hash].[ext]'
      }
    }
  }
}
```

Webpack (webpack.config.js):
```javascript
module.exports = {
  output: {
    filename: '[name].[contenthash].js',
    assetModuleFilename: 'assets/[name].[contenthash][ext]'
  }
}
```

### Query String Versioning (Fallback)

If you can't hash filenames:

```html
<script src="/main.js?v=1.2.3"></script>
<link href="/styles.css?v=1.2.3" rel="stylesheet">
```

**Note:** CloudFront must be configured to include query strings in cache key.

## Content-Type Headers

S3 usually sets correct Content-Type, but verify:

| Extension | Content-Type |
|-----------|--------------|
| `.html` | `text/html; charset=utf-8` |
| `.css` | `text/css; charset=utf-8` |
| `.js` | `application/javascript; charset=utf-8` |
| `.json` | `application/json; charset=utf-8` |
| `.svg` | `image/svg+xml` |
| `.woff2` | `font/woff2` |

### Force Content-Type on Upload

```bash
aws s3 cp file.js s3://$BUCKET/file.js \
  --content-type "application/javascript; charset=utf-8" \
  --cache-control "max-age=31536000, immutable"
```

## Compression

### Enable in CloudFront

CloudFront compresses automatically when:
- `Compress` is enabled in cache behavior
- Client sends `Accept-Encoding: gzip` or `br`
- Content-Type is compressible
- File size > 1KB

**Compressible types:** HTML, CSS, JS, JSON, XML, SVG, fonts

### Verify Compression

```bash
# Check if response is compressed
curl -I -H "Accept-Encoding: gzip, br" https://your-site.cloudfront.net/main.js

# Look for:
# Content-Encoding: gzip
# or
# Content-Encoding: br
```

## Debugging Cache Issues

### Check Cache Status

```bash
# CloudFront cache status header
curl -I https://your-site.cloudfront.net/index.html

# Look for X-Cache header:
# X-Cache: Hit from cloudfront  → Served from cache
# X-Cache: Miss from cloudfront → Fetched from origin
# X-Cache: RefreshHit from cloudfront → Revalidated
```

### Check S3 Headers

```bash
# Get object metadata from S3
aws s3api head-object \
  --bucket $BUCKET \
  --key index.html

# Check CacheControl in response
```

### Force Cache Bypass (Testing)

```bash
# Add unique query string to bypass cache
curl -I "https://your-site.cloudfront.net/index.html?nocache=$(date +%s)"
```

---

**Next:** Read `04-spa-routing` if deploying a Single Page Application.
