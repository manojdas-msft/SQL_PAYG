# Arc SQL Orphaned Instance Cleanup Script

## Overview
This script identifies and optionally removes **orphaned Azure Arc SQL Server instances** - SQL instances where the underlying Arc machine has been deleted but the SQL instance resource remains.

## 🔍 What Are Orphaned Instances?

Orphaned instances occur when:
1. An Arc-enabled machine is deleted or decommissioned
2. The machine is manually removed from Azure Arc
3. The Arc agent expires or is uninstalled
4. **But** the SQL Server Instance resource is not automatically cleaned up

**Symptoms:**
- SQL instance shows as "Connected" in Azure Portal
- **Arc Machine Name shows as "N/A"**
- Cannot manage or update the SQL instance
- Instance cannot be converted to PAYG (no underlying machine)

---

## 📋 Prerequisites

### Required PowerShell Modules
```powershell
Install-Module -Name Az.Accounts -Force
Install-Module -Name Az.Resources -Force
Install-Module -Name Az.ConnectedMachine -Force
```

### Required Permissions
- **Reader** role (for report-only mode)
- **Contributor** or **Owner** role (for deletion)

---

## 🧪 Phase 1: Identify Orphans (Report Only)

**Always start with report-only mode to identify orphaned instances:**

### Scan Entire Subscription
```powershell
.\Remove-OrphanedArcSql.ps1 `
    -SubscriptionId "3f9c1e2b-6a4d-41c8-9bf2-8c2e5c9a7f14" `
    -OutputPath "C:\Scripts"
```

**What this does:**
- ✅ Scans all Arc SQL Server instances in the subscription
- ✅ Checks if the underlying Arc machine exists
- ✅ Identifies orphaned instances (machine deleted/N/A)
- ✅ Generates a detailed CSV report
- ❌ Does NOT delete anything

### Scan Specific Resource Group
```powershell
.\Remove-OrphanedArcSql.ps1 `
    -SubscriptionId "3f9c1e2b-6a4d-41c8-9bf2-8c2e5c9a7f14" `
    -ResourceGroup "rgInova-poc" `
    -OutputPath "C:\Scripts"
```

### With Verbose Output
```powershell
.\Remove-OrphanedArcSql.ps1 `
    -SubscriptionId "3f9c1e2b-6a4d-41c8-9bf2-8c2e5c9a7f14" `
    -OutputPath "C:\Scripts" `
    -Verbose
```

---

## 📊 Understanding the Report

### Output File
**Filename:** `ArcSQL_OrphanReport_YYYYMMDD_HHMMSS.csv`

### Report Columns

| Column | Description |
|--------|-------------|
| `InstanceName` | SQL Server instance name |
| `ResourceGroup` | Azure resource group |
| `Location` | Azure region |
| `ResourceId` | Full Azure resource ID |
| `ContainerResourceId` | Arc machine resource ID |
| `MachineName` | Arc machine name (or "N/A") |
| `MachineExists` | Yes/No - Does Arc machine exist? |
| `Status` | Instance status (see below) |
| `Action` | Recommended action |
| `ErrorMessage` | Error details (if any) |
| `DateTime` | Scan timestamp |

### Status Values

| Status | Meaning | Action |
|--------|---------|--------|
| **Valid** | Arc machine exists and is healthy | No action needed |
| **Orphaned - No Container** | No Arc machine reference at all | Delete candidate |
| **Orphaned - Machine Not Found** | Arc machine reference exists but machine is gone | Delete candidate |
| **Orphaned - Machine Deleted** | Arc machine was explicitly deleted | Delete candidate |
| **Error Checking** | Could not verify (permissions, API error) | Manual review |

### Example Report Output

```csv
InstanceName,ResourceGroup,Location,MachineName,MachineExists,Status,Action
WSQL2022_MSSQLSERVER2017,rgInova-poc,eastus,WSQL2022,Yes,Valid,No Action
WSQL_OLD_SERVER,rgInova-poc,eastus,N/A,No,Orphaned - No Container,Identified
WSQL_DECOM_2023,rgInova-poc,westus,OLD-MACHINE,No,Orphaned - Machine Deleted,Identified
```

---

## 🗑️ Phase 2: Delete Orphans (WhatIf Test)

**After reviewing the report, test deletion with WhatIf:**

```powershell
.\Remove-OrphanedArcSql.ps1 `
    -SubscriptionId "3f9c1e2b-6a4d-41c8-9bf2-8c2e5c9a7f14" `
    -OutputPath "C:\Scripts" `
    -DeleteOrphans `
    -WhatIf
```

**What this does:**
- ✅ Identifies orphaned instances
- ✅ Shows what WOULD be deleted
- ❌ Does NOT actually delete anything

### Example WhatIf Output
```
========================================
Arc SQL Orphaned Instance Cleanup
========================================

Checking: WSQL2022_MSSQLSERVER2017
  -> VALID: Arc machine exists (Connected)

Checking: WSQL_OLD_SERVER
  -> ORPHAN: No container resource ID
  [WHATIF] Would delete this instance

Checking: WSQL_DECOM_2023
  -> ORPHAN: Arc machine does not exist
  [WHATIF] Would delete this instance

========================================
SUMMARY
========================================
Total SQL Instances: 3
Valid Instances:     1
Orphaned Instances:  2
```

---

## 🚨 Phase 3: Delete Orphans (Production)

**After confirming with WhatIf, proceed with actual deletion:**

### Delete All Orphans in Subscription
```powershell
.\Remove-OrphanedArcSql.ps1 `
    -SubscriptionId "3f9c1e2b-6a4d-41c8-9bf2-8c2e5c9a7f14" `
    -OutputPath "C:\Scripts" `
    -DeleteOrphans `
    -Verbose
```

### Delete Orphans in Specific Resource Group
```powershell
.\Remove-OrphanedArcSql.ps1 `
    -SubscriptionId "3f9c1e2b-6a4d-41c8-9bf2-8c2e5c9a7f14" `
    -ResourceGroup "rgInova-poc" `
    -OutputPath "C:\Scripts" `
    -DeleteOrphans `
    -Verbose
```

### Example Deletion Output
```
========================================
DELETING ORPHANED INSTANCES
========================================

Found 2 orphaned instances to delete

Deleting: WSQL_OLD_SERVER
  Deleted successfully

Deleting: WSQL_DECOM_2023
  Deleted successfully

Deletion Summary:
  Successfully Deleted: 2
  Failed to Delete: 0

Deletion report saved: C:\Scripts\ArcSQL_OrphanDeletion_20260111_153045.csv
```

---

## 🔧 Parameters Reference

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-SubscriptionId` | Yes | - | Azure subscription ID to scan |
| `-ResourceGroup` | No | All | Limit to specific resource group |
| `-OutputPath` | Yes | - | Directory for output CSV files |
| `-DeleteOrphans` | No | False | Actually delete orphans (otherwise report only) |
| `-WhatIf` | No | False | Preview deletions without executing |
| `-Verbose` | No | False | Detailed logging output |

---

## 📝 Usage Workflow

### Recommended Process

#### Step 1: Initial Scan (Report Only)
```powershell
# Generate report without deleting anything
.\Remove-OrphanedArcSql.ps1 `
    -SubscriptionId "YOUR-SUB-ID" `
    -OutputPath "C:\Scripts" `
    -Verbose
```

**Review:**
1. Open the generated CSV report
2. Verify orphaned instances in Azure Portal
3. Confirm these should be deleted

#### Step 2: Test Deletion (WhatIf)
```powershell
# Preview what would be deleted
.\Remove-OrphanedArcSql.ps1 `
    -SubscriptionId "YOUR-SUB-ID" `
    -OutputPath "C:\Scripts" `
    -DeleteOrphans `
    -WhatIf `
    -Verbose
```

**Verify:**
- Check the list of instances that would be deleted
- Ensure no valid instances are marked for deletion

#### Step 3: Execute Deletion
```powershell
# Actually delete orphaned instances
.\Remove-OrphanedArcSql.ps1 `
    -SubscriptionId "YOUR-SUB-ID" `
    -OutputPath "C:\Scripts" `
    -DeleteOrphans `
    -Verbose
```

**Confirm:**
- Review deletion report CSV
- Verify instances are removed in Azure Portal

---

## ✅ Verification

### Verify in Azure Portal
1. Go to **Azure Portal** → **Azure Arc**
2. Navigate to **SQL Server instances**
3. Check that orphaned instances (Machine Name = "N/A") are gone
4. Confirm valid instances remain

### Verify with PowerShell
```powershell
# List all remaining SQL instances
Get-AzResource -ResourceType "Microsoft.AzureArcData/sqlServerInstances" | 
    Select-Object Name, ResourceGroupName, Location |
    Format-Table -AutoSize

# Check specific instance
Get-AzResource -ResourceType "Microsoft.AzureArcData/sqlServerInstances" -Name "INSTANCE-NAME"
```

---

## 🎯 Common Scenarios

### Scenario 1: Cleanup Before License Conversion
**Problem:** You want to convert servers to PAYG, but some show "N/A" for machine name

**Solution:**
```powershell
# Step 1: Clean up orphans first
.\Remove-OrphanedArcSql.ps1 -SubscriptionId "SUB-ID" -OutputPath "C:\Scripts" -DeleteOrphans

# Step 2: Run license conversion on remaining valid instances
.\Set-ArcSql-PAYG-Final.ps1 -CsvPath "valid_servers.csv" ...
```

### Scenario 2: Post-Decommission Cleanup
**Problem:** Decommissioned servers in January 2025, but SQL instances remain

**Solution:**
```powershell
# Identify and remove orphans from specific resource group
.\Remove-OrphanedArcSql.ps1 `
    -SubscriptionId "SUB-ID" `
    -ResourceGroup "rgInova-decom" `
    -OutputPath "C:\Scripts" `
    -DeleteOrphans
```

### Scenario 3: Monthly Cleanup Job
**Problem:** Need regular cleanup of orphaned instances

**Solution:** Schedule monthly cleanup
```powershell
# Create scheduled task or runbook
# Run in report mode to identify, then review before deletion

# Monthly report
.\Remove-OrphanedArcSql.ps1 -SubscriptionId "SUB-ID" -OutputPath "C:\Reports\Monthly"

# Review report, then delete
.\Remove-OrphanedArcSql.ps1 -SubscriptionId "SUB-ID" -OutputPath "C:\Reports\Monthly" -DeleteOrphans
```

---

## 🚨 Safety Features

### Built-in Protections
1. ✅ **Report-only default** - Must explicitly use `-DeleteOrphans`
2. ✅ **WhatIf support** - Test before executing
3. ✅ **Validation checks** - Verifies machine existence before marking as orphan
4. ✅ **Detailed logging** - All actions logged with timestamps
5. ✅ **Error handling** - Marks errors for manual review instead of deleting
6. ✅ **CSV audit trail** - Complete record of all actions

### What Won't Be Deleted
- ✅ Instances where Arc machine exists and is connected
- ✅ Instances with errors during verification (marked for manual review)
- ✅ Instances in resource groups not specified (if `-ResourceGroup` used)

---

## ⚠️ Important Notes

### Before Running
1. **Backup first** - Export current state:
   ```powershell
   Get-AzResource -ResourceType "Microsoft.AzureArcData/sqlServerInstances" | 
       Export-Csv "C:\Backup\AllSqlInstances_Before_$(Get-Date -Format 'yyyyMMdd').csv"
   ```

2. **Review orphans manually** in Azure Portal before deletion

3. **Test with WhatIf** before actual deletion

4. **Run during maintenance window** if deleting many instances

### After Running
1. Keep the deletion report CSV for audit purposes
2. Verify in Azure Portal that only orphans were removed
3. Check Azure billing to ensure orphaned instances stop incurring costs

---

## 🔍 Troubleshooting

### Issue: "Permission denied"
**Error:** Authorization failed

**Solution:**
```powershell
# For report-only: Need Reader role
# For deletion: Need Contributor or Owner role

# Check your role
Get-AzRoleAssignment | Where-Object { $_.SignInName -eq "your@email.com" }
```

### Issue: Some instances marked as "Error Checking"
**Cause:** API errors, permission issues, or transient failures

**Solution:**
- These are NOT deleted automatically
- Review the ErrorMessage column in the report
- Manually investigate these instances in Azure Portal

### Issue: Valid instances marked as orphans
**This should not happen!** The script verifies machine existence.

**If this occurs:**
1. Do NOT run with `-DeleteOrphans`
2. Review the report CSV carefully
3. Check the ContainerResourceId column
4. Manually verify the Arc machine exists

---

## 📊 Example Reports

### Report 1: Clean Environment
```
Total SQL Instances: 10
Valid Instances:     10
Orphaned Instances:  0

All instances are healthy. No cleanup needed.
```

### Report 2: Some Orphans Found
```
Total SQL Instances: 15
Valid Instances:     12
Orphaned Instances:  3

Orphaned Instances:
InstanceName              ResourceGroup    MachineName  Status
------------              -------------    -----------  ------
SQL2019_OLD_DECOM        rgInova-old      N/A          Orphaned - No Container
SQL2022_TEST_EXPIRED     rgInova-test     TEST-SRV-01  Orphaned - Machine Deleted
SQL2017_MIGRATION        rgInova-mig      MIG-HOST-05  Orphaned - Machine Not Found

NEXT STEPS:
1. Review the report CSV file
2. Verify orphaned instances in Azure Portal
3. Run with -DeleteOrphans -WhatIf to preview deletion
```

---

## 💡 Best Practices

### Cleanup Workflow
1. ✅ Run report mode first
2. ✅ Review CSV report thoroughly
3. ✅ Verify orphans in Azure Portal
4. ✅ Test with `-WhatIf`
5. ✅ Run deletion during maintenance window
6. ✅ Keep CSV reports for audit

### Regular Maintenance
- Run monthly report to identify orphans early
- Clean up orphans before license conversions
- Include in decommissioning procedures

### Integration with License Conversion
```powershell
# 1. Generate health check
.\ArchHealthCheckDiscover.ps1

# 2. Clean up orphans
.\Remove-OrphanedArcSql.ps1 -SubscriptionId "SUB-ID" -OutputPath "C:\Scripts" -DeleteOrphans

# 3. Generate fresh health check (orphans now removed)
.\ArchHealthCheckDiscover.ps1

# 4. Run license conversion on valid instances
.\Set-ArcSql-PAYG-Final.ps1 -CsvPath "ArcSQLHealthCheck_LATEST.csv" ...
```

---

## 📞 Quick Reference

### Report Only Commands
```powershell
# Full subscription
.\Remove-OrphanedArcSql.ps1 -SubscriptionId "SUB-ID" -OutputPath "C:\Scripts"

# Specific resource group
.\Remove-OrphanedArcSql.ps1 -SubscriptionId "SUB-ID" -ResourceGroup "RG-NAME" -OutputPath "C:\Scripts"

# With verbose
.\Remove-OrphanedArcSql.ps1 -SubscriptionId "SUB-ID" -OutputPath "C:\Scripts" -Verbose
```

### Deletion Commands
```powershell
# Test deletion (WhatIf)
.\Remove-OrphanedArcSql.ps1 -SubscriptionId "SUB-ID" -OutputPath "C:\Scripts" -DeleteOrphans -WhatIf

# Actual deletion
.\Remove-OrphanedArcSql.ps1 -SubscriptionId "SUB-ID" -OutputPath "C:\Scripts" -DeleteOrphans -Verbose
```

### Verification Commands
```powershell
# List all SQL instances
Get-AzResource -ResourceType "Microsoft.AzureArcData/sqlServerInstances" | Select Name, ResourceGroupName

# Check for orphans manually
Get-AzResource -ResourceType "Microsoft.AzureArcData/sqlServerInstances" | ForEach-Object {
    $sql = Get-AzResource -ResourceId $_.ResourceId
    if ([string]::IsNullOrWhiteSpace($sql.Properties.containerResourceId)) {
        Write-Host "$($_.Name) - ORPHAN (no container)" -ForegroundColor Red
    }
}
```

---

**Version:** 1.0  
**Last Updated:** January 2026  
**Status:** Production Ready ✅  
**Recommended Use:** Run BEFORE license conversion scripts to ensure clean inventory
