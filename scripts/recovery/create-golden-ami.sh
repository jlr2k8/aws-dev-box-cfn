#!/bin/bash

# Script to create golden AMI for dev box
# Usage: ./create-golden-ami.sh [STACK_NAME]

STACK_NAME=${1:-dev-box-core}
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

log_ami() {
    echo -e "${BLUE}[AMI]${NC} $1"
}

log_info "Creating golden AMI for dev box..."

# Get the instance ID from the CloudFormation stack
INSTANCE_ID=$(aws cloudformation describe-stack-resources \
    --stack-name "$STACK_NAME" \
    --logical-resource-id "DevBox" \
    --region "$REGION" \
    --query 'StackResources[0].PhysicalResourceId' \
    --output text 2>/dev/null)

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
    log_error "Could not find DevBox instance in stack '$STACK_NAME'"
    exit 1
fi

log_info "Found instance: $INSTANCE_ID"

# Check if instance is running
INSTANCE_STATE=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null)

if [ "$INSTANCE_STATE" != "running" ]; then
    log_error "Instance is not running (current state: $INSTANCE_STATE)"
    echo "Please start the instance first:"
    echo "aws ec2 start-instances --instance-ids $INSTANCE_ID --region $REGION"
    exit 1
fi

# Create timestamp for AMI name
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
AMI_NAME="dev-box-golden-${TIMESTAMP}"
AMI_DESCRIPTION="Golden AMI for dev box created on $(date)"

log_ami "Creating AMI: $AMI_NAME"

# Create the AMI
AMI_ID=$(aws ec2 create-image \
    --instance-id "$INSTANCE_ID" \
    --name "$AMI_NAME" \
    --description "$AMI_DESCRIPTION" \
    --no-reboot \
    --region "$REGION" \
    --query 'ImageId' \
    --output text 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$AMI_ID" ]; then
    log_success "AMI creation initiated successfully!"
    echo ""
    echo "=========================================="
    echo "Golden AMI Details"
    echo "=========================================="
    echo "AMI ID: $AMI_ID"
    echo "AMI Name: $AMI_NAME"
    echo "Description: $AMI_DESCRIPTION"
    echo "=========================================="
    echo ""
    echo "To check AMI status:"
    echo "aws ec2 describe-images --image-ids $AMI_ID --region $REGION"
    echo ""
    echo "To use this AMI in future deployments, update the ImageId in dev-box-core.yaml:"
    echo "ImageId: $AMI_ID"
else
    log_error "Failed to create AMI"
    echo "Please ensure:"
    echo "1. The instance is running and accessible"
    echo "2. You have proper permissions to create AMIs"
    echo "3. The instance is not in a transitional state"
fi