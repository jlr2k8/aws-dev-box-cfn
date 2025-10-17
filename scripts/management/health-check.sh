#!/bin/bash

# Health check script for dev box
# Usage: ./health-check.sh [STACK_NAME]

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

log_health() {
    echo -e "${BLUE}[HEALTH]${NC} $1"
}

log_info "Performing health check on dev box..."

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

# Check instance state
INSTANCE_STATE=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null)

log_health "Instance State: $INSTANCE_STATE"

if [ "$INSTANCE_STATE" != "running" ]; then
    log_error "Instance is not running!"
    exit 1
fi

# Check system status
SYSTEM_STATUS=$(aws ec2 describe-instance-status \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'InstanceStatuses[0].SystemStatus.Status' \
    --output text 2>/dev/null)

log_health "System Status: $SYSTEM_STATUS"

# Check instance status
INSTANCE_STATUS=$(aws ec2 describe-instance-status \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'InstanceStatuses[0].InstanceStatus.Status' \
    --output text 2>/dev/null)

log_health "Instance Status: $INSTANCE_STATUS"

# Check if RDP is accessible (port 3389)
PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text 2>/dev/null)

if [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "None" ]; then
    log_health "Public IP: $PUBLIC_IP"
    
    # Test RDP port connectivity
    if timeout 5 bash -c "</dev/tcp/$PUBLIC_IP/3389" 2>/dev/null; then
        log_success "RDP port 3389 is accessible"
    else
        log_error "RDP port 3389 is not accessible"
    fi
else
    log_error "No public IP address found"
fi

# Check backup status
LATEST_BACKUP=$(aws backup list-recovery-points \
    --backup-vault-name dev-dev-box-vault \
    --region "$REGION" \
    --query 'RecoveryPoints[0].CreationDate' \
    --output text 2>/dev/null)

if [ -n "$LATEST_BACKUP" ] && [ "$LATEST_BACKUP" != "None" ]; then
    log_health "Latest backup: $LATEST_BACKUP"
    
    # Check if backup is recent (within 24 hours)
    BACKUP_TIME=$(date -d "$LATEST_BACKUP" +%s 2>/dev/null || echo "0")
    CURRENT_TIME=$(date +%s)
    TIME_DIFF=$((CURRENT_TIME - BACKUP_TIME))
    
    if [ $TIME_DIFF -lt 86400 ]; then  # 24 hours in seconds
        log_success "Recent backup available (within 24 hours)"
    else
        log_error "No recent backup found (older than 24 hours)"
    fi
else
    log_error "No backups found"
fi

# Overall health status
if [ "$INSTANCE_STATE" = "running" ] && [ "$SYSTEM_STATUS" = "ok" ] && [ "$INSTANCE_STATUS" = "ok" ]; then
    echo ""
    log_success "Dev box is healthy!"
    exit 0
else
    echo ""
    log_error "Dev box has health issues!"
    exit 1
fi