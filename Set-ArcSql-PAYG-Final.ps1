<#
.SYNOPSIS
    Converts Azure Arc-enabled SQL Server instances to PAYG licensing with physical core license option.

.PARAMETER CsvPath
    Path to the input CSV file containing Arc SQL Server instances.

.PARAMETER OutputPath
    Directory path where the output CSV file will be saved.

.PARAMETER SubscriptionId
    Azure subscription ID.

.PARAMETER EnablePhysicalCoreLicense
    Enables the "Use physical core license" option.

.PARAMETER WhatIf
    Shows what would happen without making changes.

.EXAMPLE
    .\Set-ArcSql-PAYG-Final.ps1 `
        -CsvPath "C:\scripts\ArcSQLHealthCheck_20260110_175248.csv" `
        -OutputPath "C:\Scripts" `
        -SubscriptionId "77b80376-724a-40fa-8c15-710765be0046" `
        -EnablePhysicalCoreLicense `
        -Verbose
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$CsvPath,
    
    [Parameter(Mandatory=$true)]
    [string]$OutputPath,
    
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$false)]
    [switch]$EnablePhysicalCoreLicense,
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Arc SQL License Conversion - Final" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Authenticate
Write-Host "Checking authentication..." -ForegroundColor Yellow
$ctx = Get-AzContext
if (-not $ctx) { 
    Write-Host "Not authenticated. Connecting..." -ForegroundColor Yellow
    Connect-AzAccount 
}
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
Write-Host "Connected as: $($ctx.Account.Id)" -ForegroundColor Green

# Load CSV
Write-Host "`nLoading CSV..." -ForegroundColor Yellow
if (-not (Test-Path $CsvPath)) {
    Write-Error "CSV file not found: $CsvPath"
    exit 1
}
$servers = Import-Csv -Path $CsvPath
Write-Host "Loaded $($servers.Count) servers" -ForegroundColor Green

if ($EnablePhysicalCoreLicense) {
    Write-Host "Physical core license option: ENABLED" -ForegroundColor Cyan
} else {
    Write-Host "Physical core license option: Not enabled" -ForegroundColor Gray
}

Write-Host "`nProcessing servers...`n" -ForegroundColor Cyan

$results = @()
$success = 0
$failed = 0
$skipped = 0

foreach ($server in $servers) {
    $serverName = $server.ServerName
    $resourceGroup = $server.ResourceGroup
    $machineName = $server.MachineName
    $location = $server.Location
    
    $index = $servers.IndexOf($server) + 1
    Write-Host "[$index/$($servers.Count)] $serverName ($location)" -ForegroundColor Yellow
    
    $result = [PSCustomObject]@{
        ServerName = $serverName
        ResourceGroup = $resourceGroup
        MachineName = $machineName
        Location = $location
        PreviousLicense = $server.CurrentLicenseType
        NewLicense = "PAYG"
        PhysicalCore = if($EnablePhysicalCoreLicense){"Enabled"}else{"Not Enabled"}
        Status = ""
        Error = ""
        DateTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    
    try {
        # Get SQL extension
        Write-Verbose "  Getting extensions for machine: $machineName"
        $extensions = Get-AzConnectedMachineExtension -MachineName $machineName -ResourceGroupName $resourceGroup -ErrorAction Stop
        $sqlExt = $extensions | Where-Object { $_.Publisher -eq 'Microsoft.AzureData' -and $_.ProvisioningState -eq 'Succeeded' } | Select-Object -First 1
        
        if (-not $sqlExt) {
            throw "No SQL extension found on machine (or not in Succeeded state)"
        }
        
        $extName = $sqlExt.Name
        $extPublisher = $sqlExt.Publisher
        $extType = $sqlExt.MachineExtensionType
        
        Write-Host "  Extension: $extName" -ForegroundColor Gray
        Write-Host "  Current License: $($sqlExt.Setting['LicenseType'])" -ForegroundColor Gray
        
        # Check current physical core license setting
        $currentPcoreSetting = $sqlExt.Setting['UsePhysicalCoreLicense']
        if ($currentPcoreSetting) {
            Write-Host "  Current Physical Core: IsApplied=$($currentPcoreSetting['IsApplied'])" -ForegroundColor Gray
        } else {
            Write-Host "  Current Physical Core: Not Set" -ForegroundColor Gray
        }
        
        # Determine if update is needed
        $needsUpdate = $false
        
        if ($sqlExt.Setting['LicenseType'] -ne 'PAYG') {
            $needsUpdate = $true
            Write-Host "  -> License needs update: $($sqlExt.Setting['LicenseType']) -> PAYG" -ForegroundColor Yellow
        }
        
        if ($EnablePhysicalCoreLicense) {
            if (-not $currentPcoreSetting -or $currentPcoreSetting['IsApplied'] -ne $true) {
                $needsUpdate = $true
                Write-Host "  -> Physical core license needs update" -ForegroundColor Yellow
            }
        }
        
        if (-not $needsUpdate) {
            Write-Host "  Already configured correctly - skipping" -ForegroundColor Green
            $result.Status = "Skipped - Already Configured"
            $skipped++
            $results += $result
            Write-Host ""
            continue
        }
        
        # Prepare settings - deep copy
        Write-Verbose "  Preparing settings..."
        $settings = @{}
        foreach ($key in $sqlExt.Setting.Keys) {
            if ($sqlExt.Setting[$key] -is [System.Collections.IDictionary]) {
                $settings[$key] = @{}
                foreach ($subKey in $sqlExt.Setting[$key].Keys) {
                    $settings[$key][$subKey] = $sqlExt.Setting[$key][$subKey]
                }
            } else {
                $settings[$key] = $sqlExt.Setting[$key]
            }
        }
        
        # Update license type
        $settings['LicenseType'] = 'PAYG'
        Write-Verbose "  Setting LicenseType = PAYG"
        
        # Add/Update physical core license
        if ($EnablePhysicalCoreLicense) {
            $timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            $settings['UsePhysicalCoreLicense'] = @{
                IsApplied = $true
                LastUpdatedTimestamp = $timestamp
            }
            Write-Verbose "  Setting UsePhysicalCoreLicense.IsApplied = True"
            Write-Verbose "  Timestamp: $timestamp"
        }
        
        if ($WhatIf) {
            Write-Host "  [WHATIF] Would update extension settings" -ForegroundColor Cyan
            $result.Status = "WhatIf"
            $skipped++
        } else {
            # Update extension
            Write-Host "  Updating extension..." -ForegroundColor Yellow
            
            Set-AzConnectedMachineExtension `
                -Name $extName `
                -ResourceGroupName $resourceGroup `
                -MachineName $machineName `
                -Location $location `
                -Publisher $extPublisher `
                -ExtensionType $extType `
                -Setting $settings `
                -NoWait `
                -ErrorAction Stop | Out-Null
            
            Write-Host "  Success (update initiated)" -ForegroundColor Green
            $result.Status = "Success"
            $success++
        }
    }
    catch {
        Write-Host "  Failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Verbose "  Full error: $_"
        $result.Status = "Failed"
        $result.Error = $_.Exception.Message
        $failed++
    }
    
    $results += $result
    Write-Host ""
}

# Export results
Write-Host "Exporting results..." -ForegroundColor Yellow
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outFile = Join-Path $OutputPath "ArcSQL_Results_$timestamp.csv"
$results | Export-Csv -Path $outFile -NoTypeInformation -Force

if (Test-Path $outFile) {
    Write-Host "Results exported: $outFile" -ForegroundColor Green
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total Servers:  $($servers.Count)" -ForegroundColor White
Write-Host "Successful:     $success" -ForegroundColor Green
Write-Host "Failed:         $failed" -ForegroundColor Red
Write-Host "Skipped:        $skipped" -ForegroundColor Yellow
Write-Host "`nOutput File:    $outFile" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan

# Display results
$results | Format-Table ServerName, Status, PreviousLicense, NewLicense, PhysicalCore, Error -AutoSize

# Verification tip
if ($success -gt 0) {
    Write-Host "`nNote: Changes may take 1-2 minutes to appear in Azure Portal" -ForegroundColor Yellow
    Write-Host "`nTo verify physical core license setting:" -ForegroundColor Cyan
    Write-Host '$ext = Get-AzConnectedMachineExtension -MachineName "WSQL2022" -ResourceGroupName "rgInova-poc" | Where-Object {$_.Publisher -eq "Microsoft.AzureData"}' -ForegroundColor Gray
    Write-Host '$ext.Setting["UsePhysicalCoreLicense"]' -ForegroundColor Gray
    Write-Host ""
}

return $results
