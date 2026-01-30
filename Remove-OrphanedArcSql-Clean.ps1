param(
    [Parameter(Mandatory=$true)][string]$SubscriptionId,
    [Parameter(Mandatory=$false)][string]$ResourceGroup,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [Parameter(Mandatory=$false)][switch]$DeleteOrphans,
    [Parameter(Mandatory=$false)][switch]$WhatIf
)

Write-Host "`nArc SQL Orphaned Instance Cleanup`n" -ForegroundColor Cyan

# Auth
Write-Host "Checking authentication..." -ForegroundColor Yellow
try { 
    $ctx = Get-AzContext -ErrorAction SilentlyContinue 
} catch { 
    $ctx = $null 
}

if (-not $ctx -or -not $ctx.Account) { 
    Write-Host "Not logged in. Logging in now..." -ForegroundColor Yellow
    Connect-AzAccount | Out-Null 
}

try {
    Write-Host "Setting subscription context..." -ForegroundColor Yellow
    $null = Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop
    $ctx = Get-AzContext
    Write-Host "Connected: $($ctx.Account.Id)" -ForegroundColor Green
    Write-Host "Subscription: $SubscriptionId`n" -ForegroundColor Green
} catch {
    Write-Host ""
    Write-Host "ERROR: Cannot set subscription context" -ForegroundColor Red
    Write-Host "Make sure you have access to subscription: $SubscriptionId" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# Get instances
if ($ResourceGroup) {
    $all = Get-AzResource -ResourceType "Microsoft.AzureArcData/sqlServerInstances" -ResourceGroupName $ResourceGroup
} else {
    $all = Get-AzResource -ResourceType "Microsoft.AzureArcData/sqlServerInstances"
}
Write-Host "Found $($all.Count) instances`n" -ForegroundColor Green

# Analyze
$results = @()
$orphans = 0
$valid = 0

foreach ($sql in $all) {
    Write-Host "Checking: $($sql.Name)" -ForegroundColor Yellow
    
    $r = [PSCustomObject]@{
        InstanceName = $sql.Name
        ResourceGroup = $sql.ResourceGroupName
        Location = $sql.Location
        ResourceId = $sql.ResourceId
        ContainerResourceId = ""
        MachineName = ""
        MachineExists = ""
        Status = ""
        Action = ""
        DateTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    
    $detail = Get-AzResource -ResourceId $sql.ResourceId
    $container = $detail.Properties.containerResourceId
    $r.ContainerResourceId = $container
    
    if ([string]::IsNullOrWhiteSpace($container)) {
        Write-Host "  ORPHAN: No container" -ForegroundColor Red
        $r.MachineName = "N/A"
        $r.MachineExists = "No"
        $r.Status = "Orphaned"
        $r.Action = if($DeleteOrphans){"Will Delete"}else{"Identified"}
        $orphans++
    } else {
        $machineName = $container.Split('/')[-1]
        $machineRG = $container.Split('/')[4]
        $r.MachineName = $machineName
        
        try {
            $machine = Get-AzConnectedMachine -Name $machineName -ResourceGroupName $machineRG -ErrorAction Stop
            Write-Host "  VALID: Machine exists" -ForegroundColor Green
            $r.MachineExists = "Yes"
            $r.Status = "Valid"
            $r.Action = "No Action"
            $valid++
        } catch {
            Write-Host "  ORPHAN: Machine deleted" -ForegroundColor Red
            $r.MachineExists = "No"
            $r.Status = "Orphaned"
            $r.Action = if($DeleteOrphans){"Will Delete"}else{"Identified"}
            $orphans++
        }
    }
    
    $results += $r
}

# Export
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$report = Join-Path $OutputPath "ArcSQL_OrphanReport_$ts.csv"
$results | Export-Csv -Path $report -NoTypeInformation -Force
Write-Host "`nReport: $report" -ForegroundColor Green

# Delete
if ($DeleteOrphans) {
    $toDelete = $results | Where-Object { $_.Status -eq "Orphaned" }
    
    if ($toDelete.Count -eq 0) {
        Write-Host "`nNo orphans to delete" -ForegroundColor Green
    } else {
        Write-Host "`nDeleting $($toDelete.Count) orphans..." -ForegroundColor Yellow
        
    foreach ($item in $toDelete) {
            Write-Host "  $($item.InstanceName)" -ForegroundColor Yellow
            if ($WhatIf) {
                Write-Host "    [WHATIF] Would delete" -ForegroundColor Cyan
                $item.Action = "WhatIf - Would Delete"
            } else {
                Remove-AzResource -ResourceId $item.ResourceId -Force | Out-Null
                Write-Host "    Deleted" -ForegroundColor Green
                $item.Action = "Deleted"
            }
        }
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Total: $($all.Count) | Valid: $valid | Orphaned: $orphans" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan

if ($orphans -gt 0) {
    $results | Where-Object {$_.Status -eq "Orphaned"} | Format-Table InstanceName, MachineName, Status -AutoSize
}