# CI/CD with CodeBuild

AWS CodeBuild handles building and deploying static sites. Two patterns available: CodePipeline orchestration (enterprise) or direct webhook triggers (simpler).

## Pattern Comparison

| Aspect | CodePipeline + CodeBuild | CodeBuild Webhook |
|--------|--------------------------|-------------------|
| Complexity | Higher | Lower |
| Visual Pipeline | Yes | No |
| Approval Gates | Built-in | Manual |
| Multi-Stage | Native support | Script-based |
| Cost | Pipeline + Build | Build only |
| Best For | Enterprise, compliance | Small teams, startups |

**Recommendation:** Start with CodeBuild webhook. Add CodePipeline when you need approval gates or complex orchestration.

## Pattern A: CodeBuild with Webhook (Recommended Start)

### Create CodeBuild Project

```bash
# Variables
PROJECT_NAME="mysite-deploy"
REPO_URL="https://github.com/org/repo.git"
BUCKET_NAME="mysite-static-prod"
DISTRIBUTION_ID="E1234567890ABC"

# Create CodeBuild project
aws codebuild create-project \
  --name $PROJECT_NAME \
  --source '{
    "type": "GITHUB",
    "location": "'$REPO_URL'",
    "buildspec": "buildspec.yml",
    "auth": {
      "type": "OAUTH"
    }
  }' \
  --artifacts '{"type": "NO_ARTIFACTS"}' \
  --environment '{
    "type": "LINUX_CONTAINER",
    "image": "aws/codebuild/amazonlinux2-x86_64-standard:5.0",
    "computeType": "BUILD_GENERAL1_SMALL",
    "environmentVariables": [
      {"name": "S3_BUCKET", "value": "'$BUCKET_NAME'"},
      {"name": "CLOUDFRONT_DISTRIBUTION_ID", "value": "'$DISTRIBUTION_ID'"},
      {"name": "BUILD_DIR", "value": "dist"},
      {"name": "SITE_TYPE", "value": "static"}
    ]
  }' \
  --service-role "arn:aws:iam::$ACCOUNT_ID:role/CodeBuildServiceRole"
```

### Create Webhook

```bash
aws codebuild create-webhook \
  --project-name $PROJECT_NAME \
  --filter-groups '[[
    {"type": "EVENT", "pattern": "PUSH"},
    {"type": "HEAD_REF", "pattern": "^refs/heads/main$"}
  ]]'
```

**Webhook Filters:**
- Triggers on push to `main` branch only
- Add additional filter groups for other branches/environments

## Pattern B: CodePipeline Orchestration

### Pipeline Structure

```
Source (GitHub) → Build (CodeBuild) → [Approval] → Deploy (CodeBuild)
```

### Create Pipeline

```bash
aws codepipeline create-pipeline --pipeline '{
  "name": "mysite-pipeline",
  "roleArn": "arn:aws:iam::ACCOUNT_ID:role/CodePipelineServiceRole",
  "stages": [
    {
      "name": "Source",
      "actions": [{
        "name": "GitHub",
        "actionTypeId": {
          "category": "Source",
          "owner": "AWS",
          "provider": "CodeStarSourceConnection",
          "version": "1"
        },
        "configuration": {
          "ConnectionArn": "arn:aws:codestar-connections:REGION:ACCOUNT_ID:connection/CONNECTION_ID",
          "FullRepositoryId": "org/repo",
          "BranchName": "main"
        },
        "outputArtifacts": [{"name": "SourceOutput"}]
      }]
    },
    {
      "name": "Build",
      "actions": [{
        "name": "Build",
        "actionTypeId": {
          "category": "Build",
          "owner": "AWS",
          "provider": "CodeBuild",
          "version": "1"
        },
        "configuration": {
          "ProjectName": "mysite-build"
        },
        "inputArtifacts": [{"name": "SourceOutput"}],
        "outputArtifacts": [{"name": "BuildOutput"}]
      }]
    },
    {
      "name": "Deploy",
      "actions": [{
        "name": "Deploy",
        "actionTypeId": {
          "category": "Build",
          "owner": "AWS",
          "provider": "CodeBuild",
          "version": "1"
        },
        "configuration": {
          "ProjectName": "mysite-deploy"
        },
        "inputArtifacts": [{"name": "BuildOutput"}]
      }]
    }
  ]
}'
```

## IAM Policies

### CodeBuild Service Role (Least Privilege)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3Deploy",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ]
    },
    {
      "Sid": "CloudFrontInvalidation",
      "Effect": "Allow",
      "Action": "cloudfront:CreateInvalidation",
      "Resource": "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${DISTRIBUTION_ID}"
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:${REGION}:${ACCOUNT_ID}:log-group:/aws/codebuild/${PROJECT_NAME}:*"
    },
    {
      "Sid": "SSMParameterStore",
      "Effect": "Allow",
      "Action": "ssm:GetParameters",
      "Resource": "arn:aws:ssm:${REGION}:${ACCOUNT_ID}:parameter/mysite/*"
    }
  ]
}
```

### Trust Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Service": "codebuild.amazonaws.com"
    },
    "Action": "sts:AssumeRole"
  }]
}
```

### Create IAM Role

```bash
# Create role
aws iam create-role \
  --role-name CodeBuildServiceRole \
  --assume-role-policy-document file://trust-policy.json

# Attach policy
aws iam put-role-policy \
  --role-name CodeBuildServiceRole \
  --policy-name CodeBuildDeployPolicy \
  --policy-document file://codebuild-policy.json
```

## Buildspec Reference

### Complete buildspec.yml

```yaml
version: 0.2

env:
  variables:
    BUILD_DIR: "dist"
    SITE_TYPE: "static"
  parameter-store:
    # Optional: pull secrets from Parameter Store
    # API_KEY: "/mysite/api-key"

phases:
  install:
    runtime-versions:
      nodejs: 20
    commands:
      - echo "Installing dependencies..."
      - npm ci --prefer-offline

  pre_build:
    commands:
      - echo "Running pre-build checks..."
      - npm run lint || true
      - npm run test -- --passWithNoTests || true

  build:
    commands:
      - echo "Building site..."
      - npm run build
      - echo "Build complete. Output in $BUILD_DIR"

  post_build:
    commands:
      - echo "Deploying to S3..."
      - |
        # Sync with delete, exclude index.html for separate handling
        aws s3 sync $BUILD_DIR s3://$S3_BUCKET \
          --delete \
          --exclude "index.html" \
          --cache-control "max-age=31536000, immutable"
      - |
        # Upload index.html with no-cache
        aws s3 cp $BUILD_DIR/index.html s3://$S3_BUCKET/index.html \
          --cache-control "no-cache, no-store, must-revalidate"
      - |
        # Upload other HTML files with short cache
        find $BUILD_DIR -name "*.html" ! -name "index.html" -exec \
          aws s3 cp {} s3://$S3_BUCKET/{} \
          --cache-control "max-age=300" \;
      - echo "Invalidating CloudFront..."
      - |
        aws cloudfront create-invalidation \
          --distribution-id $CLOUDFRONT_DISTRIBUTION_ID \
          --paths "/index.html"
      - echo "Deployment complete!"

cache:
  paths:
    - node_modules/**/*
```

### Environment-Specific Builds

For multi-environment deployments:

```yaml
version: 0.2

env:
  variables:
    BUILD_DIR: "dist"

phases:
  build:
    commands:
      - |
        case "$ENVIRONMENT" in
          "production")
            npm run build:prod
            ;;
          "staging")
            npm run build:staging
            ;;
          *)
            npm run build
            ;;
        esac

  post_build:
    commands:
      - |
        case "$ENVIRONMENT" in
          "production")
            S3_BUCKET="mysite-prod"
            CF_DIST="E1234567890ABC"
            ;;
          "staging")
            S3_BUCKET="mysite-staging"
            CF_DIST="E0987654321XYZ"
            ;;
        esac
        aws s3 sync $BUILD_DIR s3://$S3_BUCKET --delete
        aws cloudfront create-invalidation --distribution-id $CF_DIST --paths "/index.html"
```

## Environment Variables

### Secure Variables (Parameter Store)

Store sensitive values in Parameter Store:

```bash
# Store secret
aws ssm put-parameter \
  --name "/mysite/api-key" \
  --value "sk-secret-key" \
  --type "SecureString"

# Reference in buildspec
env:
  parameter-store:
    API_KEY: "/mysite/api-key"
```

### Build-Time Variables

Set in CodeBuild project:

| Variable | Description | Example |
|----------|-------------|---------|
| `S3_BUCKET` | Target S3 bucket | `mysite-static-prod` |
| `CLOUDFRONT_DISTRIBUTION_ID` | CloudFront distribution | `E1234567890ABC` |
| `BUILD_DIR` | Build output directory | `dist` |
| `SITE_TYPE` | Site type for routing | `static` or `spa` |
| `ENVIRONMENT` | Deployment environment | `production` |

## Build Notifications

### SNS Notifications

```bash
# Create SNS topic
aws sns create-topic --name codebuild-notifications

# Subscribe email
aws sns subscribe \
  --topic-arn arn:aws:sns:REGION:ACCOUNT_ID:codebuild-notifications \
  --protocol email \
  --notification-endpoint team@example.com

# Create CloudWatch Events rule
aws events put-rule \
  --name codebuild-status \
  --event-pattern '{
    "source": ["aws.codebuild"],
    "detail-type": ["CodeBuild Build State Change"],
    "detail": {
      "project-name": ["mysite-deploy"],
      "build-status": ["FAILED", "SUCCEEDED"]
    }
  }'

# Add target
aws events put-targets \
  --rule codebuild-status \
  --targets '[{
    "Id": "sns",
    "Arn": "arn:aws:sns:REGION:ACCOUNT_ID:codebuild-notifications"
  }]'
```

## Troubleshooting Builds

### Common Issues

**Build fails: npm ci error**
```
npm ERR! code ENOENT
```
- Ensure `package-lock.json` is committed
- Check Node.js version matches local

**S3 sync fails: Access Denied**
```
fatal error: An error occurred (AccessDenied)
```
- Verify CodeBuild role has S3 permissions
- Check bucket name is correct
- Ensure bucket exists

**CloudFront invalidation fails**
```
An error occurred (AccessDenied) when calling CreateInvalidation
```
- Verify CodeBuild role has `cloudfront:CreateInvalidation`
- Check distribution ID is correct

### Debug Mode

Add to buildspec for verbose output:

```yaml
phases:
  install:
    commands:
      - set -x  # Enable debug output
      - aws --version
      - node --version
      - npm --version
```

### View Build Logs

```bash
# Get recent builds
aws codebuild list-builds-for-project --project-name mysite-deploy

# Get build details
aws codebuild batch-get-builds --ids BUILD_ID

# Stream logs (requires CloudWatch Logs)
aws logs tail /aws/codebuild/mysite-deploy --follow
```

---

**Next:** Read `03-caching-and-headers` to optimize cache behavior.
