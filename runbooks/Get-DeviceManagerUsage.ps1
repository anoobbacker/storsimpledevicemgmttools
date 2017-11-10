<#
.DESCRIPTION
    This scipt lists StorSimple device manager and usages of the devices under the manager.

    Steps to execute the script (https://aka.ms/ss8000-azure-automation):
    --------------------------------------------------------------------
    1.  Open powershell, create a new folder & change directory to the folder.
            mkdir C:\scripts\StorSimpleSDKTools
            cd C:\scripts\StorSimpleSDKTools
    
    2.  Download nuget CLI under the same folder in Step1.
        Various versions of nuget.exe are available on nuget.org/downloads. Each download link points directly to an .exe file, so be sure to right-click and save the file to your computer rather than running it from the browser. 
            wget https://dist.nuget.org/win-x86-commandline/latest/nuget.exe -Out C:\scripts\StorSimpleSDKTools\nuget.exe
    
    3.  Download the dependent SDK
            C:\scripts\StorSimpleSDKTools\nuget.exe install Microsoft.Azure.Management.Storsimple8000series
            C:\scripts\StorSimpleSDKTools\nuget.exe install Microsoft.IdentityModel.Clients.ActiveDirectory -Version 2.28.3
            C:\scripts\StorSimpleSDKTools\nuget.exe install Microsoft.Rest.ClientRuntime.Azure.Authentication -Version 2.2.9-preview
    
    4.  Download the script from github. 
            wget https://raw.githubusercontent.com/anoobbacker/storsimpledevicemgmttools/master/Get-DeviceManagerUsage.ps1 -Out Get-DeviceManagerUsage.ps1
     
    5. Create an Azure automation account with Azure RunAs Account. Refer https://docs.microsoft.com/azure/automation/automation-create-standalone-account. 
    
        If you've an existing Azure automation account configure the Azure RunAs Account, refer https://docs.microsoft.com/azure/automation/automation-create-runas-account.

    6. Create an Azure Automation Runbook Module for StorSimple 8000 Series device management. Use the below commands to create a Automation module zip file.

            # set path variables
            $downloadDir = "C:\scripts\StorSimpleSDKTools"
            $moduleDir = "$downloadDir\AutomationModule\Microsoft.Azure.Management.StorSimple8000Series"

            #don't change the folder name "Microsoft.Azure.Management.StorSimple8000Series"
            mkdir "$moduleDir"
            copy "$downloadDir\Microsoft.IdentityModel.Clients.ActiveDirectory.2.28.3\lib\net45\Microsoft.IdentityModel.Clients.ActiveDirectory*.dll" $moduleDir
            copy "$downloadDir\Microsoft.Rest.ClientRuntime.Azure.3.3.7\lib\net452\Microsoft.Rest.ClientRuntime.Azure*.dll" $moduleDir
            copy "$downloadDir\Microsoft.Rest.ClientRuntime.2.3.8\lib\net452\Microsoft.Rest.ClientRuntime*.dll" $moduleDir
            copy "$downloadDir\Newtonsoft.Json.6.0.8\lib\net45\Newtonsoft.Json*.dll" $moduleDir
            copy "$downloadDir\Microsoft.Rest.ClientRuntime.Azure.Authentication.2.2.9-preview\lib\net45\Microsoft.Rest.ClientRuntime.Azure.Authentication*.dll" $moduleDir
            copy "$downloadDir\Microsoft.Azure.Management.Storsimple8000series.1.0.0\lib\net452\Microsoft.Azure.Management.Storsimple8000series*.dll" $moduleDir

            #Don't change the name of the Archive
            compress-Archive -Path "$moduleDir" -DestinationPath Microsoft.Azure.Management.StorSimple8000Series.zip

    7. Import the Azure Automation module zip file (Microsoft.Azure.Management.StorSimple8000Series.zip) created in above step. This can be done by selecting the Automation Account, click "Modules" under SHARED RESOURCES and then click "Add a module". 

    8. Import the runbook script (Get-DeviceManagerUsage.ps1) as a Azure Automation Powershell runbook script, publish & execute it.

    9. Use below commands to create Variable assets & Credential asset in Azure Automation

            $SubscriptionId = "[sub-id]"
            $ResourceGroupName = "[res-group-name]"
            $AutomationAccountName = "[automation-acc-name]"
            $ManagerName = "[device-manager-name]"
            $FilterByStartTime = "[filter-start-time]"
            $FilterByEndTime = "[filter-end-time]"
            $IsMailRequired = $true
            $MailSmtpServer = "[server-name]"
            $MailToAddress = "[to-email-address]"
            $MailSubject = "[subject-name]"
            $Creds = Get-Credential -Message "Enter the SMTP user log-in credentials"

            Login-AzureRmAccount 
            Set-AzureRmContext -SubscriptionId "$SubscriptionId"
            New-AzureRmAutomationVariable -Encrypted $false -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name "ResourceGroupName" -Value "$ResourceGroupName"
            New-AzureRmAutomationVariable -Encrypted $false -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name "ManagerName" -Value "$ManagerName"
            
            New-AzureRmAutomationVariable -Encrypted $false -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name "FilterByStartTime" -Value "$FilterByStartTime"
            New-AzureRmAutomationVariable -Encrypted $false -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name "FilterByEndTime" -Value "$FilterByEndTime"
            
            # e-mail related variables
            New-AzureRmAutomationVariable -Encrypted $false -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name "IsMailRequired" -Value "$IsMailRequired"
            New-AzureRmAutomationVariable -Encrypted $false -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name "Mail-SMTPServer" -Value "$MailSmtpServer"
            New-AzureRmAutomationVariable -Encrypted $false -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name "Mail-ToAddress" -Value "$MailToAddress"
            New-AzureRmAutomationVariable -Encrypted $false -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name "Mail-Subject" -Value "$MailSubject"
            New-AzureRmAutomationCredential -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name "Mail-Credential" -Value $Creds

     ----------------------------
.PARAMS

    ResourceGroupName: Input the name of the resource group on which to create/update the volume.
    ManagerName: Input the name of the resource (StorSimple device manager) on which to create/update the volume.

    FilterByStartTime: Input the start time of the capacity utilization. Eg: (Get-Date -Date "2017-01-01 10:30")
    FilterByEndTime: Input the end time of the capacity utilization. Eg: (Get-Date -Date "2017-01-01 10:30")

    IsMailRequired: Input the ismailrequired arg as $true if you want to receive the results. Possible values [$true/$false]
    Mail-Credential (Optional): Input a user account that has permission to perform this action.
    Mail-SMTPServer (Optional): Input the name of the SMTP server that sends the email message.
    Mail-ToAddress (Optional): Input the addresses to which the mail is sent.
                    If you have multiple addresses, then add addresses as a comma-separated string, such as someone@example.com,someone@example.com
    Mail-Subject (Optional): Input the subject of the email message.
#>

if (!(Get-Command Get-AutomationConnection -ErrorAction SilentlyContinue))
{
    throw "You cannot running the script in an Windows Powershell. Import this into Azure automation account and execute."  
}

$ResourceGroupName = Get-AutomationVariable -Name "ResourceGroupName" 
if ($ResourceGroupName -eq $null) 
{ 
    throw "The ResourceGroupName asset has not been created in the Automation service."  
}
    
$ManagerName = Get-AutomationVariable -Name "ManagerName" 
if ($ManagerName -eq $null) 
{ 
    throw "The ManagerName asset has not been created in the Automation service."
}
    
$FilterByStartTime = Get-AutomationVariable -Name "FilterByStartTime" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($FilterByStartTime))
{ 
    $FilterByStartTime = (get-date).AddDays(-1)
}
    
$FilterByEndTime = Get-AutomationVariable -Name "FilterByEndTime" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($FilterByEndTime))
{ 
    $FilterByEndTime = (get-date)
}

$IsMailRequired = Get-AutomationVariable -Name "IsMailRequired" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($IsMailRequired)) 
{ 
    throw "The IsMailRequired asset has not been created in the Automation service."  
}

$Mail_SMTPServer = Get-AutomationVariable -Name "Mail-SMTPServer" -ErrorAction SilentlyContinue
if ($IsMailRequired -and [string]::IsNullOrEmpty($Mail_SMTPServer)) 
{ 
    throw "The Mail-SMTPServer asset has not been created in the Automation service."  
}

$Mail_ToAddress = Get-AutomationVariable -Name "Mail-ToAddress" -ErrorAction SilentlyContinue
if ($IsMailRequired -and [string]::IsNullOrEmpty($Mail_ToAddress))
{
    throw "The Mail-ToAddress asset has not been created in the Automation service."
}

$Mail_Subject = Get-AutomationVariable -Name "Mail-Subject" -ErrorAction SilentlyContinue
if ($IsMailRequired -and [string]::IsNullOrEmpty($Mail_Subject))
{
    throw "The Mail-Subject asset has not been created in the Automation service."
}

$Mail_Credential = Get-AutomationPSCredential -Name "Mail-Credential" -ErrorAction SilentlyContinue
if ($IsMailRequired -and [string]::IsNullOrEmpty($Mail_Credential))
{
    throw "The Mail-Credential asset has not been created in the Automation service."
}

$ClientCertificate = Get-AutomationCertificate -Name "AzureRunAsCertificate"
if ($ClientCertificate -eq $null)
{
    throw "The AzureRunAsCertificate asset has not been created in the Automation service."
}

$ServicePrincipalConnection = Get-AutomationConnection -Name "AzureRunAsConnection"
if ($ServicePrincipalConnection -eq $null)
{
    throw "The AzureRunAsConnection asset has not been created in the Automation service."
}

# Set Token Url
$TokenUrl = "https://management.azure.com" #Run '(Get-AzureRmEnvironment).ResourceManagerUrl' get the Fairfax url.

# Get service principal details
$SubscriptionId = $ServicePrincipalConnection.SubscriptionId
if ($SubscriptionId -eq $null) {
   throw "Could not retrieve subscription."
}

$TenantId = $ServicePrincipalConnection.TenantId
if ($TenantId -eq $null) {
   throw "Could not retrieve TenantId."
}

$ClientId = $ServicePrincipalConnection.ApplicationId
if ($TenantId -eq $null) {
   throw "Could not retrieve ApplicationId."
}

if ($IsMailRequired)
{
    # Get from address 
    $Mail_FromAddress = $Mail_Credential.UserName
    $Mail_Subject = $Mail_Subject + " " + (Get-Date -Format "dd-MMM-yyyy")
    $Mail_ToAddress = $Mail_ToAddress -split ','
}

# Set Current directory path
$ScriptDirectory = "C:\Modules\User\Microsoft.Azure.Management.StorSimple8000Series"
#ls $ScriptDirectory

# Load all dependent dlls
[Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Microsoft.IdentityModel.Clients.ActiveDirectory.dll")) | Out-Null
[Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Microsoft.Rest.ClientRuntime.Azure.dll")) | Out-Null
[Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Microsoft.Rest.ClientRuntime.dll")) | Out-Null
[Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Newtonsoft.Json.dll")) | Out-Null
[Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Microsoft.Rest.ClientRuntime.Azure.Authentication.dll")) | Out-Null
[Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Microsoft.Azure.Management.Storsimple8000series.dll")) | Out-Null

Function GenerateCapacityFilter() {
    param([DateTime] $FilterByStartTime, [DateTime] $FilterByEndTime)
    $queryFilter = $null
    if ($FilterByStartTime -ne $null) {
        $queryFilter = "startTime ge '$($FilterByStartTime.ToString('r'))'"
    }

    if($FilterByEndTime -ne $null) {
        if(![string]::IsNullOrEmpty($queryFilter)) {
            $queryFilter += " and "
        }
        $queryFilter += "endTime  le '$($FilterByEndTime.ToString('r'))'"
    }

    if(![string]::IsNullOrEmpty($queryFilter)) {
        $queryFilter += " and timeGrain eq 'PT1H' and category eq 'CapacityUtilization'"
    } else {
        $queryFilter += "timeGrain eq 'PT1H' and category eq 'CapacityUtilization'"
    }

    return $queryFilter
}

Function Convert-Value {
    param(      
        [validateset("Bytes","KB","MB","GB","TB")]            
        [String]$To,            
        [Parameter(Mandatory=$true)]            
        [double]$Value,            
        [int]$Precision = 1
    )

    switch ($To) {            
        "Bytes" {return $Value}            
        "KB" {$Value = $Value/1KB}
        "MB" {$Value = $Value/1MB}            
        "GB" {$Value = $Value/1GB}            
        "TB" {$Value = $Value/1TB}                
    }

    return [Math]::Round($Value,$Precision,[MidPointRounding]::AwayFromZero)
}

Function Convert-Size {
    param(
        [validateset("Bytes","KB","MB","GB","TB")]          
        [String]$From,           
        [Parameter(Mandatory=$true)]            
        [double]$Value,            
        [int]$Precision = 1            
    )            
    switch($From) {            
        "Bytes" {$value = $Value }            
        "KB" {$value = $Value * 1024 }            
        "MB" {$value = $Value * 1024 * 1024}            
        "GB" {$value = $Value * 1024 * 1024 * 1024}            
        "TB" {$value = $Value * 1024 * 1024 * 1024 * 1024}            
    }            
    
    $tUnit = "TB"
    $tValue = Convert-Value $tUnit $value
    if ( $tValue -eq 0 ) {
        $tUnit = "GB"
        $tValue = Convert-Value $tUnit $value $Precision
    }
    if ( $tValue -eq 0 ) {
        $tUnit = "MB"
        $tValue = Convert-Value $tUnit $value $Precision
    }
    if ( $tValue -eq 0 ) {
        $tUnit = "KB"
        $tValue = Convert-Value $tUnit $value $Precision
    }
    if ( $tValue -eq 0 ) {
        $tUnit = "Bytes"
        $tValue = Convert-Value $tUnit $value $Precision
    }        

    return "$tValue $tUnit"
}


$SyncContext = New-Object System.Threading.SynchronizationContext
[System.Threading.SynchronizationContext]::SetSynchronizationContext($SyncContext)

$TokenUri = New-Object System.Uri -ArgumentList $TokenUrl

# Instantiate clientAssertionCertificate
$clientAssertionCertificate = New-Object Microsoft.IdentityModel.Clients.ActiveDirectory.ClientAssertionCertificate -ArgumentList $ClientId, $ClientCertificate

# Verify Credentials
Write-Output "Connecting to Azure"
$Credentials = [Microsoft.Rest.Azure.Authentication.ApplicationTokenProvider]::LoginSilentWithCertificateAsync($TenantId, $clientAssertionCertificate).GetAwaiter().GetResult()

if ($Credentials -eq $null) {
    throw "Failed to authenticate!"
}

# Get StorSimpleClient instance
$StorSimpleClient = New-Object Microsoft.Azure.Management.StorSimple8000Series.StorSimple8000SeriesManagementClient -ArgumentList $TokenUri, $Credentials

# Set SubscriptionId
$StorSimpleClient.SubscriptionId = $SubscriptionId

# Get backups by Device
try {
    #Generate query filter for the metrics.
    $BackupQuery = GenerateCapacityFilter $FilterByStartTime $FilterByEndTime    
    $oDataQuery = New-Object Microsoft.Rest.Azure.OData.ODataQuery[Microsoft.Azure.Management.StorSimple8000Series.Models.MetricFilter] -ArgumentList $BackupQuery

    #Get the metrics values
    $Metrics = [Microsoft.Azure.Management.StorSimple8000Series.ManagersOperationsExtensions]::ListMetrics($StorSimpleClient.Managers, $oDataQuery, $ResourceGroupName, $ManagerName)

    # Print usage
    if ($Metrics -ne $null -and $Metrics.Length -gt 0) {
        #Metrics: PrimaryStorageTieredUsed, PrimaryStorageLocallyPinnedUsed, CloudStorageUsed
        foreach ($Metric in $Metrics) 
        {
            $MetricsName =$Metric.Name.Value
            $MetricsDisplayName = $Metric.Name.LocalizedValue
            $MetricsCount = $Metric.Values.Count
            $LatestMetricsValue = $Metric.Values[$MetricsCount-1].Maximum
            $DisplayUsageValue = Convert-Size "Bytes" $LatestMetricsValue
            PrettyWriter "Latest $MetricsDisplayName - $DisplayUsageValue"
        }
    } else {
        Write-Error "No metric(s) available."
    }

    $Devices = [Microsoft.Azure.Management.StorSimple8000Series.DevicesOperationsExtensions]::ListByManager($StorSimpleClient.Devices, $ResourceGroupName, $ManagerName)
    # Print device usage
    
    $DeviceUsageStats = @()
    if ($Devices -ne $null -and $Devices.Length -gt 0) {
        #Usage fields: AvailableLocalStorageInBytes, AvailableTieredStorageInBytes, ProvisionedTieredStorageInBytes, ProvisionedLocalStorageInBytes, ProvisionedVolumeSizeInBytes, UsingStorageInBytes, TotalTieredStorageInBytes
        foreach ($Device in $Devices)
        {
            $AvailableLocalStorage = Convert-Size "Bytes"  $Device.AvailableLocalStorageInBytes
            $AvailableTieredStorage = Convert-Size "Bytes" $Device.AvailableTieredStorageInBytes
            $RemainingLocalStorageBytes = ($Device.AvailableLocalStorageInBytes - $Device.UsingStorageInBytes)
            $RemainingLocalStorage = Convert-Size "Bytes" $RemainingLocalStorageBytes
            $ProvisionedTieredStorage = Convert-Size "Bytes" $Device.ProvisionedTieredStorageInBytes
            $ProvisionedLocalStorage = Convert-Size "Bytes" $Device.ProvisionedLocalStorageInBytes
            $ProvisionedVolumeSize = Convert-Size "Bytes" $Device.ProvisionedVolumeSizeInBytes
            $UsingStorage = Convert-Size "Bytes" $Device.UsingStorageInBytes            
            $object = New-Object System.Object
            $object | Add-Member -Type NoteProperty -Name "Device Name" -Value $Device.Name            
            #StorSimple cloud appliances (8010/8020) doesn't support locally-pinned volumes.
            if ( $Device.ModelDescription -ne "8010" -and $Device.ModelDescription -ne "8020" ) {
                $object | Add-Member -Type NoteProperty -Name "Available" -Value "Local=$AvailableLocalStorage Or Tiered=$AvailableTieredStorage"  
            } else {
                $object | Add-Member -Type NoteProperty -Name "Available" -Value "Tiered=$AvailableTieredStorage"     
            }


            #Provisioned Tiered Storage
            $object | Add-Member -Type NoteProperty -Name "Prov. Tiered" -Value "$ProvisionedTieredStorage"
            
            #StorSimple cloud appliances (8010/8020) doesn't support locally-pinned volumes.
            #Provisioned Local Storage
            if ( $Device.ModelDescription -ne "8010" -and $Device.ModelDescription -ne "8020" ) {
                $object | Add-Member -Type NoteProperty -Name "Prov. Local" -Value "$ProvisionedLocalStorage"
            } else {
                $object | Add-Member -Type NoteProperty -Name "Prov. Local" -Value "-"
            }
            
            $object | Add-Member -Type NoteProperty -Name "Prov. Volume" -Value "$ProvisionedVolumeSize"
            $object | Add-Member -Type NoteProperty -Name "Usage" -Value "$UsingStorage"
            
            if ( $Device.ModelDescription -eq "8100" ) {
                #$MaximumCapacityBytes = 200 * 1024 * 1024 * 1024 * 1024
                $object | Add-Member -Type NoteProperty -Name "Max" -Value "200 TB"                
            } elseif ( $Device.ModelDescription -eq "8600" ) {
                #$MaximumCapacityBytes = 500 * 1024 * 1024 * 1024 * 1024
                $object | Add-Member -Type NoteProperty -Name "Max" -Value "500 TB"
            } elseif ( $Device.ModelDescription -eq "8010" ) {
                #$MaximumCapacityBytes = 30 * 1024 * 1024 * 1024 * 1024
                $object | Add-Member -Type NoteProperty -Name "Max" -Value "30 TB"
            } elseif ( $Device.ModelDescription -eq "8020" ) {
                #$MaximumCapacityBytes = 64 * 1024 * 1024 * 1024 * 1024
                $object | Add-Member -Type NoteProperty -Name "Max" -Value "64 TB"
            } else {
                $object | Add-Member -Type NoteProperty -Name "Max" -Value "-"
            }
            $DeviceUsageStats += $object  
        }
    } else {
        Write-Error "No device(s) available."
    }    
}
catch {
    # Print error details
    Write-Error $_.Exception.Message
    break
}

if ($IsMailRequired)
{
    # Send a mail
    $Mail_Body = ($DeviceUsageStats | ConvertTo-Html | Out-String)
    $Mail_Body = $Mail_Body -replace "<head>", "<head><style>body{font-family: 'Segoe UI',Arial,sans-serif; color: #366EC4; font-size: 13px;}table { border-right: 1px solid #434343;  border-top: 1px solid #434343; } th, td { border-left: 1px solid #434343; border-bottom: 1px solid #434343; padding: 5px 5px; }</style>"
    $Mail_Body = $Mail_Body -replace "<table>", "<table cellspacing='0' cellpadding='0' width='700px'>"

    Write-Output "Attempting to send a status mail"
    Send-MailMessage -Credential $Mail_Credential -From $Mail_FromAddress -To $Mail_ToAddress -Subject $Mail_Subject -SmtpServer $Mail_SMTPServer -Body $Mail_Body -BodyAsHtml:$true -UseSsl
    Write-Output "Mail sent successfully"
}

# Print result
Write-Output "StorSimple Device Usage details"
$DeviceUsageStats | Format-Table -Auto
