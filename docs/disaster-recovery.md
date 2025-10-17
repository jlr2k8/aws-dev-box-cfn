# Disaster Recovery Guide

## Emergency Procedures

### Health Check
```bash
# Check system health
./scripts/management/health-check.sh dev-box-core
```

### Create Golden AMI
```bash
# Create recovery point
./scripts/recovery/create-golden-ami.sh dev-box-core
```

### Emergency Recovery
```bash
# Restore from backup
./scripts/recovery/emergency-recovery.sh dev-box-core

# Force recovery (if needed)
./scripts/recovery/emergency-recovery.sh dev-box-core --force
```

## Backup Strategy

### Automated Backups
- **AWS Backup**: Daily at 7 PM PDT (2 AM UTC)
- **Retention**: 30 days
- **Vault**: `dev-dev-box-vault`

### Manual Backups
```bash
# Create golden AMI
./scripts/recovery/create-golden-ami.sh dev-box-core

# List available backups
aws backup list-recovery-points --backup-vault-name dev-dev-box-vault
```

## Recovery Procedures

### Instance Recovery
1. **Health Check**: Verify current status
2. **Backup Selection**: Choose recovery point
3. **Restore Process**: Automated restore job
4. **Verification**: Test connectivity and functionality

### Data Recovery
1. **EBS Snapshots**: Volume-level recovery
2. **AMI Images**: Full instance recovery
3. **Cross-Region**: Multi-region backup (if configured)

## Prevention

### Regular Maintenance
- **Weekly AMI Creation**: Automated golden image
- **Health Monitoring**: Continuous status checks
- **Backup Verification**: Regular backup testing

### Monitoring
- **CloudWatch Alarms**: Automated alerting
- **Health Checks**: Regular system verification
- **Cost Monitoring**: Usage and cost tracking

## Emergency Contacts

### AWS Support
- **Business Support**: For production issues
- **Technical Support**: For technical problems
- **Account Support**: For billing and account issues

### Internal Procedures
1. **Alert Team**: Notify relevant stakeholders
2. **Documentation**: Record all actions taken
3. **Post-Mortem**: Analyze and improve procedures