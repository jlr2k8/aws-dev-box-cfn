# AWS Dev Box CloudFormation Templates

This repository contains a **multi-stack CloudFormation architecture** for automatically provisioning Windows-based development boxes with remote access capabilities.

## Architecture

The solution uses **three separate CloudFormation stacks** for better separation of concerns:

### Core Infrastructure (`dev-box-core`)
- **VPC** with public subnet and internet gateway
- **EC2 Instance** running Windows Server 2025 with native RDP
- **Route 53 DNS** support for custom domain names
- **Security Groups** configured for RDP access
- **IAM Roles** for EC2 instance access

### Backup Configuration (`dev-box-backup`)
- **AWS Backup Vault** for data protection
- **Backup Plans** with automated scheduling
- **Backup Selections** targeting the dev box
- **IAM Roles** for backup service access

### Shared Resources (`dev-box-shared`) - Optional
- **Route 53 Hosted Zone** management (only if creating new hosted zone)
- **Common IAM Policies** for cross-stack access
- **Note:** This stack is commented out in the deploy script by default

## Quick Start

### 1. Prerequisites

- AWS CLI installed and configured
- AWS account with appropriate permissions
- EC2 Key Pair for SSH access
- AWS Secrets Manager secret with dev user credentials
- Route 53 hosted zone (optional, for domain support)

### 2. Clone and Setup

```bash
git clone https://github.com/jlr2k8/aws-dev-box-cfn
cd aws-dev-box-cfn
```

### 3. Create Secrets Manager Secret

```bash
aws secretsmanager create-secret \
  --name "dev-box-credentials" \
  --description "Dev box user credentials" \
  --secret-string '{"username":"your-username","password":"your-secure-password"}'
```

### 4. Configure Parameters

Edit the parameter files with your values:

**`parameters-core.json`:**
```json
[
  {
    "ParameterKey": "Environment",
    "ParameterValue": "dev"
  },
  {
    "ParameterKey": "InstanceType", 
    "ParameterValue": "t3.large"
  },
  {
    "ParameterKey": "KeyPairName",
    "ParameterValue": "your-key-pair-name"
  },
  {
    "ParameterKey": "SecretsManagerSecretName",
    "ParameterValue": "dev-box-credentials"
  },
  {
    "ParameterKey": "DomainName",
    "ParameterValue": "dev.yourdomain.com"
  },
  {
    "ParameterKey": "HostedZoneId",
    "ParameterValue": "YOUR_HOSTED_ZONE_ID"
  }
]
```

### 5. Deploy

**Option A: Multi-Stack Deployment (Recommended)**
```bash
# Deploy core infrastructure and backup (shared stack is optional)
./scripts/deployment/deploy-multi.sh dev-box

# Deploy with custom prefix
./scripts/deployment/deploy-multi.sh my-dev-box
```

**Option B: Single Stack Deployment**
```bash
# Deploy just the core infrastructure
./scripts/deployment/deploy.sh dev-box-core infrastructure/core/dev-box-core.yaml infrastructure/core/parameters-core.json
```

## File Structure

```
aws-dev-box-cfn/
├── README.md                    # This file
├── LICENSE                      # License file
├── .gitignore                  # Git ignore file
│
├── infrastructure/              # CloudFormation templates
│   ├── core/
│   │   ├── dev-box-core.yaml
│   │   └── parameters-core.json
│   ├── backup/
│   │   ├── dev-box-backup.yaml
│   │   └── parameters-backup.json
│   └── shared/
│       ├── dev-box-shared.yaml
│       └── parameters-shared.json
│
├── scripts/                     # All executable scripts
│   ├── deployment/
│   │   ├── deploy-multi.sh
│   │   ├── deploy.sh
│   │   └── teardown.sh
│   ├── management/
│   │   ├── get-password.sh
│   │   └── health-check.sh
│   └── recovery/
│       ├── create-golden-ami.sh
│       └── emergency-recovery.sh
│
├── docs/                        # Documentation
│   ├── deployment.md
│   ├── troubleshooting.md
│   └── disaster-recovery.md
│
└── examples/                    # Example configurations
    ├── parameters/
    │   ├── dev.json
    │   ├── staging.json
    │   └── prod.json
    └── scripts/
        └── custom-deployment.sh
```

## Connecting to Your Dev Box

### 1. Get Credentials

```bash
# Just retrieve and display credentials
./scripts/management/get-password.sh dev-box-core

# Retrieve credentials AND apply them to the Windows box
./scripts/management/get-password.sh dev-box-core --apply
```

### 2. Connect via Remote Desktop

**From Windows:**
1. Open **Remote Desktop Connection** (mstsc.exe)
2. **Computer:** `dev.yourdomain.com` (or the IP address from stack outputs)
3. **Username:** `your-username`
4. **Password:** (from get-password.sh output)

**From Mac:**
1. Download **Microsoft Remote Desktop** from App Store
2. **PC name:** `dev.yourdomain.com`
3. **Username:** `your-username`
4. **Password:** (from get-password.sh output)

**From Linux:**
```bash
xfreerdp /v:dev.yourdomain.com /u:your-username /p:$(./scripts/management/get-password.sh dev-box-core | grep Password | cut -d' ' -f2)
```

## Cost Optimization

### Reserved Instances

Save ~33% on monthly costs with a 3-year Reserved Instance:

```bash
# Check available Reserved Instance offerings
aws ec2 describe-reserved-instances-offerings \
  --instance-type t3.large \
  --product-description "Windows" \
  --offering-type "No Upfront" \
  --max-duration 94608000

# Purchase 3-year No Upfront Reserved Instance
aws ec2 purchase-reserved-instances-offering \
  --reserved-instances-offering-id <offering-id> \
  --instance-count 1
```

**Monthly costs:**
- **On-Demand:** ~$70/month
- **3-Year Reserved:** ~$46/month (33% savings)

### Instance Types

| Type | vCPUs | Memory | Use Case | Monthly Cost |
|------|-------|--------|----------|--------------|
| t3.small | 2 | 2 GB | Light development | ~$15 |
| t3.medium | 2 | 4 GB | Standard development | ~$30 |
| t3.large | 2 | 8 GB | Heavy development | ~$60 |
| t3.xlarge | 4 | 16 GB | Multi-user development | ~$120 |

## Configuration Options

### Core Stack Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| Environment | Environment name | dev | No |
| InstanceType | EC2 instance type | t3.large | No |
| KeyPairName | EC2 Key Pair name | - | Yes |
| SecretsManagerSecretName | Secret name for credentials | dev-box-credentials | No |
| DomainName | Custom domain name | dev.yourdomain.com | No |
| HostedZoneId | Route 53 hosted zone ID | YOUR_HOSTED_ZONE_ID | No |

### Backup Stack Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| Environment | Environment name | dev | No |
| CoreStackName | Name of the core stack | dev-box-core | No |
| BackupRetentionDays | Days to retain backups | 30 | No |

## Pre-installed Software

- **Windows Server 2025** with native RDP
- **Docker Desktop** for containerization
- **VS Code** for development
- **Node.js** and npm
- **Python** with pip
- **Git** for version control
- **Notepad++** for advanced text editing
- **Chocolatey** package manager

## Security Features

- **Elastic IP** for static IP address
- **Security Groups** with configurable access rules
- **IAM Roles** with least privilege access
- **Route 53 DNS** for secure domain access
- **AWS Backup** for data protection
- **Secrets Manager** for credential management

## Bulletproofing Features

### Resource Protection
- **DeletionPolicy: Retain** on all critical resources (EC2, VPC, networking)
- **UpdateReplacePolicy: Retain** prevents accidental replacement
- **Immutable infrastructure** patterns for maximum reliability

### Disaster Recovery
- **Golden AMI Strategy**: Weekly AMI creation for instant recovery
- **Multi-tier Backup**: AWS Backup + EBS snapshots + AMI images
- **Emergency Recovery**: Automated restore procedures
- **Health Monitoring**: Comprehensive system health checks

### Monitoring & Alerting
- **Real-time Health Checks**: Instance, system, and network status
- **Backup Verification**: Automated backup status monitoring
- **RDP Connectivity**: Port accessibility verification
- **Cost Optimization**: Usage tracking and optimization

### Emergency Procedures
```bash
# Health check
./scripts/management/health-check.sh dev-box-core

# Create golden AMI
./scripts/recovery/create-golden-ami.sh dev-box-core

# Emergency recovery
./scripts/recovery/emergency-recovery.sh dev-box-core

# Force recovery (if needed)
./scripts/recovery/emergency-recovery.sh dev-box-core --force
```

## Enhanced Password Management

The `get-password.sh` script now supports remote password application via the `--apply` flag:

### Basic Usage
```bash
# Just retrieve and display credentials (auto-detects secret from stack)
./scripts/management/get-password.sh dev-box-core

# Retrieve credentials AND apply them to the Windows box
./scripts/management/get-password.sh dev-box-core --apply

# With custom secret name (overrides auto-detection)
./scripts/management/get-password.sh dev-box-core my-custom-secret --apply
```

### How It Works
- **Auto-detects secret name** from CloudFormation stack parameters (SecretsManagerSecretName)
- **Retrieves credentials** from AWS Secrets Manager
- **Finds the Windows instance** from your CloudFormation stack
- **Validates instance status** (ensures it's running)
- **Executes PowerShell remotely** via AWS Systems Manager
- **Updates the Windows user password** using the `net user` command
- **Provides command tracking** with Command ID for status checking

### Command Status Checking
```bash
# Check command status
aws ssm list-command-invocations --instance-id i-1234567890abcdef0 --region us-west-2

# Get detailed command output
aws ssm get-command-invocation --instance-id i-1234567890abcdef0 --command-id <COMMAND_ID> --region us-west-2
```

## Password Management

To update the dev box password:

1. **Update the password in AWS Secrets Manager:**
```bash
aws secretsmanager update-secret \
  --secret-id dev-box-credentials \
  --secret-string '{"username":"your-username","password":"YourNewPassword123!"}' \
  --region us-west-2
```

2. **Apply the password to your Windows dev box (Recommended):**
```bash
# Simple one-command approach - retrieves and applies password
./scripts/management/get-password.sh dev-box-core --apply
```

3. **Alternative: Manual sync (if needed):**
```bash
# Get your instance ID first
aws ec2 describe-instances --region us-west-2 --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0]]' --output table

# Sync the password (replace INSTANCE_ID with your actual instance ID)
aws ssm send-command \
  --instance-ids INSTANCE_ID \
  --document-name "AWS-RunPowerShellScript" \
  --parameters 'commands=["$secret = (Get-SECSecretValue -SecretId dev-box-credentials -Region us-west-2).SecretString; $creds = $secret | ConvertFrom-Json; net user your-username $creds.password"]' \
  --region us-west-2
```

## Cleanup

### Using the Teardown Script

```bash
# Clean up core stack
./scripts/deployment/teardown.sh dev-box-core

# Clean up backup stack
./scripts/deployment/teardown.sh dev-box-backup

# Clean up shared stack
./scripts/deployment/teardown.sh dev-box-shared
```

### Manual Cleanup

```bash
# Delete stacks in reverse order
aws cloudformation delete-stack --stack-name dev-box-backup
aws cloudformation delete-stack --stack-name dev-box-core
aws cloudformation delete-stack --stack-name dev-box-shared
```