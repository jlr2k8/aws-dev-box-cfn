#!/bin/bash

# Single stack deployment script
# Usage: ./deploy.sh STACK_NAME TEMPLATE_FILE [PARAMETERS_FILE]

STACK_NAME=$1
TEMPLATE_FILE=$2
PARAMETERS_FILE=${3:-""}
REGION=${AWS_DEFAULT_REGION:-us-west-2}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

if [ -z "$STACK_NAME" ] || [ -z "$TEMPLATE_FILE" ]; then
    log_error "Usage: $0 STACK_NAME TEMPLATE_FILE [PARAMETERS_FILE]"
    exit 1
fi

log_info "Deploying stack: $STACK_NAME"

# Check if stack exists
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &> /dev/null; then
    log_info "Stack $STACK_NAME exists, updating..."
    
    if [ -n "$PARAMETERS_FILE" ]; then
        aws cloudformation update-stack \
            --stack-name "$STACK_NAME" \
            --template-body "file://$TEMPLATE_FILE" \
            --parameters "file://$PARAMETERS_FILE" \
            --capabilities CAPABILITY_IAM \
            --region "$REGION"
    else
        aws cloudformation update-stack \
            --stack-name "$STACK_NAME" \
            --template-body "file://$TEMPLATE_FILE" \
            --capabilities CAPABILITY_IAM \
            --region "$REGION"
    fi
    
    log_info "Waiting for stack update to complete..."
    aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME" --region "$REGION"
else
    log_info "Creating new stack: $STACK_NAME"
    
    if [ -n "$PARAMETERS_FILE" ]; then
        aws cloudformation create-stack \
            --stack-name "$STACK_NAME" \
            --template-body "file://$TEMPLATE_FILE" \
            --parameters "file://$PARAMETERS_FILE" \
            --capabilities CAPABILITY_IAM \
            --region "$REGION"
    else
        aws cloudformation create-stack \
            --stack-name "$STACK_NAME" \
            --template-body "file://$TEMPLATE_FILE" \
            --capabilities CAPABILITY_IAM \
            --region "$REGION"
    fi
    
    log_info "Waiting for stack creation to complete..."
    aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" --region "$REGION"
fi

if [ $? -eq 0 ]; then
    log_success "Stack $STACK_NAME deployed successfully"
else
    log_error "Stack $STACK_NAME deployment failed"
    exit 1
fi
