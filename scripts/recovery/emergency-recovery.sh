#!/bin/bash

# Emergency recovery script for dev box
# Usage: ./emergency-recovery.sh [STACK_NAME] [--force]

STACK_NAME=${1:-dev-box-core}
REGION=${AWS_DEFAULT_REGION:-us-west-2}
FORCE_RECOVERY=false

# Check for --force flag
if [[ "$*" == *"--force"* ]]; then
    FORCE_RECOVERY=true
fi

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

log_emergency() {
    echo -e "${BLUE}[EMERGENCY]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo "=========================================="
log_emergency "EMERGENCY RECOVERY PROCEDURE"
echo "=========================================="
echo ""

if [ "$FORCE_RECOVERY" = false ]; then
    log_warning "This is an EMERGENCY recovery procedure!"
    log_warning "It will attempt to restore your dev box from backup."
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "Recovery cancelled by user"
        exit 0
    fi
fi

log_info "Starting emergency recovery procedure..."

# Step 1: Check current instance status
log_info "Step 1: Checking current instance status..."

INSTANCE_ID=$(aws cloudformation describe-stack-resources \
    --stack-name "$STACK_NAME" \
    --logical-resource-id "DevBox" \
    --region "$REGION" \
    --query 'StackResources[0].PhysicalResourceId' \
    --output text 2>/dev/null)

if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ]; then
    INSTANCE_STATE=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --region "$REGION" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null)
    
    log_info "Current instance: $INSTANCE_ID (State: $INSTANCE_STATE)"
    
    if [ "$INSTANCE_STATE" = "running" ]; then
        log_warning "Instance is currently running. Recovery may not be necessary."
        read -p "Continue anyway? (yes/no): " continue_anyway
        if [ "$continue_anyway" != "yes" ]; then
            log_info "Recovery cancelled"
            exit 0
        fi
    fi
else
    log_error "Could not find current instance in stack"
fi

# Step 2: Find latest backup
log_info "Step 2: Finding latest backup..."

LATEST_BACKUP=$(aws backup list-recovery-points \
    --backup-vault-name dev-dev-box-vault \
    --region "$REGION" \
    --query 'RecoveryPoints[0].RecoveryPointArn' \
    --output text 2>/dev/null)

if [ -z "$LATEST_BACKUP" ] || [ "$LATEST_BACKUP" = "None" ]; then
    log_error "No backups found in vault 'dev-dev-box-vault'"
    echo ""
    echo "Alternative recovery options:"
    echo "1. Check other backup vaults"
    echo "2. Look for AMI snapshots"
    echo "3. Manual instance recreation"
    exit 1
fi

BACKUP_DATE=$(aws backup list-recovery-points \
    --backup-vault-name dev-dev-box-vault \
    --region "$REGION" \
    --query 'RecoveryPoints[0].CreationDate' \
    --output text 2>/dev/null)

log_success "Found latest backup: $LATEST_BACKUP"
log_info "Backup date: $BACKUP_DATE"

# Step 3: Start restore job
log_info "Step 3: Starting restore job..."

RESTORE_METADATA='{"InstanceId":"'$INSTANCE_ID'"}'

RESTORE_JOB_ID=$(aws backup start-restore-job \
    --recovery-point-arn "$LATEST_BACKUP" \
    --metadata "$RESTORE_METADATA" \
    --region "$REGION" \
    --query 'RestoreJobId' \
    --output text 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$RESTORE_JOB_ID" ]; then
    log_success "Restore job started successfully!"
    echo ""
    echo "=========================================="
    echo "Recovery Job Details"
    echo "=========================================="
    echo "Restore Job ID: $RESTORE_JOB_ID"
    echo "Backup ARN: $LATEST_BACKUP"
    echo "Target Instance: $INSTANCE_ID"
    echo "=========================================="
    echo ""
    echo "To monitor restore progress:"
    echo "aws backup describe-restore-job --restore-job-id $RESTORE_JOB_ID --region $REGION"
    echo ""
    echo "To check restore status:"
    echo "aws backup list-restore-jobs --region $REGION"
else
    log_error "Failed to start restore job"
    echo ""
    echo "Manual recovery steps:"
    echo "1. Create new instance from AMI"
    echo "2. Update CloudFormation stack with new instance ID"
    echo "3. Update DNS records if needed"
    exit 1
fi

# Step 4: Wait for completion (optional)
if [ "$FORCE_RECOVERY" = true ]; then
    log_info "Step 4: Waiting for restore completion..."
    
    while true; do
        RESTORE_STATUS=$(aws backup describe-restore-job \
            --restore-job-id "$RESTORE_JOB_ID" \
            --region "$REGION" \
            --query 'Status' \
            --output text 2>/dev/null)
        
        log_info "Restore status: $RESTORE_STATUS"
        
        if [ "$RESTORE_STATUS" = "COMPLETED" ]; then
            log_success "Restore completed successfully!"
            break
        elif [ "$RESTORE_STATUS" = "FAILED" ] || [ "$RESTORE_STATUS" = "ABORTED" ]; then
            log_error "Restore failed with status: $RESTORE_STATUS"
            exit 1
        fi
        
        sleep 30
    done
else
    log_info "Step 4: Restore job is running in background"
    log_info "Monitor progress with the commands shown above"
fi

log_success "Emergency recovery procedure completed!"
echo ""
echo "Next steps:"
echo "1. Verify instance is running: ./health-check.sh $STACK_NAME"
echo "2. Test RDP connectivity"
echo "3. Update password if needed: ./get-password.sh $STACK_NAME --apply"