#!/bin/bash

# Multi-Stack Dev Box Deployment Script
set -e

STACK_PREFIX=${1:-dev-box}
REGION=${AWS_DEFAULT_REGION:-us-west-2}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${BLUE}[WARNING]${NC} $1"
}

echo "=========================================="
echo "Multi-Stack Dev Box Deployment"
echo "=========================================="
echo "Stack Prefix: $STACK_PREFIX"
echo "Region: $REGION"
echo "=========================================="
echo ""

# Check AWS CLI
log_info "Checking AWS CLI..."
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed"
    exit 1
fi
log_success "AWS CLI is installed"

# Check if we're logged in
log_info "Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured"
    exit 1
fi
log_success "AWS credentials configured"

# Function to deploy a stack
deploy_stack() {
    local stack_name=$1
    local template_file=$2
    local parameters_file=$3
    local depends_on=$4
    
    log_info "Deploying stack: $stack_name"
    
    # Wait for dependency if specified
    if [ -n "$depends_on" ]; then
        log_info "Waiting for dependency: $depends_on"
        aws cloudformation wait stack-create-complete --stack-name "$depends_on" --region "$REGION" 2>/dev/null || \
        aws cloudformation wait stack-update-complete --stack-name "$depends_on" --region "$REGION" 2>/dev/null || \
        log_warning "Dependency $depends_on may not be in CREATE_COMPLETE or UPDATE_COMPLETE state"
    fi
    
    # Check if stack exists
    if aws cloudformation describe-stacks --stack-name "$stack_name" --region "$REGION" &> /dev/null; then
        log_info "Stack $stack_name exists, updating..."
        aws cloudformation update-stack \
            --stack-name "$stack_name" \
            --template-body "file://$template_file" \
            --parameters "file://$parameters_file" \
            --capabilities CAPABILITY_IAM \
            --region "$REGION" > /dev/null
        
        log_info "Waiting for stack update to complete..."
        aws cloudformation wait stack-update-complete --stack-name "$stack_name" --region "$REGION"
    else
        log_info "Creating new stack: $stack_name"
        aws cloudformation create-stack \
            --stack-name "$stack_name" \
            --template-body "file://$template_file" \
            --parameters "file://$parameters_file" \
            --capabilities CAPABILITY_IAM \
            --region "$REGION" > /dev/null
        
        log_info "Waiting for stack creation to complete..."
        aws cloudformation wait stack-create-complete --stack-name "$stack_name" --region "$REGION"
    fi
    
    if [ $? -eq 0 ]; then
        log_success "Stack $stack_name deployed successfully"
    else
        log_error "Stack $stack_name deployment failed"
        return 1
    fi
}

# Deploy stacks in order
log_info "Starting multi-stack deployment..."

# 1. Deploy shared resources first (if needed)
# deploy_stack "${STACK_PREFIX}-shared" "dev-box-shared.yaml" "parameters-shared.json"

# 2. Deploy core infrastructure
deploy_stack "${STACK_PREFIX}-core" "dev-box-core.yaml" "parameters-core.json"

# 3. Deploy backup configuration
# Get instance ID from core stack
INSTANCE_ID=$(aws cloudformation describe-stacks --stack-name "${STACK_PREFIX}-core" --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`DevBoxInstanceId`].OutputValue' --output text 2>/dev/null || echo "")

if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ]; then
    # Update parameters with actual instance ID
    sed "s/PLACEHOLDER/$INSTANCE_ID/g" parameters-backup.json > parameters-backup-temp.json
    deploy_stack "${STACK_PREFIX}-backup" "dev-box-backup.yaml" "parameters-backup-temp.json" "${STACK_PREFIX}-core"
    rm -f parameters-backup-temp.json
else
    log_error "Could not get instance ID from core stack"
    exit 1
fi

echo ""
echo "=========================================="
log_success "Multi-stack deployment completed!"
echo "=========================================="

# Show connection information
log_info "Getting connection information..."
CORE_STACK_NAME="${STACK_PREFIX}-core"
PUBLIC_IP=$(aws cloudformation describe-stacks --stack-name "$CORE_STACK_NAME" --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`DevBoxPublicIP`].OutputValue' --output text 2>/dev/null || echo "Unknown")

echo ""
echo "=========================================="
echo "Dev Box Connection Information"
echo "=========================================="
echo "Public IP: $PUBLIC_IP"
DOMAIN_NAME=$(aws cloudformation describe-stacks --stack-name "$CORE_STACK_NAME" --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`DomainName`].OutputValue' --output text 2>/dev/null || echo "dev.yourdomain.com")
echo "Domain: $DOMAIN_NAME"
echo ""
echo "To get credentials:"
echo "./get-password.sh $CORE_STACK_NAME"
echo ""
echo "To connect via RDP:"
echo "mstsc /v:$DOMAIN_NAME"
echo "=========================================="