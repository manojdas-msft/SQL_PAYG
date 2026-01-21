# Production Deployment Guide
## Arc SQL Server License Conversion Script

---

## Pre-Production Checklist

### 1. Test Environment Setup
- [ ] Test with 5-10 servers first
- [ ] Run with `-WhatIf` flag to preview changes
- [ ] Verify Azure permissions (Contributor or Owner role)
- [ ] Confirm network connectivity to Azure
- [ ] Test output directory write permissions

### 2. Backup Current State
```powershell
# Export current license configuration before making changes
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
Get-AzResource -ResourceType "Microsoft.AzureArcData/sqlServerInstances" | 
    Select-Object Name, ResourceGroupName, @{N="LicenseType";E={$_.Properties.licenseType}} |
    Export-Csv -Path "C:\Backup\ArcSQL_PreConversion_$timestamp.csv" -NoTypeInformation
```

---

## Scaling Considerations for 500+ Servers

### 1. API Rate Limiting
**Issue**: Azure Resource Manager has throttling limits
- **Read operations**: 12,000 requests per hour per subscription
- **Write operations**: 1,200 requests per hour per subscription

**Solution**: The script processes servers sequentially, which naturally paces requests.

**Estimated Runtime**:
- ~30-60 seconds per server (includes API calls, verification, retry logic)
- **500 servers**: 4-8 hours total
- Run during maintenance window or off-peak hours

### 2. Network Stability
**Issue**: Long-running scripts over unstable networks may fail

**Solution**: 
```powershell
# Run in a screen/tmux session or use PowerShell Job
Start-Job -ScriptBlock {
    .\Set-ArcSql-LicenseToPAYG.ps1 `
        -CsvPath "C:\scripts\input.csv" `
        -OutputPath "C:\Scripts" `
        -SubscriptionId "XXXXX" `
        -Verbose
} | Wait-Job | Receive-Job
```

Or use Azure Cloud Shell for stable connectivity.

### 3. Batch Processing
For 500+ servers, consider breaking into batches:

```powershell
# Split CSV into batches of 100 servers each
$allServers = Import-Csv "C:\scripts\all_servers.csv"
$batchSize = 100
$batchNumber = 1

for ($i = 0; $i -lt $allServers.Count; $i += $batchSize) {
    $batch = $allServers[$i..([Math]::Min($i + $batchSize - 1, $allServers.Count - 1))]
    $batchFile = "C:\scripts\batch_$batchNumber.csv"
    $batch | Export-Csv -Path $batchFile -NoTypeInformation
    
    Write-Host "Processing batch $batchNumber ($($batch.Count) servers)..."
    
    .\Set-ArcSql-LicenseToPAYG.ps1 `
        -CsvPath $batchFile `
        -OutputPath "C:\Scripts" `
        -SubscriptionId "XXXXX" `
        -Verbose
    
    Start-Sleep -Seconds 300  # 5-minute pause between batches
    $batchNumber++
}
```

### 4. Token Expiration
**Issue**: Azure authentication tokens expire after 1 hour

**Solution**: Script automatically handles reauthentication, but for extra safety:
```powershell
# Refresh token before long runs
Connect-AzAccount -Force
Set-AzContext -SubscriptionId "XXXXX"

# Then run script
.\Set-ArcSql-LicenseToPAYG.ps1 [parameters]
```

### 5. Memory Management
**Issue**: Storing 500+ results in memory

**Current design**: Results array holds all data in memory
**Memory usage**: ~1-2 MB for 500 servers (negligible)
**No action needed** unless processing 10,000+ servers

---

## Most Common Production Errors & Troubleshooting

### Error 1: Authentication Failures
```
ERROR: Failed to authenticate to Azure
```

**Causes**:
- Expired credentials
- Network connectivity issues
- Multi-factor authentication timeout

**Solutions**:
```powershell
# Re-authenticate
Disconnect-AzAccount
Connect-AzAccount

# Or use Service Principal for automation
$credential = Get-Credential
Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant "TENANT_ID"
```

**Prevention**:
- Use Service Principal for production runs
- Enable persistent authentication: `Update-AzConfig -EnableLoginByWam $true`

---

### Error 2: Resource Not Found
```
ERROR: Arc SQL Server instance 'ServerName' not found in resource group 'RG'
```

**Causes**:
- Server was deleted/moved
- Incorrect CSV data
- Wrong subscription context

**Troubleshooting**:
```powershell
# Verify server exists
Get-AzResource -ResourceType "Microsoft.AzureArcData/sqlServerInstances" -Name "ServerName"

# Check subscription context
Get-AzContext

# Verify resource group
Get-AzResourceGroup -Name "RG"
```

**Prevention**:
- Run health check script before conversion
- Validate CSV data matches current Azure inventory

---

### Error 3: Insufficient Permissions
```
ERROR: AuthorizationFailed: The client does not have authorization to perform action
```

**Causes**:
- Missing RBAC role
- Read-only access
- Conditional access policies

**Solution**:
```powershell
# Check your role assignments
Get-AzRoleAssignment -SignInName "user@domain.com" | 
    Where-Object { $_.Scope -like "*$subscriptionId*" }
```

**Required Permissions**:
- Minimum: `Contributor` role on subscription or resource group
- Or custom role with:
  - `Microsoft.AzureArcData/sqlServerInstances/read`
  - `Microsoft.AzureArcData/sqlServerInstances/write`

---

### Error 4: Throttling / Rate Limiting
```
ERROR: TooManyRequests: The request is being throttled
```

**Causes**:
- Too many API requests in short time
- Other automation running concurrently

**Solution**:
```powershell
# The script will automatically retry with exponential backoff
# If persistent, add manual delays between batches (see Batch Processing above)
```

**Prevention**:
- Process in smaller batches (100 servers per batch)
- Add 5-minute delays between batches
- Schedule during off-peak hours

---

### Error 5: Network Timeout
```
ERROR: The operation has timed out
```

**Causes**:
- Network instability
- Firewall blocking Azure endpoints
- Proxy issues

**Solution**:
```powershell
# Test Azure connectivity
Test-NetConnection -ComputerName management.azure.com -Port 443

# Check proxy settings
$env:HTTPS_PROXY
$env:HTTP_PROXY

# Run from Azure Cloud Shell as alternative
```

---

### Error 6: API Version Mismatch
```
ERROR: Property 'UsePhysicalCoreLicense' does not exist
```

**Causes**:
- Azure API version changed
- Property name varies by region/version

**Solution**:
Update the property name in the script. Check current API schema:
```powershell
$server = Get-AzResource -ResourceType "Microsoft.AzureArcData/sqlServerInstances" -Name "ServerName"
$server.Properties | Get-Member
```

Common property names:
- `UsePhysicalCoreLicense`
- `physicalCoreLicense`
- `enablePhysicalCoreLicense`

---

### Error 7: Concurrent Modification
```
ERROR: The resource was modified by another operation
```

**Causes**:
- Another user/process modifying the same server
- Azure policy enforcement

**Solution**:
- Script will automatically retry
- If persistent, coordinate with team to avoid conflicts

---

### Error 8: Already at PAYG
```
STATUS: Skipped - Already Configured
```

**Causes**:
- Server already converted (not an error)
- Previous run partially completed

**Solution**:
- Review output CSV to see which servers were skipped
- No action needed if intentional

---

## Production Best Practices

### 1. Pre-Run Validation
```powershell
# Validate CSV before running
$csv = Import-Csv "C:\scripts\input.csv"
Write-Host "Total servers: $($csv.Count)"
Write-Host "Unique resource groups: $($csv.ResourceGroup | Select-Object -Unique | Measure-Object).Count"

# Check for duplicates
$duplicates = $csv | Group-Object ServerName | Where-Object { $_.Count -gt 1 }
if ($duplicates) {
    Write-Warning "Duplicate servers found!"
    $duplicates | ForEach-Object { Write-Host "  $($_.Name): $($_.Count) times" }
}
```

### 2. Monitoring Progress
```powershell
# Run with transcript logging
Start-Transcript -Path "C:\Logs\ArcSQL_Conversion_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

.\Set-ArcSql-LicenseToPAYG.ps1 `
    -CsvPath "C:\scripts\input.csv" `
    -OutputPath "C:\Scripts" `
    -SubscriptionId "XXXXX" `
    -Verbose

Stop-Transcript
```

### 3. Post-Run Verification
```powershell
# Import results
$results = Import-Csv "C:\Scripts\ArcSQL_LicenseConversion_TIMESTAMP.csv"

# Check success rate
$total = $results.Count
$success = ($results | Where-Object { $_.Status -eq "Success" }).Count
$failed = ($results | Where-Object { $_.Status -eq "Failed" }).Count
$skipped = ($results | Where-Object { $_.Status -like "*Skipped*" }).Count

Write-Host "Total: $total"
Write-Host "Success: $success ($([math]::Round($success/$total*100,2))%)"
Write-Host "Failed: $failed"
Write-Host "Skipped: $skipped"

# Review failures
$results | Where-Object { $_.Status -eq "Failed" } | 
    Select-Object ServerName, ErrorMessage | 
    Format-Table -AutoSize
```

### 4. Retry Failed Servers
```powershell
# Extract failed servers to new CSV
$results = Import-Csv "C:\Scripts\ArcSQL_LicenseConversion_TIMESTAMP.csv"
$failed = $results | Where-Object { $_.Status -eq "Failed" } | 
    Select-Object ServerName, ResourceGroup, MachineName, CurrentLicenseType

$failed | Export-Csv -Path "C:\Scripts\retry_servers.csv" -NoTypeInformation

# Re-run just the failed servers
.\Set-ArcSql-LicenseToPAYG.ps1 `
    -CsvPath "C:\scripts\retry_servers.csv" `
    -OutputPath "C:\Scripts" `
    -SubscriptionId "XXXXX" `
    -Verbose
```

---

## Performance Optimization Tips

### 1. Use Service Principal for Automation
```powershell
# More reliable than user authentication for long runs
$appId = "APP_ID"
$secret = "SECRET" | ConvertTo-SecureString -AsPlainText -Force
$tenantId = "TENANT_ID"
$credential = New-Object System.Management.Automation.PSCredential($appId, $secret)

Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $tenantId
```

### 2. Parallel Processing (Advanced)
For very large deployments (1000+ servers), consider parallel processing:

```powershell
# Split into 5 batches and run in parallel
$batches = 1..5
$batches | ForEach-Object -Parallel {
    .\Set-ArcSql-LicenseToPAYG.ps1 `
        -CsvPath "C:\scripts\batch_$_.csv" `
        -OutputPath "C:\Scripts\Batch$_" `
        -SubscriptionId "XXXXX"
} -ThrottleLimit 5
```

**Caution**: Monitor Azure throttling limits closely with parallel runs.

---

## Emergency Rollback Plan

If you need to revert changes:

```powershell
# Rollback script - change PAYG back to original license type
$backupCsv = Import-Csv "C:\Backup\ArcSQL_PreConversion_TIMESTAMP.csv"

foreach ($server in $backupCsv) {
    $resource = Get-AzResource -ResourceType "Microsoft.AzureArcData/sqlServerInstances" `
        -Name $server.Name -ResourceGroupName $server.ResourceGroupName
    
    if ($resource) {
        $properties = @{
            licenseType = $server.LicenseType  # Original license type
        }
        
        Set-AzResource -ResourceId $resource.ResourceId -Properties $properties -Force
        Write-Host "Reverted: $($server.Name)"
    }
}
```

---

## Support Contacts & Resources

**Azure Support**:
- Azure Portal → Help + Support
- Priority based on support plan (Basic/Standard/Professional Direct)

**Script Issues**:
1. Review output CSV ErrorMessage column
2. Check transcript logs
3. Run diagnostic scripts (Test-CsvExport.ps1)

**Documentation**:
- Azure Arc SQL: https://learn.microsoft.com/azure/azure-arc/data/
- REST API Reference: https://learn.microsoft.com/rest/api/azurearcdata/

---

## Change Log Template

Keep a log of production runs:

```
Date: 2026-01-10
Operator: John Doe
Total Servers: 500
Success: 485
Failed: 10
Skipped: 5
Duration: 6 hours 23 minutes
Issues: 
  - 10 servers failed due to network timeout (retried successfully next day)
  - 5 servers already configured
Notes: Ran in batches of 100 during maintenance window
```
