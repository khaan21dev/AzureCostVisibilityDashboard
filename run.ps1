param($Timer)

Write-Host "Cost Dashboard function started at $(Get-Date)"

# 1. Environment Variables
$subscriptionId = $env:SUBSCRIPTION_ID
$logicAppUrl = $env:LOGIC_APP_URL
$storageConnection = $env:STORAGE_CONNECTION
$thresholdPercent = [int]$env:COST_THRESHOLD_PERCENT

$yesterday = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")
Write-Host "Analyzing costs for: $yesterday"

# 2. Authenticate using App Service Managed Identity Endpoints
$tokenUrl = "$($env:IDENTITY_ENDPOINT)?api-version=2019-08-01&resource=https://management.azure.com/"
$tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Headers @{"X-IDENTITY-HEADER"=$env:IDENTITY_HEADER} -Method Get
$accessToken = $tokenResponse.access_token
$authHeader = @{ Authorization = "Bearer $accessToken"; "Content-Type" = "application/json" }
Write-Host "Authentication successful"

# 3. Query Cost Management API for yesterday's spend
$costUrl = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.CostManagement/query?api-version=2023-03-01"
$costBody = @{
    type = "ActualCost"
    timeframe = "Custom"
    timePeriod = @{ from = $yesterday; to = $yesterday }
    dataset = @{
        granularity = "None"
        aggregation = @{ totalCost = @{ name = "PreTaxCost"; function = "Sum" } }
        grouping = @( @{ type = "Dimension"; name = "ServiceName" } )
    }
} | ConvertTo-Json -Depth 10

$costResponse = Invoke-RestMethod -Uri $costUrl -Headers $authHeader -Method Post -Body $costBody
$rows = $costResponse.properties.rows

$totalSpend = 0
$serviceBreakdown = @()
foreach ($row in $rows) {
    $cost = [Math]::Round([double]$row[0], 2)
    $service = $row[1]
    $totalSpend += $cost
    if ($cost -gt 0) { $serviceBreakdown += @{ Service = $service; Cost = $cost } }
}
$totalSpend = [Math]::Round($totalSpend, 2)
Write-Host "Total yesterday spend: $totalSpend"

# 4. Check for Anomalies (Yesterday vs previous 7-day average)
$sevenDaysAgo = (Get-Date).AddDays(-8).ToString("yyyy-MM-dd")
$twoDaysAgo = (Get-Date).AddDays(-2).ToString("yyyy-MM-dd")

$historyBody = @{
    type = "ActualCost"
    timeframe = "Custom"
    timePeriod = @{ from = $sevenDaysAgo; to = $twoDaysAgo }
    dataset = @{ granularity = "Daily"; aggregation = @{ totalCost = @{ name = "PreTaxCost"; function = "Sum" } } }
} | ConvertTo-Json -Depth 10

$historyResponse = Invoke-RestMethod -Uri $costUrl -Headers $authHeader -Method Post -Body $historyBody
$historyRows = $historyResponse.properties.rows

$historicalSum = 0
foreach ($hRow in $historyRows) { $historicalSum += [double]$hRow[0] }
$historicalAvg = if ($historyRows.Count -gt 0) { [Math]::Round($historicalSum / $historyRows.Count, 2) } else { 0 }

$isAnomaly = $false
$anomalyMessage = "No cost anomalies detected."
if ($historicalAvg -gt 0) {
    $pctIncrease = (($totalSpend - $historicalAvg) / $historicalAvg) * 100
    if ($pctIncrease -gt $thresholdPercent) {
        $isAnomaly = $true
        $anomalyMessage = "⚠️ COST ANOMALY DETECTED: Yesterday's spend ($totalSpend) was $([Math]::Round($pctIncrease, 1))% higher than the 7-day average ($historicalAvg)."
    }
}
Write-Host $anomalyMessage

# 5. Query Azure Resource Graph for missing tags
$graphUrl = "https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2021-03-01"
$graphBody = @{
    subscriptions = @($subscriptionId)
    query = "resources | where isnull(tags.Environment) or isnull(tags.Owner) | project name, type, resourceGroup"
} | ConvertTo-Json -Depth 10

$graphResponse = Invoke-RestMethod -Uri $graphUrl -Headers $authHeader -Method Post -Body $graphBody
$missingTagsCount = $graphResponse.totalRecords
Write-Host "Resources missing required tags: $missingTagsCount"

# 5.5 Save Daily Snapshot to Azure Storage Table (costreports)

if ($storageConnection -and $storageConnection -ne "placeholder") {
    Write-Host "Initializing Storage Table logging..."
    
    # Extract Account Name and Key cleanly from your existing connection string string
    $accountName = $storageConnection -replace '.*AccountName=([^;]+);.*', '$1'
    $accountKey  = $storageConnection -replace '.*AccountKey=([^;]+)(;|$).*', '$1'
    $tableName   = "costreports"
    
    # Unique data row keys (Partition Key = YearMonth, Row Key = Day-Time)
    $partitionKey = (Get-Date).ToString("yyyyMM")
    $rowKey       = (Get-Date).ToString("yyyyMMdd-HHmmss")
    
    # Format the payload exactly how the Azure Table API expects it
    $entity = @{
        PartitionKey  = $partitionKey
        RowKey         = $rowKey
        ReportDate     = $yesterday
        TotalSpend     = "$totalSpend"
        UntaggedCount  = [int]$missingTagsCount
        AnomalyStatus  = $anomalyMessage
    }
    $jsonBody = $entity | ConvertTo-Json
    
    # Setup the manual endpoint and HMAC signature parameters using pure .NET
    $uri = "https://$accountName.table.core.windows.net/$tableName"
    $dateString = [DateTime]::UtcNow.ToString("R")
    
    # Build standard canonicalized string for SharedKeyLite authentication
    $stringToSign = "$dateString`n/$accountName/$tableName"
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [System.Convert]::FromBase64String($accountKey)
    $signature = [System.Convert]::ToBase64String($hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($stringToSign)))
    
    $tableHeaders = @{
        "x-ms-date"    = $dateString
        "x-ms-version" = "2019-02-02"
        "Authorization"= "SharedKeyLite $accountName`:$signature"
        "Accept"       = "application/json;odata=nometadata"
        "Content-Type" = "application/json"
    }
    
    try {
        # Shoot it up using pure built-in PowerShell web mechanics
        Invoke-RestMethod -Uri $uri -Method Post -Headers $tableHeaders -Body $jsonBody
        Write-Host "Metrics successfully logged to 'costreports' table database."
    }
    catch {
        Write-Host "⚠️ Warning: Failed to log data to storage table: $_"
    }
} else {
    Write-Host "Skipping database logging: STORAGE_CONNECTION environment variable is missing or placeholder."
}

# 6. Trigger Logic App with Report Payload
$emailPayload = @{
    reportDate = $yesterday
    totalSpend = "$totalSpend"
    anomalyStatus = $anomalyMessage
    untaggedCount = $missingTagsCount
    breakdown = $serviceBreakdown
} | ConvertTo-Json -Depth 10

if ($logicAppUrl -ne "placeholder") {
    Write-Host "Sending report to Logic App..."
    Invoke-RestMethod -Uri $logicAppUrl -Method Post -Headers @{"Content-Type"="application/json"} -Body $emailPayload
    Write-Host "Notification alert dispatched successfully."
}
