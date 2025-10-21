#!/bin/bash

# Fix dynamic IP issue for dev box - all-in-one solution
# Usage: ./fix-dynamic-ip.sh [INSTANCE_ID]

INSTANCE_ID=${1:-""}
STACK_NAME="dev-box-core"
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

# Function to get current public IP
get_current_ip() {
    log_info "Detecting your current public IP..."
    local ip=$(curl -s https://checkip.amazonaws.com/ 2>/dev/null || curl -s https://ipinfo.io/ip 2>/dev/null || echo "unknown")
    if [ "$ip" = "unknown" ]; then
        log_error "Could not determine your public IP"
        return 1
    fi
    echo "$ip"
}

# Function to get instance ID if not provided
get_instance_id() {
    if [ -n "$INSTANCE_ID" ]; then
        echo "$INSTANCE_ID"
        return
    fi
    
    log_info "Looking for dev box instance..."
    
    # Try to get from CloudFormation stack
    local cf_instance_id=$(aws cloudformation describe-stack-resources \
        --stack-name "$STACK_NAME" \
        --logical-resource-id "DevBox" \
        --region "$REGION" \
        --query 'StackResources[0].PhysicalResourceId' \
        --output text 2>/dev/null)
    
    if [ -n "$cf_instance_id" ] && [ "$cf_instance_id" != "None" ]; then
        echo "$cf_instance_id"
        return
    fi
    
    # Fallback: find by name pattern
    local instance_id=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters "Name=tag:Name,Values=*dev-box*" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text 2>/dev/null)
    
    if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
        echo "$instance_id"
    else
        return 1
    fi
}

# Function to get security group ID
get_security_group_id() {
    local instance_id=$1
    aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$REGION" \
        --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
        --output text 2>/dev/null
}

# Function to get instance public IP
get_instance_public_ip() {
    local instance_id=$1
    aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$REGION" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text 2>/dev/null
}

# Function to check if instance is running
check_instance_status() {
    local instance_id=$1
    local state=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$REGION" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null)
    
    if [ "$state" = "running" ]; then
        return 0
    else
        log_error "Instance is not running (state: $state)"
        return 1
    fi
}

# Function to update security group rules
update_security_group() {
    local sg_id=$1
    local current_ip=$2
    
    log_info "Updating security group $sg_id for IP $current_ip"
    
    # Remove old specific IP rules (keep 0.0.0.0/0 rules)
    log_info "Cleaning up old IP-specific rules..."
    aws ec2 describe-security-groups \
        --group-ids "$sg_id" \
        --region "$REGION" \
        --query 'SecurityGroups[0].IpPermissions' \
        --output json 2>/dev/null | jq -r '.[] | select(.IpRanges[].CidrIp != "0.0.0.0/0") | .' | while read -r rule; do
        if [ -n "$rule" ] && [ "$rule" != "null" ]; then
            aws ec2 revoke-security-group-ingress \
                --group-id "$sg_id" \
                --ip-permissions "$rule" \
                --region "$REGION" 2>/dev/null || true
        fi
    done
    
    # Add new rule for current IP
    log_info "Adding rule for current IP: $current_ip/32"
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 3389 \
        --cidr "$current_ip/32" \
        --region "$REGION" 2>/dev/null || log_info "RDP rule may already exist"
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 22 \
        --cidr "$current_ip/32" \
        --region "$REGION" 2>/dev/null || log_info "SSH rule may already exist"
}

# Function to test connectivity
test_connectivity() {
    local instance_id=$1
    local public_ip=$(get_instance_public_ip "$instance_id")
    
    if [ -n "$public_ip" ] && [ "$public_ip" != "None" ]; then
        log_info "Testing RDP connectivity to $public_ip:3389"
        if timeout 5 bash -c "</dev/tcp/$public_ip/3389" 2>/dev/null; then
            log_success "RDP port 3389 is accessible"
            return 0
        else
            log_error "RDP port 3389 is not accessible"
            return 1
        fi
    else
        log_error "No public IP found for instance"
        return 1
    fi
}

# Function to setup Session Manager as backup
setup_session_manager() {
    local instance_id=$1
    
    log_info "Checking Session Manager availability..."
    
    local ssm_status=$(aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$instance_id" \
        --region "$REGION" \
        --query 'InstanceInformationList[0].PingStatus' \
        --output text 2>/dev/null)
    
    if [ "$ssm_status" = "Online" ]; then
        log_success "Session Manager is available as backup access method"
        log_info "To connect via Session Manager:"
        log_info "aws ssm start-session --target $instance_id --region $REGION"
        return 0
    else
        log_error "Session Manager is not available (status: $ssm_status)"
        return 1
    fi
}

# Main execution
main() {
    echo -e "${BLUE}=== Dev Box Dynamic IP Fix ===${NC}"
    echo ""
    
    # Get current IP
    local current_ip=$(get_current_ip)
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    log_success "Current public IP: $current_ip"
    
    # Get instance ID
    local instance_id=$(get_instance_id)
    if [ $? -ne 0 ] || [ -z "$instance_id" ] || [ "$instance_id" = "None" ]; then
        log_error "Could not find dev box instance"
        log_info "Please provide instance ID: $0 <INSTANCE_ID>"
        exit 1
    fi
    
    log_success "Found instance: $instance_id"
    
    # Check instance status
    if ! check_instance_status "$instance_id"; then
        exit 1
    fi
    
    # Get security group ID
    local sg_id=$(get_security_group_id "$instance_id")
    if [ -z "$sg_id" ] || [ "$sg_id" = "None" ]; then
        log_error "Could not find security group for instance"
        exit 1
    fi
    
    log_success "Found security group: $sg_id"
    
    # Update security group
    update_security_group "$sg_id" "$current_ip"
    
    # Test connectivity
    log_info "Testing connectivity..."
    if test_connectivity "$instance_id"; then
        log_success "Dev box is now accessible from your current IP!"
    else
        log_error "Connectivity test failed. Setting up Session Manager as backup..."
        setup_session_manager "$instance_id"
    fi
    
    # Show connection info
    local public_ip=$(get_instance_public_ip "$instance_id")
    
    echo ""
    log_success "=== CONNECTION INFO ==="
    log_info "RDP to: $public_ip"
    log_info "Username/Password: Check Secrets Manager"
    log_info "Session Manager: aws ssm start-session --target $instance_id --region $REGION"
    echo ""
    log_info "To run this script again when your IP changes:"
    log_info "./fix-dynamic-ip.sh $instance_id"
}

# Check dependencies
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed or not in PATH"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    log_error "jq is not installed. Please install jq for JSON processing"
    exit 1
fi

# Run main function
main "$@"