#!/bin/bash

# Dev Box Teardown Script
set -e

STACK_NAME=${1:-dev-box-core}

# If no stack name provided, show available options
if [ "$1" = "" ]; then
    echo ""
    echo "Please specify which stack to delete:"
    echo "  ./teardown.sh dev-box-core     (core infrastructure)"
    echo "  ./teardown.sh dev-box-backup   (backup configuration)"
    echo "  ./teardown.sh dev-box-shared   (shared resources)"
    echo ""
    echo "Or delete all stacks:"
    echo "  ./teardown.sh dev-box-core && ./teardown.sh dev-box-backup && ./teardown.sh dev-box-shared"
    echo ""
    exit 1
fi
REGION=${AWS_DEFAULT_REGION:-us-west-2}

# Safety confirmation prompts
echo ""
echo "WARNING: This will PERMANENTLY DELETE your infrastructure!"
echo "This action CANNOT be undone!"
echo ""
echo "Stack to delete: $STACK_NAME"
echo "Region: $REGION"
echo ""

# First confirmation
read -p "Are you sure you want to delete $STACK_NAME? Type 'yes' to continue: " confirm1
if [ "$confirm1" != "yes" ]; then
    echo "Teardown cancelled."
    exit 1
fi

# Second confirmation with stack details
echo ""
echo "Checking stack details..."
aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query 'Stacks[0].{Name:StackName,Status:StackStatus,CreationTime:CreationTime}' --output table 2>/dev/null || {
    echo "Stack $STACK_NAME not found or not accessible."
    exit 1
}

echo ""
read -p "FINAL WARNING: This will destroy ALL resources in $STACK_NAME. Type 'DELETE' to confirm: " confirm2
if [ "$confirm2" != "DELETE" ]; then
    echo "Teardown cancelled."
    exit 1
fi

echo ""
echo "Proceeding with teardown in 5 seconds..."
echo "   Press Ctrl+C to cancel"
sleep 5

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
echo "Dev Box Teardown Script"
echo "=========================================="
echo "Stack Name: $STACK_NAME"
echo "Region: $REGION"
echo "=========================================="
echo ""

# Check if stack exists
log_info "Checking if stack '$STACK_NAME' exists..."
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" >/dev/null 2>&1; then
    log_error "Stack '$STACK_NAME' does not exist or you don't have access to it"
    exit 1
fi

# Get stack status
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query 'Stacks[0].StackStatus' --output text)
log_info "Current stack status: $STACK_STATUS"

# Check for running EC2 instances that might block deletion
log_info "Checking for running EC2 instances in the stack..."
INSTANCES=$(aws cloudformation list-stack-resources --stack-name "$STACK_NAME" --region "$REGION" --query 'StackResourceSummaries[?ResourceType==`AWS::EC2::Instance`].PhysicalResourceId' --output text 2>/dev/null || echo "")

if [ -n "$INSTANCES" ] && [ "$INSTANCES" != "None" ]; then
    log_warning "Found EC2 instances in the stack. Checking their status..."
    
    for INSTANCE_ID in $INSTANCES; do
        INSTANCE_STATE=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$REGION" --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "unknown")
        log_info "Instance $INSTANCE_ID is in state: $INSTANCE_STATE"
        
        if [ "$INSTANCE_STATE" = "running" ]; then
            log_warning "Instance $INSTANCE_ID is still running. This may block stack deletion."
            echo ""
            read -p "Do you want to terminate this instance first? (y/N): " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "Terminating instance $INSTANCE_ID..."
                aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$REGION" >/dev/null
                log_success "Termination initiated for instance $INSTANCE_ID"
                
                log_info "Waiting for instance to terminate..."
                aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" --region "$REGION"
                log_success "Instance $INSTANCE_ID has been terminated"
            else
                log_warning "Skipping instance termination. Stack deletion may fail."
            fi
        fi
    done
fi

echo ""
log_info "Starting stack deletion..."
aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"

if [ $? -eq 0 ]; then
    log_success "Stack deletion initiated successfully"
    echo ""
    log_info "Waiting for stack deletion to complete..."
    echo "This may take several minutes..."
    echo ""
    
    # Wait for deletion to complete
    aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION"
    
    if [ $? -eq 0 ]; then
        log_success "Stack '$STACK_NAME' has been deleted successfully!"
    else
        log_error "Stack deletion failed or timed out"
        echo ""
        log_info "Checking stack status..."
        FINAL_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "STACK_NOT_FOUND")
        log_info "Final stack status: $FINAL_STATUS"
        
        if [ "$FINAL_STATUS" = "DELETE_FAILED" ]; then
            echo ""
            log_warning "Stack deletion failed. You may need to:"
            echo "1. Check the AWS Console for specific error details"
            echo "2. Manually delete any remaining resources"
            echo "3. Use 'aws cloudformation delete-stack --retain-resources <resource-name>' to force delete"
            echo ""
            log_info "Useful commands:"
            echo "aws cloudformation describe-stack-events --stack-name $STACK_NAME --region $REGION"
            echo "aws cloudformation list-stack-resources --stack-name $STACK_NAME --region $REGION"
        fi
    fi
else
    log_error "Failed to initiate stack deletion"
    exit 1
fi

echo ""
echo "=========================================="
log_success "Teardown completed!"
echo "=========================================="