# SPA Routing

Single Page Applications use client-side routing. The server must return `index.html` for all routes, letting the JavaScript router handle navigation.

## The Problem

```
User visits: https://mysite.com/dashboard/settings
CloudFront looks for: /dashboard/settings (file doesn't exist)
Result: 403 Forbidden or 404 Not Found
```

**Why it happens:** CloudFront/S3 looks for a file at that path. SPAs don't have files for each route — they have one `index.html` and JavaScript handles routing.

## The Solution: Custom Error Responses

Configure CloudFront to return `index.html` for 403 and 404 errors:

### Via AWS Console

1. Open CloudFront distribution
2. Go to **Error Pages** tab
3. Create custom error response:
   - HTTP Error Code: `403`
   - Customize Error Response: Yes
   - Response Page Path: `/index.html`
   - HTTP Response Code: `200`
4. Repeat for `404`

### Via AWS CLI

```bash
DISTRIBUTION_ID="E1234567890ABC"

# Get current config
aws cloudfront get-distribution-config --id $DISTRIBUTION_ID > dist-config.json

# Extract ETag for update
ETAG=$(jq -r '.ETag' dist-config.json)

# Add custom error responses to config
jq '.DistributionConfig.CustomErrorResponses = {
  "Quantity": 2,
  "Items": [
    {
      "ErrorCode": 403,
      "ResponsePagePath": "/index.html",
      "ResponseCode": "200",
      "ErrorCachingMinTTL": 0
    },
    {
      "ErrorCode": 404,
      "ResponsePagePath": "/index.html",
      "ResponseCode": "200",
      "ErrorCachingMinTTL": 0
    }
  ]
}' dist-config.json > updated-config.json

# Extract just DistributionConfig
jq '.DistributionConfig' updated-config.json > final-config.json

# Update distribution
aws cloudfront update-distribution \
  --id $DISTRIBUTION_ID \
  --distribution-config file://final-config.json \
  --if-match $ETAG
```

### CloudFormation/CDK

```yaml
# CloudFormation
CloudFrontDistribution:
  Type: AWS::CloudFront::Distribution
  Properties:
    DistributionConfig:
      CustomErrorResponses:
        - ErrorCode: 403
          ResponseCode: 200
          ResponsePagePath: /index.html
          ErrorCachingMinTTL: 0
        - ErrorCode: 404
          ResponseCode: 200
          ResponsePagePath: /index.html
          ErrorCachingMinTTL: 0
```

```typescript
// CDK
new cloudfront.Distribution(this, 'Distribution', {
  errorResponses: [
    {
      httpStatus: 403,
      responseHttpStatus: 200,
      responsePagePath: '/index.html',
      ttl: Duration.seconds(0),
    },
    {
      httpStatus: 404,
      responseHttpStatus: 200,
      responsePagePath: '/index.html',
      ttl: Duration.seconds(0),
    },
  ],
});
```

## Why Both 403 and 404?

| Error | When It Occurs |
|-------|----------------|
| 403 | S3 returns this for non-existent objects (with OAC) |
| 404 | Some configurations return 404 instead |

**Always configure both** to handle all cases.

## Error Caching TTL

Set `ErrorCachingMinTTL: 0` to ensure:
- Fresh `index.html` is always served
- Route changes take effect immediately
- No stale error responses cached

## Common SPA Pitfalls

### 1. Forgetting to Configure Error Responses

**Symptom:** Direct URL access returns 403/404
**Solution:** Add custom error responses as shown above

### 2. Caching Error Responses Too Long

**Symptom:** After deploying, some routes still 404
**Solution:** Set `ErrorCachingMinTTL: 0`

### 3. API Routes Returning index.html

**Symptom:** API calls return HTML instead of JSON
**Solution:** Use separate origin/behavior for API, or prefix API routes

```
# CloudFront behaviors (order matters)
1. /api/*  → API Gateway origin (no error response override)
2. *       → S3 origin (with error response override)
```

### 4. Static Assets Returning index.html

**Symptom:** Missing images/CSS return index.html (200 OK)
**Solution:** This is expected behavior. Fix the missing asset, don't change config.

### 5. Hash-Based Routing Not Working

**Symptom:** `/#/dashboard` works but `/dashboard` doesn't
**Solution:** 
- Hash routing (`/#/route`) doesn't need server config
- History routing (`/route`) needs custom error responses
- Most modern SPAs use history routing — configure error responses

## Framework-Specific Notes

### React (Create React App / Vite)

```javascript
// React Router v6
import { BrowserRouter } from 'react-router-dom';

// Uses history API — needs CloudFront error responses
<BrowserRouter>
  <Routes>
    <Route path="/dashboard" element={<Dashboard />} />
  </Routes>
</BrowserRouter>
```

### Vue (Vue Router)

```javascript
// vue-router
const router = createRouter({
  history: createWebHistory(), // Needs CloudFront error responses
  // history: createWebHashHistory(), // Doesn't need server config
  routes: [...]
});
```

### Angular

```typescript
// app-routing.module.ts
@NgModule({
  imports: [RouterModule.forRoot(routes, {
    useHash: false // Default, needs CloudFront error responses
  })],
})
```

### Next.js (Static Export)

```javascript
// next.config.js
module.exports = {
  output: 'export',
  trailingSlash: true, // Generates /about/index.html instead of /about.html
};
```

**Note:** With `trailingSlash: true`, Next.js generates actual HTML files for each route. You may not need custom error responses if all routes are pre-rendered.

## Testing SPA Routing

### Manual Testing

```bash
# Test direct URL access
curl -I https://your-site.cloudfront.net/dashboard/settings

# Should return:
# HTTP/2 200
# content-type: text/html
# (index.html content)
```

### Automated Testing

```bash
#!/bin/bash
SITE_URL="https://your-site.cloudfront.net"

ROUTES=(
  "/"
  "/dashboard"
  "/dashboard/settings"
  "/users/123"
  "/about"
)

for route in "${ROUTES[@]}"; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$SITE_URL$route")
  if [ "$STATUS" = "200" ]; then
    echo "✅ $route → $STATUS"
  else
    echo "❌ $route → $STATUS"
  fi
done
```

## Handling Real 404s

With custom error responses, all missing routes return `index.html`. Handle actual 404s in your app:

```javascript
// React Router v6
<Routes>
  <Route path="/" element={<Home />} />
  <Route path="/dashboard" element={<Dashboard />} />
  <Route path="*" element={<NotFound />} /> {/* Catch-all */}
</Routes>
```

```javascript
// NotFound component
function NotFound() {
  return (
    <div>
      <h1>404 - Page Not Found</h1>
      <a href="/">Go Home</a>
    </div>
  );
}
```

## SEO Considerations

SPAs with client-side routing can have SEO challenges:

1. **Pre-rendering:** Use tools like `react-snap` or `prerender-spa-plugin`
2. **SSG:** Consider Next.js/Gatsby for static generation
3. **Meta tags:** Use `react-helmet` or similar for dynamic meta tags
4. **Sitemap:** Generate sitemap.xml with all routes

For SEO-critical sites, consider:
- Static Site Generation (SSG) instead of pure SPA
- Server-Side Rendering (SSR) with Lambda@Edge or CloudFront Functions

---

**Next:** Read `05-troubleshooting` for common issues and solutions.
