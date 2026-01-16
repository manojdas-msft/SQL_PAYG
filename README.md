# ArchHealthCheckDiscover.ps1

A PowerShell script to discover SQL Server instances/components relevant to archiving operations and produce a health-check report. This README provides usage guidance, examples, expected outputs, and recommendations for automation and security.

## Table of Contents
- Overview
- Requirements
- Installation
- Usage
- Parameters
- Examples
- Output
- License & Author

## Overview
ArchHealthCheckDiscover.ps1 probes one or more SQL Server instances to collect information relevant to archival processes (database sizes, archive tables, retention configuration, backup/restore status, job status, index health, etc.) and generates a consolidated report for operations and capacity planning.

## Requirements
- PowerShell 5.1 or PowerShell 7+
- Network access to target SQL Server instances (TCP 1433 or configured port)
- Credentials with appropriate permissions to query sys views and system databases (typically read access to msdb and target databases). If your script performs changes, additional privileges are required.
- Recommended PowerShell modules (install if needed):
  - SqlServer (Install-Module -Name SqlServer)
  - Alternatively, use System.Data.SqlClient / Microsoft.Data.SqlClient if the script uses that.
- Sufficient disk space to store report files and logs.

## Installation
1. Place `ArchHealthCheckDiscover.ps1` in a scripts directory in your repository or deployment location.
2. Ensure the script is unblocked:
   ```powershell
   Unblock-File .\ArchHealthCheckDiscover.ps1
   ```
3. If required modules are missing, install them:
   ```powershell
   Install-Module -Name SqlServer -Scope AllUsers
   ```
## Usage
Run the script from an elevated PowerShell prompt or with an account that has the necessary Azure/Arc permissions.

Basic invocation pattern:
```powershell
.\ArchHealthCheckDiscover.ps1 -
```
## Parameters
- `-exportPath` (string)  
 $exportPath = "C:\Scripts".

- `-subscriptionId` (string)  
  $subscriptionId = "123-9b06-1234-b794-10d83c45009f5"

## Output
- Primary report file(s) written to `-OutputPath`. Suggested filename pattern:
  `ArchHealthCheckDiscover_<yyyyMMdd_HHmmss>.<ext>` (e.g., `.html`, `.csv`, `.json`)
- A machine-readable results file (CSV) may be included for further automation.
- A human-friendly text version summary for operations teams.


## License & Author
- Author: Manoj Das [HLS]

