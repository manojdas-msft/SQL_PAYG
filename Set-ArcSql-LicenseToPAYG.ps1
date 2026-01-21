<#
.SYNOPSIS
    Converts Azure Arc-enabled SQL Server instances to PAYG licensing model.

.DESCRIPTION
    This script reads a CSV file containing Arc SQL Server instances and converts them
    to Pay-As-You-Go (PAYG) licensing. It also enables the "Apply physical core license"
    option for each instance. Results are exported to a CSV file.

.PARAMETER CsvPath
    Path to the input CSV file containing Arc SQL Server instances.
    Expected columns: ServerName, ResourceGroup, MachineName

.PARAMETER OutputPath
    Directory path where the output CSV file will be saved.

.PARAMETER SubscriptionId
    Azure subscription ID containing the Arc SQL Server instances.

.PARAMETER WhatIf
    Shows what would happen if the script runs without making actual changes.

.EXAMPLE
    .\Set-ArcSql-LicenseToPAYG.ps1 `
        -CsvPath "C:\scripts\ArcSQLHealthCheck_20260110_165143.csv" `
        -OutputPath "C:\Scripts" `
        -SubscriptionId "77b80376-724a-40fa-8c15-710765be0046" `
        -Verbose

.EXAMPLE
    .\Set-ArcSql-LicenseToPAYG.ps1 `
        -CsvPath "C:\scripts\ArcSQLHealthCheck_20260110_165143.csv" `
        -OutputPath "C:\Scripts" `
        -SubscriptionId "77b80376-724a-40fa-8c15-710765be0046" `
        -WhatIf `
        -Verbose

.NOTES
    Author: Generated Script
    Date: 2026-01-10
    Requires: Az.Accounts, Az.Resources, Az.ConnectedMachine modules
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Path to the input CSV file")]
    [ValidateScript({
        if (-not (Test-Path $_)) {
            throw "CSV file not found at path: $_"
        }
        if ($_ -notmatch '\.csv$') {
            throw "File must be a CSV file"
        }
        return $true
    })]
    [string]$CsvPath,

    [Parameter(Mandatory = $true, HelpMessage = "Directory path for output CSV file")]
    [ValidateScript({
        if (-not (Test-Path $_)) {
            throw "Output directory not found at path: $_"
        }
        return $true
    })]
    [string]$OutputPath,

    [Parameter(Mandatory = $true, HelpMessage = "Azure subscription ID")]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId
)

# ============================================
# Script Initialization
# ============================================

Write-Verbose "Script started at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Arc SQL Server License Conversion Script" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Check for required modules
$requiredModules = @('Az.Accounts', 'Az.Resources', 'Az.ConnectedMachine')
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Error "Required module '$module' is not installed. Please install it using: Install-Module -Name $module"
        exit 1
    }
}

# ============================================
# Azure Authentication
# ============================================

Write-Host "Checking Azure authentication..." -ForegroundColor Yellow
try {
    $context = Get-AzContext -ErrorAction Stop
    if (-not $context) {
        Write-Host "Not authenticated. Connecting to Azure..." -ForegroundColor Yellow
        Connect-AzAccount -ErrorAction Stop | Out-Null
    } else {
        Write-Host "Already authenticated as: $($context.Account.Id)" -ForegroundColor Green
    }
} catch {
    Write-Error "Failed to authenticate to Azure: $_"
    exit 1
}

# Set subscription context
Write-Host "Setting subscription context to: $SubscriptionId" -ForegroundColor Yellow
try {
    Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
    Write-Host "Subscription context set successfully" -ForegroundColor Green
} catch {
    Write-Error "Failed to set subscription context: $_"
    exit 1
}

# ============================================
# Import and Validate CSV
# ============================================

Write-Host "`nImporting CSV file: $CsvPath" -ForegroundColor Yellow
try {
    $servers = Import-Csv -Path $CsvPath -ErrorAction Stop
    Write-Host "Successfully imported $($servers.Count) server records" -ForegroundColor Green
} catch {
    Write-Error "Failed to import CSV file: $_"
    exit 1
}

# Validate required columns
$requiredColumns = @('ServerName', 'ResourceGroup', 'MachineName')
$csvColumns = $servers[0].PSObject.Properties.Name
$missingColumns = $requiredColumns | Where-Object { $_ -notin $csvColumns }

if ($missingColumns) {
    Write-Error "CSV file is missing required columns: $($missingColumns -join ', ')"
    exit 1
}

# ============================================
# Process Each Server
# ============================================

$results = @()
$successCount = 0
$failureCount = 0
$skippedCount = 0

Write-Host "`nProcessing $($servers.Count) Arc SQL Server instances...`n" -ForegroundColor Cyan

foreach ($server in $servers) {
    $serverName = $server.ServerName
    $resourceGroup = $server.ResourceGroup
    $machineName = $server.MachineName
    $currentLicense = $server.CurrentLicenseType

    Write-Host "[$($servers.IndexOf($server) + 1)/$($servers.Count)] Processing: $serverName" -ForegroundColor Yellow
    Write-Verbose "  Resource Group: $resourceGroup"
    Write-Verbose "  Machine Name: $machineName"
    Write-Verbose "  Current License: $currentLicense"

    $result = [PSCustomObject]@{
        ServerName          = $serverName
        ResourceGroup       = $resourceGroup
        MachineName         = $machineName
        PreviousLicenseType = $currentLicense
        NewLicenseType      = "PAYG"
        PhysicalCoreLicense = "Enabled"
        Status              = ""
        ErrorMessage        = ""
        ProcessedDateTime   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }

    try {
        # Get the Arc SQL Server instance resource
        Write-Verbose "  Retrieving Arc SQL Server resource..."
        $arcSqlResources = Get-AzResource `
            -ResourceGroupName $resourceGroup `
            -ResourceType "Microsoft.AzureArcData/sqlServerInstances" `
            -ErrorAction Stop | Where-Object { $_.Name -eq $serverName }

        if (-not $arcSqlResources) {
            throw "Arc SQL Server instance '$serverName' not found in resource group '$resourceGroup'"
        }

        $arcSqlResource = $arcSqlResources[0]
        Write-Verbose "  Found resource: $($arcSqlResource.ResourceId)"

        # Get current resource details
        $currentResource = Get-AzResource -ResourceId $arcSqlResource.ResourceId -ErrorAction Stop
        $currentProperties = $currentResource.Properties

        # Check if already PAYG
        if ($currentProperties.licenseType -eq "PAYG") {
            Write-Host "  Already configured as PAYG - checking physical core license setting..." -ForegroundColor Yellow
            
            # Check if physical core license is already enabled
            if ($currentProperties.UsePhysicalCoreLicense -eq $true) {
                Write-Host "  Already configured with physical core license enabled - skipping" -ForegroundColor Green
                $result.Status = "Skipped - Already Configured"
                $result.ErrorMessage = "Server already has PAYG license with physical core license enabled"
                $skippedCount++
                $results += $result
                continue
            }
        }

        # Prepare updated properties
        $updatedProperties = @{
            licenseType = "PAYG"
        }

        # Add physical core license property
        # Note: The actual property name may vary depending on API version
        # Common variations: UsePhysicalCoreLicense, physicalCoreLicense, enablePhysicalCoreLicense
        $updatedProperties.Add("UsePhysicalCoreLicense", $true)

        Write-Verbose "  Updated properties: $($updatedProperties | ConvertTo-Json -Compress)"

        # Perform the update
        if ($PSCmdlet.ShouldProcess($serverName, "Convert to PAYG license with physical core license enabled")) {
            Write-Host "  Updating license configuration..." -ForegroundColor Yellow

            # Update the resource
            Set-AzResource `
                -ResourceId $arcSqlResource.ResourceId `
                -Properties $updatedProperties `
                -Force `
                -ErrorAction Stop | Out-Null

            # Verify the update
            Start-Sleep -Seconds 2
            $updatedResource = Get-AzResource -ResourceId $arcSqlResource.ResourceId -ErrorAction Stop
            
            Write-Host "  Successfully updated to PAYG with physical core license" -ForegroundColor Green
            $result.Status = "Success"
            $result.NewLicenseType = $updatedResource.Properties.licenseType
            $result.PhysicalCoreLicense = if ($updatedResource.Properties.UsePhysicalCoreLicense) { "Enabled" } else { "Not Confirmed" }
            $successCount++
        } else {
            Write-Host "  [WHATIF] Would update license to PAYG with physical core license" -ForegroundColor Cyan
            $result.Status = "WhatIf - Not Executed"
            $result.ErrorMessage = "WhatIf mode - no changes made"
            $skippedCount++
        }

    } catch {
        Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
        Write-Verbose "  Full error: $_"
        $result.Status = "Failed"
        $result.ErrorMessage = $_.Exception.Message
        if ($_.Exception.InnerException) {
            $result.ErrorMessage += " | Inner: $($_.Exception.InnerException.Message)"
        }
        $failureCount++
    }

    $results += $result
    Write-Host ""
}

# ============================================
# Export Results
# ============================================

# Show debug info only with -Verbose
if ($VerbosePreference -eq 'Continue') {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "EXPORT DEBUG INFO" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Results array count: $($results.Count)" -ForegroundColor Yellow
    Write-Host "Results array type: $($results.GetType().FullName)" -ForegroundColor Yellow
    if ($results.Count -gt 0) {
        Write-Host "First result type: $($results[0].GetType().FullName)" -ForegroundColor Yellow
        Write-Host "First result properties: $($results[0].PSObject.Properties.Name -join ', ')" -ForegroundColor Yellow
        Write-Host "Sample data from first result:" -ForegroundColor Yellow
        Write-Host "  ServerName: $($results[0].ServerName)" -ForegroundColor Gray
        Write-Host "  Status: $($results[0].Status)" -ForegroundColor Gray
    } else {
        Write-Host "⚠ WARNING: Results array is EMPTY!" -ForegroundColor Red
    }
    Write-Host "========================================`n" -ForegroundColor Cyan
}

# Only attempt export if we have results
if ($results.Count -eq 0) {
    Write-Host "⚠ No results to export. Skipping file creation." -ForegroundColor Yellow
    $exportSuccess = $false
} else {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputFileName = "ArcSQL_LicenseConversion_$timestamp.csv"
    $outputFilePath = Join-Path -Path $OutputPath -ChildPath $outputFileName

    Write-Host "`nExporting $($results.Count) results to CSV file..." -ForegroundColor Yellow

    # Ensure the output directory exists
    if (-not (Test-Path -Path $OutputPath)) {
        try {
            New-Item -ItemType Directory -Path $OutputPath -Force -ErrorAction Stop | Out-Null
            Write-Verbose "Created output directory: $OutputPath"
        } catch {
            Write-Error "Failed to create output directory: $_"
        }
    }

    $exportSuccess = $false
    $exportError = $null

    # Method 1: Try Export-Csv (standard method)
    if (-not $exportSuccess) {
        try {
            Write-Verbose "Method 1: Attempting Export-Csv..."
            
            # Create a copy of results to avoid any reference issues
            $resultsToExport = @($results)
            
            # Use absolute path
            $absolutePath = [System.IO.Path]::GetFullPath($outputFilePath)
            Write-Verbose "Absolute path: $absolutePath"
            
            # Export
            $resultsToExport | Export-Csv -Path $absolutePath -NoTypeInformation -Force -ErrorAction Stop
            
            # Wait and verify
            Start-Sleep -Milliseconds 500
            
            if (Test-Path -Path $absolutePath) {
                $fileInfo = Get-Item -Path $absolutePath
                Write-Host "✓ Results exported successfully (Method 1: Export-Csv)" -ForegroundColor Green
                Write-Host "  File Size: $([math]::Round($fileInfo.Length / 1KB, 2)) KB" -ForegroundColor Gray
                Write-Host "  Full Path: $($fileInfo.FullName)" -ForegroundColor Gray
                $exportSuccess = $true
                $outputFilePath = $absolutePath
            } else {
                $exportError = "File not found after Export-Csv command"
                Write-Verbose "Method 1 failed: $exportError"
            }
        } catch {
            $exportError = $_.Exception.Message
            Write-Verbose "Method 1 exception: $exportError"
        }
    }

    # Method 2: Try ConvertTo-Csv + Out-File
    if (-not $exportSuccess) {
        try {
            Write-Verbose "Method 2: Attempting ConvertTo-Csv + Out-File..."
            
            $absolutePath = [System.IO.Path]::GetFullPath($outputFilePath)
            $csvContent = $results | ConvertTo-Csv -NoTypeInformation
            $csvContent | Out-File -FilePath $absolutePath -Encoding UTF8 -Force -ErrorAction Stop
            
            Start-Sleep -Milliseconds 500
            
            if (Test-Path -Path $absolutePath) {
                $fileInfo = Get-Item -Path $absolutePath
                Write-Host "✓ Results exported successfully (Method 2: ConvertTo-Csv + Out-File)" -ForegroundColor Green
                Write-Host "  File Size: $([math]::Round($fileInfo.Length / 1KB, 2)) KB" -ForegroundColor Gray
                Write-Host "  Full Path: $($fileInfo.FullName)" -ForegroundColor Gray
                $exportSuccess = $true
                $outputFilePath = $absolutePath
            } else {
                $exportError = "File not found after ConvertTo-Csv + Out-File"
                Write-Verbose "Method 2 failed: $exportError"
            }
        } catch {
            $exportError = $_.Exception.Message
            Write-Verbose "Method 2 exception: $exportError"
        }
    }

    # Method 3: Try Set-Content
    if (-not $exportSuccess) {
        try {
            Write-Verbose "Method 3: Attempting ConvertTo-Csv + Set-Content..."
            
            $absolutePath = [System.IO.Path]::GetFullPath($outputFilePath)
            $csvContent = $results | ConvertTo-Csv -NoTypeInformation
            Set-Content -Path $absolutePath -Value $csvContent -Force -ErrorAction Stop
            
            Start-Sleep -Milliseconds 500
            
            if (Test-Path -Path $absolutePath) {
                $fileInfo = Get-Item -Path $absolutePath
                Write-Host "✓ Results exported successfully (Method 3: Set-Content)" -ForegroundColor Green
                Write-Host "  File Size: $([math]::Round($fileInfo.Length / 1KB, 2)) KB" -ForegroundColor Gray
                Write-Host "  Full Path: $($fileInfo.FullName)" -ForegroundColor Gray
                $exportSuccess = $true
                $outputFilePath = $absolutePath
            } else {
                $exportError = "File not found after Set-Content"
                Write-Verbose "Method 3 failed: $exportError"
            }
        } catch {
            $exportError = $_.Exception.Message
            Write-Verbose "Method 3 exception: $exportError"
        }
    }

    # Method 4: Manual CSV construction (last resort)
    if (-not $exportSuccess) {
        try {
            Write-Verbose "Method 4: Attempting manual CSV construction..."
            
            $absolutePath = [System.IO.Path]::GetFullPath($outputFilePath)
            
            # Build CSV manually
            $csvLines = New-Object System.Collections.ArrayList
            [void]$csvLines.Add("ServerName,ResourceGroup,MachineName,PreviousLicenseType,NewLicenseType,PhysicalCoreLicense,Status,ErrorMessage,ProcessedDateTime")
            
            foreach ($result in $results) {
                $errorMsg = if ($result.ErrorMessage) { $result.ErrorMessage -replace '"','""' } else { "" }
                $line = "`"$($result.ServerName)`",`"$($result.ResourceGroup)`",`"$($result.MachineName)`",`"$($result.PreviousLicenseType)`",`"$($result.NewLicenseType)`",`"$($result.PhysicalCoreLicense)`",`"$($result.Status)`",`"$errorMsg`",`"$($result.ProcessedDateTime)`""
                [void]$csvLines.Add($line)
            }
            
            # Write to file
            [System.IO.File]::WriteAllLines($absolutePath, $csvLines)
            
            Start-Sleep -Milliseconds 500
            
            if (Test-Path -Path $absolutePath) {
                $fileInfo = Get-Item -Path $absolutePath
                Write-Host "✓ Results exported successfully (Method 4: Manual CSV)" -ForegroundColor Green
                Write-Host "  File Size: $([math]::Round($fileInfo.Length / 1KB, 2)) KB" -ForegroundColor Gray
                Write-Host "  Full Path: $($fileInfo.FullName)" -ForegroundColor Gray
                $exportSuccess = $true
                $outputFilePath = $absolutePath
            } else {
                $exportError = "File not found after manual CSV creation"
                Write-Verbose "Method 4 failed: $exportError"
            }
        } catch {
            $exportError = $_.Exception.Message
            Write-Verbose "Method 4 exception: $exportError"
        }
    }

    # Final check and warning
    if (-not $exportSuccess) {
        Write-Host "`n⚠ WARNING: Could not create output file!" -ForegroundColor Red
        Write-Host "Last error: $exportError" -ForegroundColor Yellow
        Write-Host "Results are available in the `$results variable for this session." -ForegroundColor Yellow
        Write-Host "You can manually export by running:" -ForegroundColor Yellow
        Write-Host "  `$results | Export-Csv -Path `"$outputFilePath`" -NoTypeInformation" -ForegroundColor Gray
        Write-Host "`nTo diagnose the issue, run: .\Test-CsvExport.ps1" -ForegroundColor Yellow
    }
}

# ============================================
# Summary Report
# ============================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "CONVERSION SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total Servers Processed: $($servers.Count)" -ForegroundColor White
Write-Host "Successful Conversions:  $successCount" -ForegroundColor Green
Write-Host "Failed Conversions:      $failureCount" -ForegroundColor Red
Write-Host "Skipped (Already Set):   $skippedCount" -ForegroundColor Yellow

# Verify output file exists and display info
Write-Host "`nOutput File Status:" -ForegroundColor White
if (Test-Path -Path $outputFilePath) {
    $fileInfo = Get-Item -Path $outputFilePath
    Write-Host "  ✓ File Created Successfully" -ForegroundColor Green
    Write-Host "  Location: $($fileInfo.FullName)" -ForegroundColor Gray
    Write-Host "  Size: $([math]::Round($fileInfo.Length / 1KB, 2)) KB" -ForegroundColor Gray
} else {
    Write-Host "  ✗ File NOT Found" -ForegroundColor Red
    Write-Host "  Expected: $outputFilePath" -ForegroundColor Gray
    Write-Host "`n  Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  1. Run: .\Test-CsvExport.ps1 to diagnose the issue" -ForegroundColor Gray
    Write-Host "  2. Results are still available in memory as `$results variable" -ForegroundColor Gray
    Write-Host "  3. Try exporting manually: `$results | Export-Csv -Path 'C:\Temp\output.csv' -NoTypeInformation" -ForegroundColor Gray
}

Write-Host "========================================`n" -ForegroundColor Cyan

# Display detailed results table
Write-Host "Detailed Results:" -ForegroundColor Cyan
$results | Format-Table -Property ServerName, Status, PreviousLicenseType, NewLicenseType, PhysicalCoreLicense, ErrorMessage -AutoSize

# If export failed, provide manual export instructions
if (-not $exportSuccess -and $results.Count -gt 0) {
    Write-Host "`n========================================" -ForegroundColor Yellow
    Write-Host "MANUAL EXPORT OPTION" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "The results are still available in the `$results variable." -ForegroundColor White
    Write-Host "You can manually export them by running this command:" -ForegroundColor White
    Write-Host "`n`$results | Export-Csv -Path '$outputFilePath' -NoTypeInformation -Force" -ForegroundColor Cyan
    Write-Host "`nOr to a different location:" -ForegroundColor White
    Write-Host "`$results | Export-Csv -Path 'C:\Temp\ArcSQL_Results.csv' -NoTypeInformation -Force" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Yellow
}

# Return results for pipeline usage
Write-Verbose "Script completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
return $results
