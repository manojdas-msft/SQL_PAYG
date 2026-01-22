# Arc SQL Server License Conversion to PAYG

## Overview
This script converts Azure Arc-enabled SQL Server instances from their current licensing model to **Pay-As-You-Go (PAYG)** and optionally enables the **"Use physical core license"** option.

**Based on:** Microsoft reference implementation for Arc SQL license management  
**Version:** Final Working Version  
**Date:** January 2026

---

## 🎯 What This Script Does

1. Reads a CSV file containing your Arc SQL Server inventory
2. Finds the SQL extension on each Connected Machine
3. Updates the extension settings to:
   - Change license type to **PAYG**
   - Enable **Physical Core License** (if specified)
4. Exports detailed results to a timestamped CSV file
5. Provides a summary of successful, failed, and skipped servers

---

## 📋 Prerequisites

### Required PowerShell Modules
```powershell
# Check if modules are installed
Get-Module -ListAvailable Az.Accounts, Az.ConnectedMachine

# Install if needed
Install-Module -Name Az.Accounts -Force
Install-Module -Name Az.ConnectedMachine -Force
```

### Required Azure Permissions
- **Contributor** or **Owner** role on the Azure subscription
- Access to resource groups containing Arc SQL Server instances

### Input CSV File
The script requires a CSV file with these columns:
- `ServerName` - Name of the Arc SQL Server instance
- `ResourceGroup` - Azure resource group name
- `MachineName` - Name of the connected machine
- `Location` - Azure region (e.g., "eastus")
- `CurrentLicenseType` - Current license type (optional, for tracking)

**Example CSV:**
```csv
ServerName,ResourceGroup,Location,MachineName,CurrentLicenseType
WSQL2022_MSSQLSERVER2017,rgInova-poc,eastus,WSQL2022,Paid
WSQL2025_MSSQLSERVER2025,rgInova-poc,eastus,WSQL2025,Paid
```

---

## 🧪 Phase 1: Trial Run (RECOMMENDED FIRST STEP)

**Always test first with `-WhatIf` to preview changes without making them!**

### Basic WhatIf Test
```powershell
C:\scripts\Set-ArcSql-PAYG-Final.ps1 `
    -CsvPath "C:\scripts\ArcSQLHealthCheck_20260110_175248.csv" `
    -OutputPath "C:\Scripts" `
    -SubscriptionId "3f9c1e2b-6a4d-41c8-9bf2-8c2e5c9a7f14" `
    -WhatIf
```

**What this does:**
- ✅ Connects to Azure
- ✅ Reads your CSV file
- ✅ Checks each server's current configuration
- ✅ Shows what WOULD be changed
- ❌ Does NOT make any actual changes
- ✅ Creates a results CSV showing "WhatIf" status

### Detailed WhatIf Test (With Verbose Output)
```powershell
C:\scripts\Set-ArcSql-PAYG-Final.ps1 `
    -CsvPath "C:\scripts\ArcSQLHealthCheck_20260110_175248.csv" `
    -OutputPath "C:\Scripts" `
    -SubscriptionId "3f9c1e2b-6a4d-41c8-9bf2-8c2e5c9a7f14" `
    -EnablePhysicalCoreLicense `
    -WhatIf `
    -Verbose
```

**What `-Verbose` adds:**
- Shows detailed extension information
- Displays current settings before changes
- Shows exactly what settings would be applied
- Helpful for troubleshooting

### Expected WhatIf Output
```
========================================
Arc SQL License Conversion - Final
========================================

Checking authentication...
Connected as: user@domain.com

Loading CSV...
Loaded 2 servers
Physical core license option: ENABLED

Processing servers...

[1/2] WSQL2022_MSSQLSERVER2017 (eastus)
  Extension: WindowsAgent.SqlServer
  Current License: Paid
  Current Physical Core: Not Set
  -> License needs update: Paid -> PAYG
  -> Physical core license needs update
  [WHATIF] Would update extension settings

[2/2] WSQL2025_MSSQLSERVER2025 (eastus)
  Extension: WindowsAgent.SqlServer
  Current License: Paid
  Current Physical Core: Not Set
  -> License needs update: Paid -> PAYG
  -> Physical core license needs update
  [WHATIF] Would update extension settings

========================================
SUMMARY
========================================
Total Servers:  2
Successful:     0
Failed:         0
Skipped:        2

Output File:    C:\Scripts\ArcSQL_Results_20260111_143022.csv
========================================
```

---

## 🚀 Phase 2: Production Run

**After reviewing WhatIf results and confirming everything looks correct:**

### Production Run - PAYG Only
```powershell
C:\scripts\Set-ArcSql-PAYG-Final.ps1 `
    -CsvPath "C:\scripts\ArcSQLHealthCheck_20260110_175248.csv" `
    -OutputPath "C:\Scripts" `
    -SubscriptionId "3f9c1e2b-6a4d-41c8-9bf2-8c2e5c9a7f14"
```

**This will:**
- Convert all servers to PAYG licensing
- NOT enable physical core license

### Production Run - PAYG + Physical Core License (RECOMMENDED)
```powershell
C:\scripts\Set-ArcSql-PAYG-Final.ps1 `
    -CsvPath "C:\scripts\ArcSQLHealthCheck_20260110_175248.csv" `
    -OutputPath "C:\Scripts" `
    -SubscriptionId "3f9c1e2b-6a4d-41c8-9bf2-8c2e5c9a7f14" `
    -EnablePhysicalCoreLicense
```

**This will:**
- Convert all servers to PAYG licensing
- Enable "Use physical core license" option

### Production Run with Verbose Logging
```powershell
C:\scripts\Set-ArcSql-PAYG-Final.ps1 `
    -CsvPath "C:\scripts\ArcSQLHealthCheck_20260110_175248.csv" `
    -OutputPath "C:\Scripts" `
    -SubscriptionId "3f9c1e2b-6a4d-41c8-9bf2-8c2e5c9a7f14" `
    -EnablePhysicalCoreLicense `
    -Verbose
```

**Use `-Verbose` for:**
- First production run
- Troubleshooting issues
- Audit trail requirements

### Expected Production Output
```
========================================
Arc SQL License Conversion - Final
========================================

Checking authentication...
Connected as: user@domain.com

Loading CSV...
Loaded 2 servers
Physical core license option: ENABLED

Processing servers...

[1/2] WSQL2022_MSSQLSERVER2017 (eastus)
  Extension: WindowsAgent.SqlServer
  Current License: Paid
  Current Physical Core: Not Set
  -> License needs update: Paid -> PAYG
  -> Physical core license needs update
  Updating extension...
  Success (update initiated)

[2/2] WSQL2025_MSSQLSERVER2025 (eastus)
  Extension: WindowsAgent.SqlServer
  Current License: Paid
  Current Physical Core: Not Set
  -> License needs update: Paid -> PAYG
  -> Physical core license needs update
  Updating extension...
  Success (update initiated)

Exporting results...
Results exported: C:\Scripts\ArcSQL_Results_20260111_143525.csv

========================================
SUMMARY
========================================
Total Servers:  2
Successful:     2
Failed:         0
Skipped:        0

Output File:    C:\Scripts\ArcSQL_Results_20260111_143525.csv
========================================

ServerName                    Status  PreviousLicense NewLicense PhysicalCore Error
----------                    ------  --------------- ---------- ------------ -----
WSQL2022_MSSQLSERVER2017     Success Paid            PAYG       Enabled
WSQL2025_MSSQLSERVER2025     Success Paid            PAYG       Enabled

Note: Changes may take 1-2 minutes to appear in Azure Portal

To verify physical core license setting:
$ext = Get-AzConnectedMachineExtension -MachineName "WSQL2022" -ResourceGroupName "rgInova-poc" | Where-Object {$_.Publisher -eq "Microsoft.AzureData"}
$ext.Setting["UsePhysicalCoreLicense"]
```

---

## 📊 Output File

The script creates a timestamped CSV file with detailed results:

**Filename format:** `ArcSQL_Results_YYYYMMDD_HHMMSS.csv`

**Columns:**
| Column | Description |
|--------|-------------|
| `ServerName` | SQL Server instance name |
| `ResourceGroup` | Azure resource group |
| `MachineName` | Connected machine name |
| `Location` | Azure region |
| `PreviousLicense` | License type before conversion |
| `NewLicense` | License type after conversion (PAYG) |
| `PhysicalCore` | Physical core license status |
| `Status` | Success, Failed, Skipped, or WhatIf |
| `Error` | Error message if failed |
| `DateTime` | Processing timestamp |

**Example Output CSV:**
```csv
ServerName,ResourceGroup,MachineName,Location,PreviousLicense,NewLicense,PhysicalCore,Status,Error,DateTime
WSQL2022_MSSQLSERVER2017,rgInova-poc,WSQL2022,eastus,Paid,PAYG,Enabled,Success,,2026-01-11 14:35:25
WSQL2025_MSSQLSERVER2025,rgInova-poc,WSQL2025,eastus,Paid,PAYG,Enabled,Success,,2026-01-11 14:35:28
```

---

## ✅ Verification Steps

### 1. Check Azure Portal
1. Navigate to Azure Portal → Arc-enabled servers
2. Select a server → SQL Server instances
3. Look for "Licensing" section
4. Verify:
   - License type shows **Pay-as-you-go**
   - "Use physical core license" checkbox is **checked** (if enabled)

### 2. Verify with PowerShell
```powershell
# Get the extension for a specific server
$ext = Get-AzConnectedMachineExtension `
    -MachineName "WSQL2022" `
    -ResourceGroupName "rgInova-poc" | 
    Where-Object {$_.Publisher -eq "Microsoft.AzureData"}

# Check license type
$ext.Setting["LicenseType"]
# Should show: PAYG

# Check physical core license
$ext.Setting["UsePhysicalCoreLicense"]
# Should show:
# IsApplied            LastUpdatedTimestamp
# ---------            --------------------
# True                 2026-01-11T14:35:25.123Z
```

### 3. Verify All Servers from Output CSV
```powershell
# Import results
$results = Import-Csv "C:\Scripts\ArcSQL_Results_20260111_143525.csv"

# Check success rate
$total = $results.Count
$success = ($results | Where-Object {$_.Status -eq "Success"}).Count
$failed = ($results | Where-Object {$_.Status -eq "Failed"}).Count

Write-Host "Total: $total"
Write-Host "Success: $success"
Write-Host "Failed: $failed"

# Show any failures
$results | Where-Object {$_.Status -eq "Failed"} | 
    Select-Object ServerName, Error | 
    Format-Table -AutoSize
```

---

## 🔧 Parameters Reference

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-CsvPath` | Yes | - | Path to input CSV file |
| `-OutputPath` | Yes | - | Directory for output CSV |
| `-SubscriptionId` | Yes | - | Azure subscription ID |
| `-EnablePhysicalCoreLicense` | No | False | Enables physical core license option |
| `-WhatIf` | No | False | Preview mode - no actual changes |
| `-Verbose` | No | False | Detailed logging output |

---

## 📝 Usage Examples

### Example 1: Test Run Before Production
```powershell
# Step 1: WhatIf to see what would change
.\Set-ArcSql-PAYG-Final.ps1 `
    -CsvPath "C:\scripts\servers.csv" `
    -OutputPath "C:\Scripts" `
    -SubscriptionId "YOUR-SUB-ID" `
    -EnablePhysicalCoreLicense `
    -WhatIf `
    -Verbose

# Step 2: Review output, then run for real
.\Set-ArcSql-PAYG-Final.ps1 `
    -CsvPath "C:\scripts\servers.csv" `
    -OutputPath "C:\Scripts" `
    -SubscriptionId "YOUR-SUB-ID" `
    -EnablePhysicalCoreLicense `
    -Verbose
```

### Example 2: Subset Testing
```powershell
# Test with just 2-3 servers first
# Create a small CSV with 2-3 servers
$allServers = Import-Csv "C:\scripts\all_500_servers.csv"
$testServers = $allServers | Select-Object -First 3
$testServers | Export-Csv "C:\scripts\test_3_servers.csv" -NoTypeInformation

# Run on test subset
.\Set-ArcSql-PAYG-Final.ps1 `
    -CsvPath "C:\scripts\test_3_servers.csv" `
    -OutputPath "C:\Scripts" `
    -SubscriptionId "YOUR-SUB-ID" `
    -EnablePhysicalCoreLicense `
    -Verbose

# Verify results, then proceed with all servers
```

### Example 3: Phased Rollout
```powershell
# Phase 1: Development environment (10 servers)
.\Set-ArcSql-PAYG-Final.ps1 `
    -CsvPath "C:\scripts\dev_servers.csv" `
    -OutputPath "C:\Scripts\Dev" `
    -SubscriptionId "YOUR-SUB-ID" `
    -EnablePhysicalCoreLicense

# Wait 24 hours, verify billing impact

# Phase 2: Test environment (20 servers)
.\Set-ArcSql-PAYG-Final.ps1 `
    -CsvPath "C:\scripts\test_servers.csv" `
    -OutputPath "C:\Scripts\Test" `
    -SubscriptionId "YOUR-SUB-ID" `
    -EnablePhysicalCoreLicense

# Phase 3: Production (470 servers)
.\Set-ArcSql-PAYG-Final.ps1 `
    -CsvPath "C:\scripts\prod_servers.csv" `
    -OutputPath "C:\Scripts\Prod" `
    -SubscriptionId "YOUR-SUB-ID" `
    -EnablePhysicalCoreLicense
```

---

## 🚨 Troubleshooting

### Issue: "Extension not found"
**Error:** `No SQL extension found on machine (or not in Succeeded state)`

**Causes:**
- Extension not installed on the machine
- Extension in failed/updating state

**Solution:**
```powershell
# Check extension status
Get-AzConnectedMachineExtension -MachineName "MACHINE" -ResourceGroupName "RG" | 
    Where-Object {$_.Publisher -eq "Microsoft.AzureData"} |
    Select-Object Name, ProvisioningState, Publisher

# If ProvisioningState is not "Succeeded", extension needs to be fixed first
```

### Issue: "Authentication failed"
**Solution:**
```powershell
# Reconnect
Disconnect-AzAccount
Connect-AzAccount
Set-AzContext -SubscriptionId "YOUR-SUB-ID"
```

### Issue: "Changes not appearing in Portal"
**Solution:**
- Wait 1-2 minutes for Azure to process the async update
- Refresh the Azure Portal page
- Verify with PowerShell (see Verification section)

### Issue: Script shows "Success" but checkbox still unchecked
**Possible causes:**
1. Azure Portal cache - try hard refresh (Ctrl+F5)
2. Extension update still processing - wait 2-3 minutes
3. Verify with PowerShell to confirm setting was applied

**Verification:**
```powershell
$ext = Get-AzConnectedMachineExtension -MachineName "MACHINE" -ResourceGroupName "RG" | 
    Where-Object {$_.Publisher -eq "Microsoft.AzureData"}
$ext.Setting["UsePhysicalCoreLicense"]
```

If PowerShell shows `IsApplied = True` but portal doesn't, it's a portal display issue. The setting IS applied.

---

## 💡 Best Practices

### Before Running in Production

1. ✅ **Test with WhatIf first**
   ```powershell
   -WhatIf -Verbose
   ```

2. ✅ **Test with small subset** (2-3 servers)

3. ✅ **Review output CSV** carefully

4. ✅ **Verify in Azure Portal** after test

5. ✅ **Check billing impact** after 24 hours

6. ✅ **Document baseline** - Export current state:
   ```powershell
   # Save current state before changes
   $timestamp = Get-Date -Format "yyyyMMdd"
   $servers | Export-Csv "C:\Backup\Servers_Before_$timestamp.csv" -NoTypeInformation
   ```

### During Production Run

1. ✅ Use `-Verbose` for audit trail
2. ✅ Save transcript log:
   ```powershell
   Start-Transcript "C:\Logs\ArcSQL_Conversion_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
   # Run script
   Stop-Transcript
   ```
3. ✅ Monitor first few servers before continuing
4. ✅ Keep output CSV files for records

### After Production Run

1. ✅ Verify in Azure Portal (sample of servers)
2. ✅ Check billing dashboard after 24-48 hours
3. ✅ Keep all output CSV files for audit
4. ✅ Document completion date and results

---

## 📈 Scaling to 500+ Servers

The script processes servers sequentially, which is safe but slower for large deployments.

### Estimated Runtime
- **~30-45 seconds per server** (includes API calls)
- **500 servers**: ~4-6 hours total

### Recommendations for Large Deployments

1. **Run during maintenance window**
2. **Use batch processing** - Process in groups of 100:
   ```powershell
   # Create batches
   $all = Import-Csv "all_servers.csv"
   $batch1 = $all[0..99]
   $batch2 = $all[100..199]
   # etc.
   
   # Process each batch
   $batch1 | Export-Csv "batch1.csv" -NoTypeInformation
   .\Set-ArcSql-PAYG-Final.ps1 -CsvPath "batch1.csv" ... -Verbose
   ```

3. **Monitor progress** - Output shows `[X/Total]` counter

4. **Handle failures** - Extract failed servers and retry:
   ```powershell
   $results = Import-Csv "ArcSQL_Results_TIMESTAMP.csv"
   $failed = $results | Where-Object {$_.Status -eq "Failed"}
   $failed | Export-Csv "retry_servers.csv" -NoTypeInformation
   # Then rerun with retry_servers.csv
   ```

---

## 🔒 Security Considerations

- Script requires Azure **Contributor** or **Owner** permissions
- Uses existing Azure PowerShell authentication (no credentials stored)
- All changes are logged in output CSV
- Consider using **Service Principal** for automation:
  ```powershell
  $credential = Get-Credential
  Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant "TENANT-ID"
  ```

---

## 📞 Support & Documentation

### Azure Documentation
- [Azure Arc-enabled SQL Server](https://learn.microsoft.com/azure/azure-arc/data/)
- [SQL Server licensing](https://learn.microsoft.com/sql/sql-server/sql-server-licensing)

### Script Information
- **Based on:** Microsoft reference script for Arc SQL license management
- **Tested with:** Az.Accounts 2.x, Az.ConnectedMachine 0.x
- **PowerShell:** 5.1 and 7.x compatible

### Getting Help
```powershell
# Get detailed help
Get-Help .\Set-ArcSql-PAYG-Final.ps1 -Detailed

# View examples
Get-Help .\Set-ArcSql-PAYG-Final.ps1 -Examples
```

---

## 📋 Quick Reference Card

### Trial Run Commands
```powershell
# Preview only - no changes
.\Set-ArcSql-PAYG-Final.ps1 -CsvPath "FILE.csv" -OutputPath "C:\Scripts" -SubscriptionId "SUB-ID" -WhatIf

# Preview with details
.\Set-ArcSql-PAYG-Final.ps1 -CsvPath "FILE.csv" -OutputPath "C:\Scripts" -SubscriptionId "SUB-ID" -EnablePhysicalCoreLicense -WhatIf -Verbose
```

### Production Run Commands
```powershell
# PAYG only
.\Set-ArcSql-PAYG-Final.ps1 -CsvPath "FILE.csv" -OutputPath "C:\Scripts" -SubscriptionId "SUB-ID"

# PAYG + Physical Core (RECOMMENDED)
.\Set-ArcSql-PAYG-Final.ps1 -CsvPath "FILE.csv" -OutputPath "C:\Scripts" -SubscriptionId "SUB-ID" -EnablePhysicalCoreLicense

# With verbose logging
.\Set-ArcSql-PAYG-Final.ps1 -CsvPath "FILE.csv" -OutputPath "C:\Scripts" -SubscriptionId "SUB-ID" -EnablePhysicalCoreLicense -Verbose
```

### Verification Commands
```powershell
# Verify single server
$ext = Get-AzConnectedMachineExtension -MachineName "MACHINE" -ResourceGroupName "RG" | Where-Object {$_.Publisher -eq "Microsoft.AzureData"}
$ext.Setting["LicenseType"]
$ext.Setting["UsePhysicalCoreLicense"]

# Verify from results CSV
$results = Import-Csv "ArcSQL_Results_TIMESTAMP.csv"
$results | Where-Object {$_.Status -eq "Failed"}
```

---

**Version:** 1.0 - Final Working Version  
**Last Updated:** January 2026  
**Status:** Production Ready ✅
