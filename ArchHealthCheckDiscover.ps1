# ============================================
# Azure Arc SQL Server Health Check Script
# ============================================

#Setting the output path
$exportPath = "C:\Scripts"
if (-not (Test-Path $exportPath)) {
    New-Item -ItemType Directory -Path $exportPath | Out-Null
}

# Authenticate to Azure
Connect-AzAccount

# Set your subscription
$subscriptionId = "d49a99d8-9b06-499a-b794-10d83c6499f5"
Set-AzContext -SubscriptionId $subscriptionId

# Get all Arc-enabled SQL Servers
$arcSqlServers = Get-AzResource -ResourceType "Microsoft.AzureArcData/sqlServerInstances"

# Create results array
$healthCheckResults = @()

Write-Host "Starting health check for $($arcSqlServers.Count) Arc-enabled SQL Servers..." -ForegroundColor Cyan

foreach ($server in $arcSqlServers) {
    Write-Host "Checking: $($server.Name)..." -ForegroundColor Yellow
    
    # Get detailed server information
    $serverDetails = Get-AzResource -ResourceId $server.ResourceId
    
    # Get the connected machine (Arc server)
    $resourceGroup = $server.ResourceGroupName
    $machineName = $serverDetails.Properties.containerResourceId.Split('/')[-1]
    
    try {
        $arcMachine = Get-AzConnectedMachine -ResourceGroupName $resourceGroup -Name $machineName -ErrorAction Stop
        
        $healthStatus = [PSCustomObject]@{
            ServerName = $server.Name
            ResourceGroup = $resourceGroup
            Location = $server.Location
            MachineName = $machineName
            ConnectionStatus = $arcMachine.Status
            LastHeartbeat = $arcMachine.LastStatusChange
            AgentVersion = $arcMachine.AgentVersion
            OSType = $arcMachine.OSType
            CurrentLicenseType = $serverDetails.Properties.licenseType
            Version = $serverDetails.Properties.version
            Edition = $serverDetails.Properties.edition
            HealthStatus = if ($arcMachine.Status -eq "Connected") { "Healthy" } else { "Unhealthy" }
            Extensions = ($arcMachine.Extensions | ForEach-Object { "$($_.Name):$($_.ProvisioningState)" }) -join "; "
        }
        
    } catch {
        $healthStatus = [PSCustomObject]@{
            ServerName = $server.Name
            ResourceGroup = $resourceGroup
            Location = $server.Location
            MachineName = $machineName
            ConnectionStatus = "Error"
            LastHeartbeat = "N/A"
            AgentVersion = "N/A"
            OSType = "N/A"
            CurrentLicenseType = $serverDetails.Properties.licenseType
            Version = "N/A"
            Edition = "N/A"
            HealthStatus = "Error"
            Extensions = $_.Exception.Message
        }
    }
    
    $healthCheckResults += $healthStatus
}

# Display results
$healthCheckResults | Format-Table -AutoSize

# Export results
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$healthCheckResults | Export-Csv -Path "$exportPath\ArcSQLHealthCheck_$timestamp.csv" -NoTypeInformation
$healthCheckResults | Out-File -FilePath "$exportPath\ArcSQLHealthCheck_$timestamp.txt"

Write-Host "`nHealth check complete! Results exported to:" -ForegroundColor Green
Write-Host "  - ArcSQLHealthCheck_$timestamp.csv" -ForegroundColor Green
Write-Host "  - ArcSQLHealthCheck_$timestamp.txt" -ForegroundColor Green

# Summary
$totalServers = $healthCheckResults.Count
$healthyServers = ($healthCheckResults | Where-Object { $_.HealthStatus -eq "Healthy" }).Count
$unhealthyServers = $totalServers - $healthyServers

Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Total Servers: $totalServers" -ForegroundColor White
Write-Host "Healthy: $healthyServers" -ForegroundColor Green
Write-Host "Unhealthy: $unhealthyServers" -ForegroundColor Red