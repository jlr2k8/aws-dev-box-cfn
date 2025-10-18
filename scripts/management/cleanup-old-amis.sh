#!/bin/bash

# Script to clean up old golden AMIs, keeping only the latest 5
# Usage: ./cleanup-old-amis.sh [STACK_NAME] [KEEP_COUNT]

STACK_NAME=${1:-dev-box-core}
KEEP_COUNT=${2:-5}
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

log_cleanup() {
    echo -e "${BLUE}[CLEANUP]${NC} $1"
}

echo "=========================================="
echo "Golden AMI Cleanup"
echo "=========================================="
echo "Keeping latest: $KEEP_COUNT AMIs"
echo "=========================================="
echo ""

# Get all golden AMIs sorted by creation date (newest first)
log_info "Fetching golden AMIs..."
AMIS=$(aws ec2 describe-images \
    --owners self \
    --filters "Name=name,Values=*dev-box-golden*" \
    --query 'Images | sort_by(@, &CreationDate) | reverse(@) | [*].{ImageId:ImageId,Name:Name,CreationDate:CreationDate,Size:BlockDeviceMappings[0].Ebs.VolumeSize}' \
    --output json)

TOTAL_AMIS=$(echo "$AMIS" | jq length)
log_info "Found $TOTAL_AMIS golden AMIs"

if [ "$TOTAL_AMIS" -le "$KEEP_COUNT" ]; then
    log_info "No cleanup needed - only $TOTAL_AMIS AMIs found (keeping $KEEP_COUNT)"
    exit 0
fi

# Calculate how many to delete
DELETE_COUNT=$((TOTAL_AMIS - KEEP_COUNT))
log_cleanup "Will delete $DELETE_COUNT old AMIs"

echo ""
echo "=========================================="
echo "AMIs to DELETE (oldest first):"
echo "=========================================="

# Get AMIs to delete (skip the first $KEEP_COUNT)
AMIS_TO_DELETE=$(echo "$AMIS" | jq ".[$KEEP_COUNT:]")

echo "$AMIS_TO_DELETE" | jq -r '.[] | "\(.ImageId) - \(.Name) (\(.CreationDate)) - \(.Size)GB"'

echo ""
echo "=========================================="
echo "AMIs to KEEP (newest):"
echo "=========================================="

# Get AMIs to keep
AMIS_TO_KEEP=$(echo "$AMIS" | jq ".[:$KEEP_COUNT]")

echo "$AMIS_TO_KEEP" | jq -r '.[] | "\(.ImageId) - \(.Name) (\(.CreationDate)) - \(.Size)GB"'

echo ""
read -p "Do you want to proceed with deletion? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Cleanup cancelled"
    exit 0
fi

echo ""
log_cleanup "Starting AMI deletion..."

# Delete AMIs
DELETED_COUNT=0
TOTAL_SAVINGS=0

echo "$AMIS_TO_DELETE" | jq -r '.[].ImageId' | while read -r ami_id; do
    if [ -n "$ami_id" ]; then
        log_info "Deleting AMI: $ami_id"
        
        # Get AMI size for cost calculation
        AMI_SIZE=$(echo "$AMIS_TO_DELETE" | jq -r ".[] | select(.ImageId==\"$ami_id\") | .Size")
        
        if aws ec2 deregister-image --image-id "$ami_id" --region "$REGION" > /dev/null 2>&1; then
            log_success "Deleted AMI: $ami_id"
            DELETED_COUNT=$((DELETED_COUNT + 1))
            # EBS snapshots cost ~$0.05/GB/month
            AMI_SAVINGS=$(echo "$AMI_SIZE * 0.05" | bc -l)
            TOTAL_SAVINGS=$(echo "$TOTAL_SAVINGS + $AMI_SAVINGS" | bc -l)
        else
            log_error "Failed to delete AMI: $ami_id"
        fi
    fi
done

echo ""
echo "=========================================="
log_success "AMI cleanup completed!"
echo "=========================================="
echo "Deleted AMIs: $DELETE_COUNT"
echo "Estimated monthly savings: \$$(printf "%.2f" $TOTAL_SAVINGS)"
echo "=========================================="