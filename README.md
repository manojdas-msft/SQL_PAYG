# Azure Arc SQL Server Health Check Script

## Overview

**PostLicensingUpdateReport-v2.ps1** is a comprehensive PowerShell script that performs health checks on all Azure Arc-enabled SQL Server instances within a specified Azure subscription. It validates system connectivity, licensing configurations, extension status, and generates detailed diagnostic reports.

This script is particularly useful for organizations managing multiple SQL Server instances across hybrid environments using Azure Arc for centralized management.

---

## Purpose & Key Features

### What This Script Does

1. **Discovers Arc SQL Servers**: Retrieves all SQL Server instances registered in Azure Arc within your subscription
2. **Validates Arc Machine Connectivity**: Checks if the underlying Azure Arc-connected machine is properly registered and communicating
3. **Verifies Extension Status**: Ensures the SQL extension is installed and in operational state
4. **Audits Licensing**: Reads license configuration from the SQL extension (authoritative source) and validates synchronization
5. **Detects Physical Core Licensing**: Identifies whether physical core licensing is enabled
6. **Identifies Issues**: Detects orphaned servers, extension failures, and sync problems
7. **Generates Reports**: Creates both CSV and text reports with detailed findings
8. **Provides Analytics**: Offers summary statistics by license type, SQL edition, version, and core allocation

### Key Features

- ✅ **Extension-based License Reading**: Uses SQL extension settings as the source of truth for license configuration
- ✅ **Sync Status Detection**: Identifies pending license synchronization between extension and instance properties
- ✅ **Orphaned Server Detection**: Flags servers with missing or deleted Arc machine references
- ✅ **Agent Health Monitoring**: Checks Arc agent version and last heartbeat status
- ✅ **Multi-format Output**: Generates CSV (for Excel analysis) and text reports
- ✅ **Color-coded Console Output**: Easy-to-read status indicators (green = healthy, red = issues)
- ✅ **Comprehensive Metrics**: Provides core count statistics, license distribution, and SQL version inventory

---

## Prerequisites

### Required Components

- **Azure PowerShell Module**: Install with `Install-Module -Name Az -Scope CurrentUser`
- **Specific Az Modules**:
  - `Az.Accounts` - For Azure authentication
  - `Az.Resources` - For resource queries
  - `Az.ConnectedMachine` - For Arc machine data
  - These are typically included in the main `Az` module

- **Azure Credentials**: Must be able to authenticate to Azure with permissions to:
  - Read Azure Arc SQL Server instances
  - Read Azure Arc machines (HybridCompute)
  - Read machine extensions
  - Read resource groups and resource details

- **File System**: Write access to `C:\Scripts` directory (script will create if missing)

### Setup Instructions

```powershell
# Install Azure PowerShell module
Install-Module -Name Az -Scope CurrentUser -AllowClobber

# Verify installation
Get-Module Az.Resources, Az.ConnectedMachine

# For isolated environments, update modules
Update-Module -Name Az
```

---

## Configuration

### Subscription ID

Edit the script and update the subscription ID on this line:

```powershell
$subscriptionId = "77b80376-724a-40fa-8c15-710765be0046"
```

Replace with your target subscription ID.

### Output Path

By default, reports are exported to `C:\Scripts`. To change:

```powershell
$exportPath = "C:\Scripts"  # Change this to your desired path
```

The script automatically creates the directory if it doesn't exist.

---

## Usage

### Basic Execution

```powershell
# Run the script from PowerShell
.\PostLicensingUpdateReport-v2.ps1
```

### Execution with Output Capture

```powershell
# Capture results in a variable for further processing
$results = .\PostLicensingUpdateReport-v2.ps1

# Filter results
$results | Where-Object { $_.HealthStatus -eq "Unhealthy" }

# Export to alternative location
$results | Export-Csv -Path "C:\Reports\custom-report.csv"
```

### Run as Administrator (Recommended)

```powershell
# Right-click PowerShell and select "Run as administrator"
# Then execute the script
```

### Automated Scheduling

To run the script on a schedule via Windows Task Scheduler:

```powershell
# Create scheduled task
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File 'C:\Scripts\PostLicensingUpdateReport-v2.ps1'"
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 6:00AM
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "ArcSQLHealthCheck" -Description "Weekly Azure Arc SQL health check"
```

---

## Output & Reports

### Console Output

The script provides real-time feedback in the console with color-coded status indicators:

```
[1/5] Checking: sql-server-01...
  -> OK: Paid

[2/5] Checking: sql-server-02...
  -> License sync pending

[3/5] Checking: sql-server-03...
  -> Extension issue
```

### Generated Reports

Two report files are created with timestamp in the filename:

#### CSV Report
- **Location**: `C:\Scripts\ArcSQLHealthCheck_YYYYMMDD_HHMMSS.csv`
- **Purpose**: Import into Excel for analysis and filtering
- **Contains**: All health data in tabular format with consistent columns

#### Text Report
- **Location**: `C:\Scripts\ArcSQLHealthCheck_YYYYMMDD_HHMMSS.txt`
- **Purpose**: Log archival and email distribution
- **Contains**: Formatted table with all server details

### Summary Statistics

The script displays comprehensive breakdowns:

#### Status Summary
```
Total Servers:      25
Healthy:            22
Extension Issues:   2
Unhealthy:          0
Orphaned:           1
```

#### License Breakdown
```
License Type Breakdown:
  Paid: 15
  License Included: 8
  HADR: 2
  Extension Not Found/Failed: 1
```

#### Edition Breakdown
```
SQL Edition Breakdown:
  Enterprise: 12
  Standard: 10
  Express: 3
```

#### Core Statistics
```
Cores Summary:
  Total Cores:   256
  Average Cores: 10.2
  Max Cores:     32
  Min Cores:     2
```

---

## Understanding the Health Statuses

### Healthy ✅
- **Condition**: Arc machine is connected AND SQL extension is in "Succeeded" state
- **Action**: No action required. Server is operational.
- **Details**: License types match between extension and instance.

### Extension Issue ⚠️
- **Condition**: Arc machine is connected BUT SQL extension is NOT in "Succeeded" state
- **Possible Causes**:
  - Extension failed to install
  - Extension encountered a configuration error
  - Extension is still provisioning
- **Actions**:
  1. Check extension details in Azure Portal → Arc machine → Extensions
  2. Review extension error messages
  3. May require extension repair or reinstall

### Unhealthy ❌
- **Condition**: Arc machine connection is not "Connected"
- **Possible Causes**:
  - Machine is offline or not communicating with Azure
  - Arc agent is misconfigured
  - Network connectivity issue
  - Machine was deleted but SQL instance still exists
- **Actions**:
  1. Verify Arc agent is running on the machine
  2. Check network connectivity to Azure
  3. Verify Arc machine status in Azure Portal

### Orphaned 🔴
- **Condition**: SQL instance has no Arc machine reference OR Arc machine doesn't exist
- **Possible Causes**:
  - Arc machine was deleted without cleaning up SQL instance
  - Configuration corruption
- **Actions**:
  1. Delete the orphaned SQL Server instance resource
  2. OR re-register the Arc machine if it still exists

---

## License Type Information

### Source of Truth: Extension Settings

This script reads license type from the **SQL extension settings** on the Arc machine, not from the instance properties. This is the authoritative source for billing and compliance.

### Common License Types

| License Type | Description | Use Case |
|---|---|---|
| **Paid** | Pay-as-you-go vCore licensing | Public cloud equivalent |
| **License Included** | Included in Azure Arc subscription | Hybrid benefit scenarios |
| **HADR** | High Availability/Disaster Recovery | Always-On configurations |
| **Extension Not Found** | SQL extension not operational | Configuration issue |

### License Sync Behavior

When you change license type through Azure:

1. **Extension receives update**: Changes pushed to extension
2. **Instance properties updated**: After extension processes change
3. **Sync window**: Typically 5-10 minutes for complete sync
4. **Script detection**: Shows "Sync pending" in Notes column during this window

**Resolution**: Wait 5-10 minutes and re-run the script to verify sync completion.

---

## Physical Core License

### What It Is

Physical Core licensing is an option for SQL Server Enterprise Edition that licenses based on physical CPU cores rather than vCores.

### Status Values

- **Enabled**: Using physical core licensing model
- **Disabled**: Using vCore or other licensing model
- **Not Set**: No physical core license configuration found

### When Used

- Enterprise Edition with perpetual licenses
- High-core-count systems where physical core licensing is more cost-effective
- On-premises licensing models being replicated in Azure Arc

---

## Troubleshooting

### Script Won't Run - "Cannot Find Module"

```powershell
# Install missing module
Install-Module -Name Az -Scope CurrentUser -AllowClobber

# Or update existing module
Update-Module -Name Az
```

### Authentication Failed

```powershell
# Clear cached credentials
Clear-AzContext -Force

# Login again
Connect-AzAccount
```

### "Access Denied" / Permission Errors

**Required permissions**:
- `Microsoft.AzureArcData/sqlServerInstances/read`
- `Microsoft.HybridCompute/machines/read`
- `Microsoft.HybridCompute/machines/extensions/read`

Contact your Azure administrator to grant these permissions.

### No Servers Found

1. Verify subscription ID is correct in script
2. Confirm subscription contains Arc SQL Server resources
3. Check authentication context: `Get-AzContext`

### Extension Data Shows "Error Reading Extension"

- SQL extension may be in provisioning state
- Extension might have corrupted settings
- Re-run script in 5-10 minutes
- If persists, check extension details in Azure Portal

---

## Data Fields Explained

### Identifying Information
- **ServerName**: Name of the SQL Server instance in Azure Arc
- **ResourceGroup**: Azure resource group containing the server
- **Location**: Azure region
- **MachineName**: Name of the Arc-connected machine

### Connectivity Status
- **ConnectionStatus**: State of Arc machine connection (Connected/Disconnected/Expired)
- **LastHeartbeat**: Last time machine reported to Azure
- **AgentVersion**: Version of Azure Arc agent software on machine

### SQL Server Details
- **SQLVersion**: SQL Server version (2019, 2022, etc.)
- **SQLEdition**: SQL Server edition (Enterprise, Standard, Express, etc.)
- **Cores**: Number of processor cores allocated
- **OSType**: Operating system (Windows/Linux)

### Licensing Information
- **ExtensionLicenseType**: License type from SQL extension (source of truth)
- **CurrentLicenseType**: License type from SQL instance properties
- **PhysicalCoreLicense**: Physical core licensing status

### Extension & Health
- **ExtensionStatus**: SQL extension provisioning state (Succeeded/Failed/Provisioning)
- **HealthStatus**: Overall health assessment (Healthy/Unhealthy/Extension Issue/Orphaned)
- **Extensions**: List of all extensions on the Arc machine
- **Notes**: Additional context or error messages

---

## Examples & Use Cases

### Find All Unhealthy Servers

```powershell
$results = .\PostLicensingUpdateReport-v2.ps1
$results | Where-Object { $_.HealthStatus -ne "Healthy" } | Select-Object ServerName, HealthStatus, Notes
```

### Identify Servers with License Issues

```powershell
$results = .\PostLicensingUpdateReport-v2.ps1
$results | Where-Object { $_.ExtensionLicenseType -ne $_.CurrentLicenseType } | Select-Object ServerName, ExtensionLicenseType, CurrentLicenseType
```

### Count Licenses by Type

```powershell
$results = .\PostLicensingUpdateReport-v2.ps1
$results | Group-Object ExtensionLicenseType | Select-Object Name, Count
```

### Find High-Core Servers

```powershell
$results = .\PostLicensingUpdateReport-v2.ps1
$results | Where-Object { $_.Cores -gt 16 } | Select-Object ServerName, Cores, SQLEdition
```

### Export Specific Fields to CSV

```powershell
$results = .\PostLicensingUpdateReport-v2.ps1
$results | Select-Object ServerName, MachineName, HealthStatus, ExtensionLicenseType | Export-Csv -Path "C:\Reports\summary.csv" -NoTypeInformation
```

---

## Performance Considerations

### Execution Time

Script execution time depends on:
- Number of Arc SQL Server instances
- Number of Arc machines to query
- Network latency to Azure
- Extension complexity

**Typical duration**: 2-5 minutes for 20-50 servers

### Optimizing Performance

- Run during off-peak hours if checking many servers
- Use scheduled tasks to distribute reporting load
- Filter results in PowerShell rather than modifying the script

---

## Support & Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|---|---|---|
| Script times out | Too many servers or network latency | Re-run with fewer servers or check network |
| Memory errors | Large result set | Increase allocated memory or run on more powerful machine |
| File export fails | No write permission to C:\Scripts | Create directory manually or change $exportPath |
| Extension data missing | Extension not yet provisioned | Wait 10-15 minutes and re-run |

### Collecting Diagnostics

If you encounter issues, gather this information:

```powershell
# PowerShell version
$PSVersionTable

# Module versions
Get-Module Az.* | Select-Object Name, Version

# Azure context
Get-AzContext

# Subscription details
Get-AzSubscription -SubscriptionId "77b80376-724a-40fa-8c15-710765be0046"
```

---

## Version History

### v2.0 (Current)
- ✨ Added comprehensive comment documentation
- ✨ Reads license type from extension settings (authoritative source)
- ✨ Detects license sync status
- ✨ Identifies orphaned servers
- ✨ Added physical core license detection
- 📊 Enhanced summary statistics and analytics
- 📋 Improved report formatting and structure

### v1.0
- Initial release with basic health checking

---

## License

This script is provided as-is for use with Azure Arc-enabled SQL Server deployments.

---

## Author

**Created by**: Manoj Das  
**Organization**: Microsoft  
**Last Updated**: 2026-05-15

---

## Feedback & Contributions

For issues, questions, or improvements, please contact the script maintainer or create an issue in the repository.

---

## Related Documentation

- [Azure Arc-enabled SQL Server Documentation](https://docs.microsoft.com/en-us/sql/sql-server/azure-arc/overview)
- [Azure Arc Connected Machine Extensions](https://docs.microsoft.com/en-us/azure/azure-arc/servers/manage-extensions)
- [Azure PowerShell Documentation](https://docs.microsoft.com/en-us/powershell/azure/)
- [SQL Server Licensing Guide](https://www.microsoft.com/en-us/sql-server/sql-server-2022-pricing)
