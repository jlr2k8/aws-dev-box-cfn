# Deployment Guide

## Quick Start

### Single Stack Deployment
```bash
# Deploy core infrastructure only
./scripts/deployment/deploy.sh dev-box-core infrastructure/core/dev-box-core.yaml infrastructure/core/parameters-core.json
```

### Multi-Stack Deployment
```bash
# Deploy complete infrastructure with backup
./scripts/deployment/deploy-multi.sh dev-box
```

## Environment-Specific Deployments

### Development Environment
```bash
# Use dev parameters
cp examples/parameters/dev.json infrastructure/core/parameters-core.json
./scripts/deployment/deploy-multi.sh dev-box-dev
```

### Staging Environment
```bash
# Use staging parameters
cp examples/parameters/staging.json infrastructure/core/parameters-core.json
./scripts/deployment/deploy-multi.sh dev-box-staging
```

### Production Environment
```bash
# Use production parameters
cp examples/parameters/prod.json infrastructure/core/parameters-core.json
./scripts/deployment/deploy-multi.sh dev-box-prod
```

## Custom Deployments

### Custom Parameters
1. Copy example parameters: `cp examples/parameters/dev.json my-params.json`
2. Edit parameters as needed
3. Deploy with custom parameters: `./scripts/deployment/deploy.sh my-stack infrastructure/core/dev-box-core.yaml my-params.json`

### Custom Templates
1. Copy template: `cp infrastructure/core/dev-box-core.yaml my-template.yaml`
2. Modify template as needed
3. Deploy with custom template: `./scripts/deployment/deploy.sh my-stack my-template.yaml`

## Troubleshooting

### Common Issues
- **Stack already exists**: Use update instead of create
- **Missing parameters**: Check parameter file format
- **Permission errors**: Ensure AWS CLI is configured
- **Template errors**: Validate CloudFormation syntax

### Validation
```bash
# Validate template
aws cloudformation validate-template --template-body file://infrastructure/core/dev-box-core.yaml

# Check stack status
aws cloudformation describe-stacks --stack-name dev-box-core
```