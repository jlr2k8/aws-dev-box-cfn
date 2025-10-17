#!/bin/bash

# Script to retrieve the dev box password from Secrets Manager
# Usage: ./get-password.sh [STACK_NAME] [SECRET_NAME] [--apply]

# Parse arguments
STACK_NAME=""
SECRET_NAME=""
APPLY_PASSWORD=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --apply)
            APPLY_PASSWORD=true
            ;;
        *)
            if [ -z "$STACK_NAME" ]; then
                STACK_NAME="$arg"
            elif [ "$arg" != "--apply" ]; then
                SECRET_NAME="$arg"
            fi
            ;;
    esac
done

# Set defaults
STACK_NAME=${STACK_NAME:-dev-box-core}
REGION=${AWS_DEFAULT_REGION:-us-west-2}

# Auto-detect secret name from CloudFormation stack if not provided
if [ -z "$SECRET_NAME" ]; then
    SECRET_NAME=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Parameters[?ParameterKey==`SecretsManagerSecretName`].ParameterValue' \
        --output text 2>/dev/null)
    
    if [ -z "$SECRET_NAME" ] || [ "$SECRET_NAME" = "None" ]; then
        SECRET_NAME="dev-box-credentials"  # fallback to default
    fi
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

log_apply() {
    echo -e "${BLUE}[APPLY]${NC} $1"
}

log_info "Retrieving password from Secrets Manager..."

# Try to get the secret value
SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region $REGION --query 'SecretString' --output text 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$SECRET_VALUE" ]; then
    # Parse JSON without jq (simple extraction)
    PASSWORD=$(echo "$SECRET_VALUE" | sed -n 's/.*"password":"\([^"]*\)".*/\1/p')
    USERNAME=$(echo "$SECRET_VALUE" | sed -n 's/.*"username":"\([^"]*\)".*/\1/p')
    
    if [ -n "$PASSWORD" ] && [ "$PASSWORD" != "null" ]; then
        echo ""
        echo "=========================================="
        echo "Dev Box Credentials"
        echo "=========================================="
        echo "Username: ${USERNAME:-user}"
        echo "Password: $PASSWORD"
        echo "=========================================="
        echo ""
        log_success "Credentials retrieved successfully!"
        
        # Apply password if requested
        if [ "$APPLY_PASSWORD" = true ]; then
            echo ""
            log_apply "Applying password to Windows dev box..."
            
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
            
            log_info "Instance is running. Applying password via Systems Manager..."
            
            # PowerShell command to apply the password (pass credentials directly)
            POWERSHELL_COMMAND="
            try {
                # Use the credentials passed from the script
                \$username = '$USERNAME'
                \$password = '$PASSWORD'
                
                # Use net user command to update password
                \$result = net user \$username \$password
                if (\$LASTEXITCODE -eq 0) {
                    Write-Host 'Password updated successfully for user:' \$username
                } else {
                    Write-Host 'Failed to update password. Result:' \$result
                    exit 1
                }
            } catch {
                Write-Host 'Error updating password:' \$_.Exception.Message
                Write-Host 'Full error details:' \$_.Exception
                exit 1
            }
            "
            
            # Execute the command via Systems Manager
            COMMAND_OUTPUT=$(aws ssm send-command \
                --instance-ids "$INSTANCE_ID" \
                --document-name "AWS-RunPowerShellScript" \
                --parameters "commands=[\"$POWERSHELL_COMMAND\"]" \
                --region "$REGION" \
                --output json 2>/dev/null)
            
            if [ $? -eq 0 ]; then
                COMMAND_ID=$(echo "$COMMAND_OUTPUT" | grep -o '"CommandId": "[^"]*"' | cut -d'"' -f4)
                log_success "Password update command sent successfully!"
                echo ""
                echo "Command ID: $COMMAND_ID"
                echo ""
                echo "To check the command status:"
                echo "aws ssm list-command-invocations --instance-id $INSTANCE_ID --region $REGION"
                echo ""
                echo "To get command output:"
                echo "aws ssm get-command-invocation --instance-id $INSTANCE_ID --command-id $COMMAND_ID --region $REGION"
            else
                log_error "Failed to send command to instance"
                echo "Please ensure:"
                echo "1. Systems Manager agent is installed and running on the instance"
                echo "2. The instance has proper IAM permissions for Systems Manager"
                echo "3. The instance is accessible via Systems Manager"
            fi
        fi
    else
        log_error "Could not parse password from secret"
        echo "Raw secret value: $SECRET_VALUE"
    fi
else
    log_error "Could not retrieve secret '$SECRET_NAME'"
    echo ""
    echo "Please ensure:"
    echo "1. The CloudFormation stack has been deployed"
    echo "2. AWS CLI is configured with proper permissions"
    echo "3. The secret exists in region: $REGION"
    echo ""
    echo "You can check if the secret exists with:"
    echo "aws secretsmanager describe-secret --secret-id $SECRET_NAME --region $REGION"
fi