# Static Web Deploy Power

A [Kiro Power](https://kiro.dev) for production-grade static website deployment to AWS using S3 (private origin), CloudFront with OAC, and GitOps CI/CD via CodeBuild.

## Installation

In Kiro, add this power via Git Repository:

```
https://github.com/Canodez/static-web-deploy-power
```

## Features

- **Secure by default** — S3 private bucket, CloudFront OAC (not legacy OAI), HTTPS-only
- **GitOps workflow** — All deployments flow from Git, no manual deploys to production
- **CI/CD ready** — CodeBuild templates with least-privilege IAM policies
- **Smart caching** — Proper Cache-Control headers, safe invalidation defaults
- **SPA support** — CloudFront custom error responses for client-side routing

## What's Included

| File | Purpose |
|------|---------|
| `POWER.md` | Main documentation and onboarding |
| `steering/` | Workflow guides (architecture, GitOps, CI/CD, caching, SPA, troubleshooting) |
| `templates/` | Ready-to-use buildspec.yml and deployment scripts |
| `hooks/` | Kiro agent hooks for common tasks |

## Documentation

See [POWER.md](POWER.md) for full documentation including:
- Step-by-step onboarding
- Security baseline requirements
- Cache-Control strategies
- Troubleshooting guide

## License

MIT
