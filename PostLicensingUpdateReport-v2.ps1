# ============================================
# Azure Arc SQL Server Health Check Script
# Reads license type from EXTENSION settings (actual source of truth)
# ============================================

# Setting the output path
$exportPath = "C:\Scripts"
if (-not (Test-Path $exportPath)) {
    New-Item -ItemType Directory -Path $exportPath | Out-Null
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Azure Arc SQL Health Check" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Authenticate to Azure
Write-Host "Checking authentication..." -ForegroundColor Yellow
$ctx = Get-AzContext -ErrorAction SilentlyContinue
if (-not $ctx) {
    Connect-AzAccount
}

# Set your subscription
$subscriptionId = "77b80376-724a-40fa-8c15-710765be0046"
Set-AzContext -SubscriptionId $subscriptionId | Out-Null
Write-Host "Subscription set`n" -ForegroundColor Green

# Get all Arc-enabled SQL Servers
Write-Host "Retrieving Arc SQL Servers..." -ForegroundColor Yellow
$arcSqlServers = Get-AzResource -ResourceType "Microsoft.AzureArcData/sqlServerInstances"
Write-Host "Found $($arcSqlServers.Count) Arc-enabled SQL Servers`n" -ForegroundColor Green

# Create results array
$healthCheckResults = @()

Write-Host "Starting health check...`n" -ForegroundColor Cyan

foreach ($server in $arcSqlServers) {
    $index = $arcSqlServers.IndexOf($server) + 1
    Write-Host "[$index/$($arcSqlServers.Count)] Checking: $($server.Name)..." -ForegroundColor Yellow
    
    # Get detailed server information
    $serverDetails = Get-AzResource -ResourceId $server.ResourceId
    
    # Get the connected machine (Arc server)
    $resourceGroup = $server.ResourceGroupName
    $containerResourceId = $serverDetails.Properties.containerResourceId
    
    # Initialize result object
    $healthStatus = [PSCustomObject]@{
        ServerName = $server.Name
        ResourceGroup = $resourceGroup
        Location = $server.Location
        MachineName = ""
        ConnectionStatus = ""
        LastHeartbeat = ""
        AgentVersion = ""
        OSType = ""
        CurrentLicenseType = ""
        ExtensionLicenseType = ""
        PhysicalCoreLicense = ""
        ExtensionStatus = ""
        SQLVersion = $serverDetails.Properties.version
        SQLEdition = $serverDetails.Properties.edition
        Cores = $serverDetails.Properties.cores
        HealthStatus = ""
        Extensions = ""
        Notes = ""
    }
    
    # Check if container resource ID exists
    if ([string]::IsNullOrWhiteSpace($containerResourceId)) {
        $healthStatus.MachineName = "N/A"
        $healthStatus.ConnectionStatus = "Orphaned"
        $healthStatus.CurrentLicenseType = $serverDetails.Properties.licenseType
        $healthStatus.ExtensionLicenseType = "N/A - No Machine"
        $healthStatus.HealthStatus = "Orphaned"
        $healthStatus.Notes = "No Arc machine reference"
        Write-Host "  -> Orphaned (no machine)" -ForegroundColor Red
        $healthCheckResults += $healthStatus
        continue
    }
    
    $machineName = $containerResourceId.Split('/')[-1]
    $healthStatus.MachineName = $machineName
    
    try {
        # Get Arc machine details
        $arcMachine = Get-AzConnectedMachine -ResourceGroupName $resourceGroup -Name $machineName -ErrorAction Stop
        
        $healthStatus.ConnectionStatus = $arcMachine.Status
        $healthStatus.LastHeartbeat = $arcMachine.LastStatusChange
        $healthStatus.AgentVersion = $arcMachine.AgentVersion
        $healthStatus.OSType = $arcMachine.OSType
        $healthStatus.Extensions = ($arcMachine.Extensions | ForEach-Object { "$($_.Name):$($_.ProvisioningState)" }) -join "; "
        
        # Get SQL extension to read ACTUAL license type
        try {
            $sqlExtension = Get-AzConnectedMachineExtension -MachineName $machineName -ResourceGroupName $resourceGroup -ErrorAction Stop | 
                Where-Object { $_.Publisher -eq 'Microsoft.AzureData' -and $_.ProvisioningState -eq 'Succeeded' } | 
                Select-Object -First 1
            
            if ($sqlExtension) {
                # Read license from EXTENSION settings (source of truth)
                $healthStatus.ExtensionLicenseType = $sqlExtension.Setting['LicenseType']
                $healthStatus.ExtensionStatus = $sqlExtension.ProvisioningState
                
                # Check physical core license
                $pcoreSetting = $sqlExtension.Setting['UsePhysicalCoreLicense']
                if ($pcoreSetting) {
                    $healthStatus.PhysicalCoreLicense = if ($pcoreSetting['IsApplied'] -eq $true) { "Enabled" } else { "Disabled" }
                } else {
                    $healthStatus.PhysicalCoreLicense = "Not Set"
                }
                
                # Also get from SQL instance properties for comparison
                $healthStatus.CurrentLicenseType = $serverDetails.Properties.licenseType
                
                # Check if they match
                if ($healthStatus.ExtensionLicenseType -ne $healthStatus.CurrentLicenseType) {
                    $healthStatus.Notes = "Sync pending: Extension=$($healthStatus.ExtensionLicenseType), Instance=$($healthStatus.CurrentLicenseType)"
                    Write-Host "  -> License sync pending" -ForegroundColor Yellow
                } else {
                    Write-Host "  -> OK: $($healthStatus.ExtensionLicenseType)" -ForegroundColor Green
                }
                
            } else {
                $healthStatus.ExtensionLicenseType = "Extension Not Found/Failed"
                $healthStatus.ExtensionStatus = "Not Found"
                $healthStatus.CurrentLicenseType = $serverDetails.Properties.licenseType
                $healthStatus.Notes = "SQL extension not in Succeeded state"
                Write-Host "  -> Extension issue" -ForegroundColor Red
            }
            
        } catch {
            $healthStatus.ExtensionLicenseType = "Error reading extension"
            $healthStatus.CurrentLicenseType = $serverDetails.Properties.licenseType
            $healthStatus.Notes = "Failed to get extension: $($_.Exception.Message)"
            Write-Host "  -> Extension read error" -ForegroundColor Red
        }
        
        # Determine health status
        if ($arcMachine.Status -eq "Connected" -and $healthStatus.ExtensionStatus -eq "Succeeded") {
            $healthStatus.HealthStatus = "Healthy"
        } elseif ($arcMachine.Status -eq "Connected" -and $healthStatus.ExtensionStatus -ne "Succeeded") {
            $healthStatus.HealthStatus = "Extension Issue"
        } else {
            $healthStatus.HealthStatus = "Unhealthy"
        }
        
    } catch {
        $healthStatus.ConnectionStatus = "Machine Not Found"
        $healthStatus.LastHeartbeat = "N/A"
        $healthStatus.AgentVersion = "N/A"
        $healthStatus.OSType = "N/A"
        $healthStatus.CurrentLicenseType = $serverDetails.Properties.licenseType
        $healthStatus.ExtensionLicenseType = "N/A - Machine Deleted"
        $healthStatus.HealthStatus = "Orphaned"
        $healthStatus.Extensions = "Machine Error"
        $healthStatus.Notes = "Arc machine does not exist"
        Write-Host "  -> Machine not found (orphaned)" -ForegroundColor Red
    }
    
    $healthCheckResults += $healthStatus
}

# Display results
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "RESULTS" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
$healthCheckResults | Format-Table ServerName, MachineName, SQLEdition, SQLVersion, Cores, ExtensionLicenseType, PhysicalCoreLicense, ExtensionStatus, HealthStatus -AutoSize

# Export results
Write-Host "`nExporting results..." -ForegroundColor Yellow
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$csvFile = "$exportPath\ArcSQLHealthCheck_$timestamp.csv"
$txtFile = "$exportPath\ArcSQLHealthCheck_$timestamp.txt"

$healthCheckResults | Export-Csv -Path $csvFile -NoTypeInformation -Force
$healthCheckResults | Out-File -FilePath $txtFile -Force

Write-Host "Results exported to:" -ForegroundColor Green
Write-Host "  - $csvFile" -ForegroundColor Green
Write-Host "  - $txtFile" -ForegroundColor Green

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$totalServers = $healthCheckResults.Count
$healthyServers = ($healthCheckResults | Where-Object { $_.HealthStatus -eq "Healthy" }).Count
$extensionIssues = ($healthCheckResults | Where-Object { $_.HealthStatus -eq "Extension Issue" }).Count
$unhealthyServers = ($healthCheckResults | Where-Object { $_.HealthStatus -eq "Unhealthy" }).Count
$orphanedServers = ($healthCheckResults | Where-Object { $_.HealthStatus -eq "Orphaned" }).Count

Write-Host "Total Servers:      $totalServers" -ForegroundColor White
Write-Host "Healthy:            $healthyServers" -ForegroundColor Green
Write-Host "Extension Issues:   $extensionIssues" -ForegroundColor Yellow
Write-Host "Unhealthy:          $unhealthyServers" -ForegroundColor Red
Write-Host "Orphaned:           $orphanedServers" -ForegroundColor Magenta

# License breakdown
Write-Host "`nLicense Type Breakdown:" -ForegroundColor Cyan
$licenseGroups = $healthCheckResults | Group-Object ExtensionLicenseType
foreach ($group in $licenseGroups) {
    Write-Host "  $($group.Name): $($group.Count)" -ForegroundColor White
}

# Physical core license breakdown
Write-Host "`nPhysical Core License:" -ForegroundColor Cyan
$pcoreGroups = $healthCheckResults | Group-Object PhysicalCoreLicense
foreach ($group in $pcoreGroups) {
    $color = if ($group.Name -eq "Enabled") { "Green" } else { "Gray" }
    Write-Host "  $($group.Name): $($group.Count)" -ForegroundColor $color
}

# SQL Edition breakdown
Write-Host "`nSQL Edition Breakdown:" -ForegroundColor Cyan
$editionGroups = $healthCheckResults | Where-Object { $_.SQLEdition } | Group-Object SQLEdition | Sort-Object Name
foreach ($group in $editionGroups) {
    Write-Host "  $($group.Name): $($group.Count)" -ForegroundColor White
}

# SQL Version breakdown
Write-Host "`nSQL Version Breakdown:" -ForegroundColor Cyan
$versionGroups = $healthCheckResults | Where-Object { $_.SQLVersion } | Group-Object SQLVersion | Sort-Object Name
foreach ($group in $versionGroups) {
    Write-Host "  $($group.Name): $($group.Count)" -ForegroundColor White
}

# Cores summary
Write-Host "`nCores Summary:" -ForegroundColor Cyan
$validCores = $healthCheckResults | Where-Object { $_.Cores -gt 0 }
if ($validCores.Count -gt 0) {
    $totalCores  = ($validCores | Measure-Object -Property Cores -Sum).Sum
    $avgCores    = [math]::Round(($validCores | Measure-Object -Property Cores -Average).Average, 1)
    $maxCores    = ($validCores | Measure-Object -Property Cores -Maximum).Maximum
    $minCores    = ($validCores | Measure-Object -Property Cores -Minimum).Minimum
    Write-Host "  Total Cores:   $totalCores" -ForegroundColor White
    Write-Host "  Average Cores: $avgCores" -ForegroundColor White
    Write-Host "  Max Cores:     $maxCores" -ForegroundColor White
    Write-Host "  Min Cores:     $minCores" -ForegroundColor White
} else {
    Write-Host "  No core data available" -ForegroundColor Gray
}

# Show servers with issues
if ($extensionIssues -gt 0) {
    Write-Host "`nServers with Extension Issues:" -ForegroundColor Yellow
    $healthCheckResults | Where-Object { $_.HealthStatus -eq "Extension Issue" } | 
        Select-Object ServerName, ExtensionStatus, Notes | 
        Format-Table -AutoSize
}

if ($orphanedServers -gt 0) {
    Write-Host "`nOrphaned Servers (should be cleaned up):" -ForegroundColor Magenta
    $healthCheckResults | Where-Object { $_.HealthStatus -eq "Orphaned" } | 
        Select-Object ServerName, MachineName, Notes | 
        Format-Table -AutoSize
}

# Show sync pending
$syncPending = $healthCheckResults | Where-Object { $_.Notes -like "*Sync pending*" }
if ($syncPending.Count -gt 0) {
    Write-Host "`nServers with Sync Pending ($($syncPending.Count)):" -ForegroundColor Yellow
    $syncPending | Select-Object ServerName, Notes | Format-Table -AutoSize
    Write-Host "Note: These will sync automatically. Wait 5-10 minutes and run script again." -ForegroundColor Gray
}

Write-Host "`n========================================`n" -ForegroundColor Cyan

return $healthCheckResults
