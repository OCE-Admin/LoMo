$TranscriptOutputLocation = "C:\temp\lomo.txt"

<# account info #>
$accessId = 'API-Information'
$accessKey = 'API-Information'
$company = 'APi-Information'

<# Client Info #>
$Client = 'Enter The Client Name'

<# NOC Locations #>
$SitesArrray = @("On-Prem","Azure")

<# Client Directory ID #>
$clientDir = 16

<# Client Dashboard Group #>
$dbGroup = 24

# Start session recording for errors
Start-Transcript -Path $TranscriptOutputLocation -force

# Functionize the reusable code that builds and executes the query
function Send-Request() {
    Param(
        [Parameter(position = 0, Mandatory = $true)]
        [string]$path,
        [Parameter(position = 1, Mandatory = $false)]
        [string]$httpVerb = 'GET',
        [Parameter(position = 2, Mandatory = $false)]
        [string]$queryParams,
        [Parameter(position = 3, Mandatory = $false)]
        [PSObject]$data
    )
    # Use TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    <# Construct URL #>
    $url = "https://$company.logicmonitor.com/santaba/rest$path$queryParams"
    <# Get current time in milliseconds #>
    $epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)
    <# Concatenate Request Details #>
    $requestVars = $httpVerb + $epoch + $data + $path
    <# Construct Signature #>
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [Text.Encoding]::UTF8.GetBytes($accessKey)
    $signatureBytes = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($requestVars))
    $signatureHex = [System.BitConverter]::ToString($signatureBytes) -replace '-'
    $signature = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($signatureHex.ToLower()))
    <# Construct Headers #>
    $auth = 'LMv1 ' + $accessId + ':' + $signature + ':' + $epoch
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", $auth)
    $headers.Add("Content-Type", 'application/json')
    $headers.Add("X-version", '2')
    <# Make request & retry if failed due to rate limiting #>
    $Stoploop = $false
    do {
        try {
            <# Make Request #>
            $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Body $data -Header $headers
            $Stoploop = $true
        } catch {
            switch ($_) {
                { $_.Exception.Response.StatusCode.value__ -eq 429 } {
                    Write-Host "Request exceeded rate limit, retrying in 60 seconds..."
                    Start-Sleep -Seconds 60
                    $response = Invoke-RestMethod -Uri $url -Method $httpVerb -Body $data -Header $headers
                }
                { $_.Exception.Response.StatusCode.value__ } {
                    Write-Host "Request failed, not as a result of rate limiting"
                    # Dig into the exception to get the Response details.
                    # Note that value__ is not a typo.
                    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__
                    Write-Host "StatusDescription:" $_.Exception.Response.StatusCode
                    $_.ErrorDetails.Message -match '{"errorMessage":"([\d\S\s]+)","errorCode":(\d+),'
                    Write-Host "LM ErrorMessage" $matches[1]
                    Write-Host "LM ErrorCode" $matches[2]
                    $response = $null
                    $Stoploop = $true
                }
                default {
                    Write-Host "An Unknown Exception occurred:"
                    Write-Host $_ | Format-List -Force
                $response = $null
                $Stoploop = $true
            }
        }
    }
} While ($Stoploop -eq $false)
Return $response
}
<# response size and starting offset #>
$offset = 0
$size = 50
$httpVerb = 'POST'
$resourcePath = "/device/groups/"
$queryParams = ""

try{
	Write-Host -ForegroundColor yellow "Creating Main Client Group..."
	#Main Client Group 
	$data = '{"name":"' + $Client + '","parentId":' + $clientDir + '}'
	$results = Send-Request $resourcePath $httpVerb $queryParams $data
	write $data
}

catch {
  Write-Host -ForegroundColor red "Creating Main Client Group failed:"
  Write-Host $_.ScriptStackTrace
}

Write-Host "Main Client Group created succesfully"

try{
	Write-Host -ForegroundColor yellow "Creating Devices by Type Group..."
	#Devices By Type
	$data = '{"name":"Devices by Type","parentId":'+ $results.id + '}'
	$resultsDevbyType = Send-Request $resourcePath $httpVerb $queryParams $data
}

catch {
  Write-Host -ForegroundColor red "Creating Devices by Type Group failed:"
  Write-Host $_.ScriptStackTrace
}

try{
	Write-Host -ForegroundColor yellow "Creating Offices folder..."
	#Devices By Type
	$data = '{"name":"Devices by Location","parentId":'+ $results.id + '}'
	$resultsOffices = Send-Request $resourcePath $httpVerb $queryParams $data
}

catch {
  Write-Host -ForegroundColor red "Creating Devices By Location folder failed:"
  Write-Host $_.ScriptStackTrace
}


try{
	Write-Host -ForegroundColor yellow "Creating IOS Group..."
	#Cisco IOS
	$Apply = 'isCisco() && join(system.staticgroups,\",\") =~ \"HBR Clients/' + $Client + '\" && system.sysinfo =~ \"Cisco IOS Software\"'
	$data = '{"name":"Cisco IOS","parentId":'+ $resultsDevbyType.id + ',"appliesTo":"'+ $Apply + '"}'
	$resultsCiscoios = Send-Request $resourcePath $httpVerb $queryParams $data
}

catch {
  Write-Host -ForegroundColor red "Creating IOS Group failed:"
  Write-Host $_.ScriptStackTrace
}


try{
	Write-Host -ForegroundColor yellow "Creating Dead Devices Group..."
	#Dead Devices
	$Apply = 'system.hoststatus == \"dead\" && join(system.staticgroups,\",\") =~ \"HBR Clients/' + $Client + '\"'
	$data = '{"name":"Dead Devices","parentId":'+ $resultsDevbyType.id + ',"appliesTo":"'+ $Apply + '"}'
	$resultsDeaddevices = Send-Request $resourcePath $httpVerb $queryParams $data
}

catch {
  Write-Host -ForegroundColor red "Creating Dead Devices Group failed:"
  Write-Host $_.ScriptStackTrace
}


try{
	Write-Host -ForegroundColor yellow "Creating Collector Group..."
	#Collectors
	$Apply = 'isCollectorDevice() && join(system.staticgroups,\",\") =~ \"HBR Clients/' + $Client + '\"'
	$data = '{"name":"Collectors","parentId":'+ $resultsDevbyType.id + ',"appliesTo":"'+ $Apply + '"}'
	$resultsCollectors = Send-Request $resourcePath $httpVerb $queryParams $data
}

catch {
  Write-Host -ForegroundColor red "Creating Collector Group failed:"
  Write-Host $_.ScriptStackTrace
}

try{
	Write-Host -ForegroundColor yellow "Creating Storage Group..."
	#Collectors
	$Apply = 'isStorage() && join(system.staticgroups,\",\") =~ \"HBR Clients/' + $Client + '\"'
	$data = '{"name":"Storage","parentId":'+ $resultsDevbyType.id + ',"appliesTo":"'+ $Apply + '"}'
	$resultsStorage = Send-Request $resourcePath $httpVerb $queryParams $data
}

catch {
  Write-Host -ForegroundColor red "Creating Storage Group failed:"
  Write-Host $_.ScriptStackTrace
}

try{
	Write-Host -ForegroundColor yellow "Creating DC Group..."
	#Domain Controller
	$Apply = 'hasCategory(\"MicrosoftDomainController\") && join(system.staticgroups,\",\") =~ \"HBR Clients/' + $Client + '\"'
	$data = '{"name":"Domain Controller","parentId":'+ $resultsDevbyType.id + ',"appliesTo":"'+ $Apply + '"}'
	$resultsDCs = Send-Request $resourcePath $httpVerb $queryParams $data
}

catch {
  Write-Host -ForegroundColor red "Creating DC Group failed:"
  Write-Host $_.ScriptStackTrace
}

try{
	Write-Host -ForegroundColor yellow "Creating ASA Group..."
	#Cisco ASA
	$Apply = 'hasCategory(\"CiscoASA\") && join(system.staticgroups,\",\") =~ \"HBR Clients/' + $Client + '\"'
	$data = '{"name":"Cisco ASA","parentId":'+ $resultsDevbyType.id + ',"appliesTo":"'+ $Apply + '"}'
	$resultsCiscoasa = Send-Request $resourcePath $httpVerb $queryParams $data
}

catch {
  Write-Host -ForegroundColor red "Creating ASA Group failed:"
  Write-Host $_.ScriptStackTrace
}

try{
	Write-Host -ForegroundColor yellow "Creating Exchange Group..."
	#Exchange Servers
	$Apply = '(hasCategory(\"MSExchange\") || hasCategory(\"MicrosoftExchange2013\") || hasCategory(\"MicrosoftExchange2016\")) && join(system.staticgroups,\",\") =~ \"HBR Clients/' + $Client + '\"'
	$data = '{"name":"Exchange Servers","parentId":'+ $resultsDevbyType.id + ',"appliesTo":"'+ $Apply + '"}'
	$resultsExchange = Send-Request $resourcePath $httpVerb $queryParams $data
}

catch {
  Write-Host -ForegroundColor red "Creating Exchange Group failed:"
  Write-Host $_.ScriptStackTrace
}

try{
	Write-Host -ForegroundColor yellow "Creating HyperV Group..."
	#Hyper-V
	$Apply = 'hasCategory(\"HyperV\") && join(system.staticgroups,\",\") =~ \"HBR Clients/' + $Client + '\"'
	$data = '{"name":"Hyper-V","parentId":'+ $resultsDevbyType.id + ',"appliesTo":"'+ $Apply + '"}'
	$resultsHyperv = Send-Request $resourcePath $httpVerb $queryParams $data
}

catch {
  Write-Host -ForegroundColor red "Creating HyperV Group failed:"
  Write-Host $_.ScriptStackTrace
}

try{
	Write-Host -ForegroundColor yellow "Creating Linux Sever Group..."
	#Linux Servers
	$Apply = 'isLinux() && join(system.staticgroups,\",\") =~ \"HBR Clients/' + $Client + '\"'
	$data = '{"name":"Linux Servers","parentId":'+ $resultsDevbyType.id + ',"appliesTo":"'+ $Apply + '"}'
	$resultsLinuxservers = Send-Request $resourcePath $httpVerb $queryParams $data
}

catch {
  Write-Host -ForegroundColor red "Creating Linux Sever Group failed:"
  Write-Host $_.ScriptStackTrace
}

try{
	Write-Host -ForegroundColor yellow "Creating minmon Group..."
	#Minimal Monitoring
	$Apply = 'isMinMon() && join(system.staticgroups,\",\") =~ \"HBR Clients/' + $Client + '\"'
	$data = '{"name":"Minimal Monitoring","parentId":'+ $resultsDevbyType.id + ',"appliesTo":"'+ $Apply + '"}'
	$resultsMinmon = Send-Request $resourcePath $httpVerb $queryParams $data
}

catch {
  Write-Host -ForegroundColor red "Creating minmon Group failed:"
  Write-Host $_.ScriptStackTrace
}

try{
	Write-Host -ForegroundColor yellow "Creating network Group..."
	#Network
	$Apply = 'isNetwork() && join(system.staticgroups,\",\") =~ \"HBR Clients/' + $Client + '\"'
	$data = '{"name":"Network","parentId":'+ $resultsDevbyType.id + ',"appliesTo":"'+ $Apply + '"}'
	$resultsNetwork = Send-Request $resourcePath $httpVerb $queryParams $data
}

catch {
  Write-Host -ForegroundColor red "Creating network Group failed:"
  Write-Host $_.ScriptStackTrace
}

try{
	Write-Host -ForegroundColor yellow "Creating PA Group..."
	#PaloAlto
	$Apply = 'sysinfo =~ \"Palo Alto\" && join(system.staticgroups,\",\") =~ \"HBR Clients/' + $Client + '\"'
	$data = '{"name":"PaloAlto","parentId":'+ $resultsDevbyType.id + ',"appliesTo":"'+ $Apply + '"}'
	$resultsPa = Send-Request $resourcePath $httpVerb $queryParams $data
}

catch {
  Write-Host -ForegroundColor red "Creating PA Group failed:"
  Write-Host $_.ScriptStackTrace
}

try{
	Write-Host -ForegroundColor yellow "Creating SQL Group..."
	#SQL Servers
	$Apply = 'hasCategory(\"MSSQL\") && join(system.staticgroups,\",\") =~ \"HBR Clients/' + $Client + '\"'
	$data = '{"name":"SQL Servers","parentId":'+ $resultsDevbyType.id + ',"appliesTo":"'+ $Apply + '"}'
	$resultsSqlserver = Send-Request $resourcePath $httpVerb $queryParams $data
}

catch {
  Write-Host -ForegroundColor red "Creating SQL Group failed:"
  Write-Host $_.ScriptStackTrace
}

try{
	Write-Host -ForegroundColor yellow "Creating ESXi Group..."
	#VMware ESXi Hosts
	$Apply = 'system.virtualization =~ \"VMware ESX host\"  && join(system.staticgroups,\",\") =~ \"HBR Clients/' + $Client + '\"'
	$data = '{"name":"VMware ESXi Hosts","parentId":'+ $resultsDevbyType.id + ',"appliesTo":"'+ $Apply + '"}'
	$resultsEsxi = Send-Request $resourcePath $httpVerb $queryParams $data
}

catch {
  Write-Host -ForegroundColor red "Creating ESXi Group failed:"
  Write-Host $_.ScriptStackTrace
}

try{
	Write-Host -ForegroundColor yellow "Creating vCenter Group..."
	#VMware vCenters
	$Apply = 'system.virtualization =~ \"VMware ESX vcenter\" && join(system.staticgroups,\",\") =~ \"HBR Clients/' + $Client + '\"'
	$data = '{"name":"VMware vCenters","parentId":'+ $resultsDevbyType.id + ',"appliesTo":"'+ $Apply + '"}'
	$resultsVcenter = Send-Request $resourcePath $httpVerb $queryParams $data
}

catch {
  Write-Host -ForegroundColor red "Creating vCenter Group failed:"
  Write-Host $_.ScriptStackTrace
}

try{
	Write-Host -ForegroundColor yellow "Creating Windows Server Group..."
	#Windows Servers
	$Apply = 'isWindows() && join(system.staticgroups,\",\") =~ \"HBR Clients/' + $Client + '\"'
	$data = '{"name":"Windows Servers","parentId":'+ $resultsDevbyType.id + ',"appliesTo":"'+ $Apply + '"}'
	$resultsWinserver = Send-Request $resourcePath $httpVerb $queryParams $data
}

catch {
  Write-Host -ForegroundColor red "Creating Windows Server Group failed:"
  Write-Host $_.ScriptStackTrace
}


try{
	Write-Host -ForegroundColor yellow "Creating static location groups..."
	<# Static Groups creation Loop through Locations #>
	foreach ($Site in $SitesArrray){
		#Main Location Group 
		$data = '{"name":"' + $Site + '","parentId":' + $resultsoffices.id + '}'
		$resultsLocation = Send-Request $resourcePath $httpVerb $queryParams $data
		Write-host $data
	}
}

catch {
  Write-Host -ForegroundColor red "Creating static location groups failed:"
  Write-Host $_.ScriptStackTrace
}

try{
	Write-Host -ForegroundColor yellow "Creating Dashboard group with widget..."
	# Add Dashboad Group with Widget Token
	$resourcePath = "/dashboard/groups"
	$queryParams = ""
	$data = '{"name":"' + $Client + '","parentId":' + $dbGroup + ',"widgetTokens":[{"name":"defaultResourceGroup","value":"HBR Clients/' + $Client + '"}]}'
	Write-Host $data
	$resultsDashboards = Send-Request $resourcePath $httpVerb $queryParams $data
}

catch {
  Write-Host -ForegroundColor red "Creating Dashboard group with widget failed:"
  Write-Host $_.ScriptStackTrace
}

try{
	Write-Host -ForegroundColor yellow "Creating Report Group..."
	# Add Report Group
	$resourcePath = "/report/groups"
	$queryParams = ""
	$data = '{"name":"' + $Client + '"}'
	Write-Host $data
	$resultsReport = Send-Request $resourcePath $httpVerb $queryParams $data
}

catch {
  Write-Host -ForegroundColor red "Creating Report Group failed:"
  Write-Host $_.ScriptStackTrace
}


try{
	Write-Host -ForegroundColor yellow "Creating 24h Alerts report..."
	# Add Report Group
	$resourcePath = "/report/reports"
	$queryParams = ""
	$data = '{"type":"Alert","groupId":' + $resultsReport.id + ',"name":"All ' + $Client + ' Alerts by Severity - Last 24 hours","description":"All Alerts from the past 24 hour period sorted by Severity","format":"HTML","reportLinkExpire":"High Flexibility","dateRange":"Last 24 hours","sortedBy":"level","sortedDirection":"desc","includePreexist":false,"summaryOnly":false,"groupFullPath":"HBR Clients/' + $Client + '*","deviceDisplayName":"*","dataSource":"*","dataSourceInstanceName":"*","dataPoint":"*","ackFilter":"all","sdtFilter":"all","activeOnly":true,"level":"all","rule":"*","chain":"*","columns":[{"name":"Severity","isHidden":false},{"name":"Group","isHidden":false},{"name":"Device","isHidden":false},{"name":"Datasource","isHidden":false},{"name":"Instance","isHidden":false},{"name":"Datapoint","isHidden":false},{"name":"Thresholds","isHidden":false},{"name":"Value","isHidden":false},{"name":"Began","isHidden":false},{"name":"End","isHidden":false},{"name":"Rule","isHidden":false},{"name":"Chain","isHidden":false},{"name":"Acked","isHidden":false},{"name":"Acked By","isHidden":false},{"name":"Acked On","isHidden":false},{"name":"Notes","isHidden":false},{"name":"In SDT","isHidden":false}],"delivery":"none"}'
	Write-Host $data
	$resultsAlertsreporta = Send-Request $resourcePath $httpVerb $queryParams $data
	
}

catch{
	Write-Host -ForegroundColor red "Creating 24h Alerts report failed:"
	Write-Host $_.ScriptStackTrace
}

try{
	Write-Host -ForegroundColor yellow "Creating Alert Summary 7 days report..."
	# Add Report Group
	$resourcePath = "/report/reports"
	$queryParams = ""
	$data = '{"type":"Alert","groupId":' + $resultsReport.id + ',"name":"' + $Client + ' Alert Sumary  - Last 7 days","description":"Creates a report with a count of alerts generated over the previous 7 days","format":"HTML","reportLinkExpire":"High Flexibility","dateRange":"Last 7 days","sortedBy":"count","sortedDirection":"desc","includePreexist":true,"summaryOnly":true,"groupFullPath":"HBR Clients/' + $Client +'*","deviceDisplayName":"*","dataSource":"*","dataSourceInstanceName":"*","dataPoint":"*","ackFilter":"all","sdtFilter":"all","activeOnly":true,"level":"all","rule":"*","chain":"*","columns":[{"name":"Alerts","isHidden":false},{"name":"Group","isHidden":false},{"name":"Device","isHidden":false},{"name":"Datasource","isHidden":false},{"name":"Instance","isHidden":false},{"name":"Datapoint","isHidden":false}],"delivery":"none"}'
	Write-Host $data
	$resultsAlertssummary = Send-Request $resourcePath $httpVerb $queryParams $data
	
}

catch{
	Write-Host -ForegroundColor red "Creating Alert Summary 7 days report failed:"
	Write-Host $_.ScriptStackTrace
}



try{
	Write-Host -ForegroundColor yellow "Creating Website Group..."
	# Add a Website Group
	$resourcePath = "/website/groups"
	$queryParams = ""
	$data = '{"parentId":"2","stopMonitoring":false,"disableAlerting":false,"name":"' + $Client + '","description":"","parentGroup":"Clients","properties":[],"testLocation":{"all":false,"smgIds":[2,4,3,5,6]}}'
	Write-Host $data
	$resultsWebsitegroup = Send-Request $resourcePath $httpVerb $queryParams $data
}

catch {
  Write-Host -ForegroundColor red "Creating Website Group failed:"
  Write-Host $_.ScriptStackTrace
}

try{
	Write-Host -ForegroundColor yellow "Creating Collector Group..."
	# Add a Collector Group
	$resourcePath = "/setting/collector/groups"
	$queryParams = ""
	$data = '{"autoBalance":false,"name":"' + $Client + '","description":"","customProperties":[]}'
	Write-Host $data
	$resultsCollectorgroup = Send-Request $resourcePath $httpVerb $queryParams $data
}

catch {
  Write-Host -ForegroundColor red "Creating Collector Group failed:"
  Write-Host $_.ScriptStackTrace
}

try{
	Write-Host -ForegroundColor yellow "Creating Netscan Group..."
	#Add Netscan Group
	$resourcePath = "/setting/netscans/groups"
	$queryParams = ""
	$data = '{"name":"' + $Client + '","description":""}'
	Write-Host $data
	$resultsNetscansgroup = Send-Request $resourcePath $httpVerb $queryParams $data
}

catch {
  Write-Host -ForegroundColor red "Creating Netscan Group failed:"
  Write-Host $_.ScriptStackTrace
}

Write-Host $total
Write-Host $items