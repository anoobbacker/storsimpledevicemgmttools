<#
.DESCRIPTION
    This Azure Automation Runbook powershell scipt reports the status of all backup jobs.
    
    Steps to execute the script (https://aka.ms/ss8000-azure-automation):
    --------------------------------------------------------------------
    1.  Open powershell, create a new folder & change directory to the folder.
            mkdir C:\scripts\StorSimpleSDKTools
            cd C:\scripts\StorSimpleSDKTools
    
    2.  Download nuget CLI under the same folder in Step1.
        Various versions of nuget.exe are available on nuget.org/downloads. Each download link points directly to an .exe file, 
        so be sure to right-click and save the file to your computer rather than running it from the browser. 
            wget https://dist.nuget.org/win-x86-commandline/latest/nuget.exe -Out C:\scripts\StorSimpleSDKTools\nuget.exe
    
    3.  Download the dependent SDK
            C:\scripts\StorSimpleSDKTools\nuget.exe install Microsoft.Azure.Management.Storsimple8000series
            C:\scripts\StorSimpleSDKTools\nuget.exe install Microsoft.IdentityModel.Clients.ActiveDirectory -Version 2.28.3
            C:\scripts\StorSimpleSDKTools\nuget.exe install Microsoft.Rest.ClientRuntime.Azure.Authentication -Version 2.2.9-preview
    
    4.  Download the script from github. 
            wget https://raw.githubusercontent.com/anoobbacker/storsimpledevicemgmttools/master/runbooks/Monitor-Backups.ps1 -Out Monitor-Backups.ps1
     
    5. Create an Azure automation account with Azure RunAs Account. 
       Refer https://docs.microsoft.com/azure/automation/automation-create-standalone-account. 
    
       If you've an existing Azure automation account configure the Azure RunAs Account. 
       Refer https://docs.microsoft.com/azure/automation/automation-create-runas-account.

    6. Create an Azure Automation Runbook Module for StorSimple 8000 Series device management. 
       Use the below commands to create a Automation module zip file.

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

    7. Import the Azure Automation module zip file (Microsoft.Azure.Management.StorSimple8000Series.zip) created in above step. 
       This can be done by selecting the Automation Account, click "Modules" under SHARED RESOURCES and then click "Add a module". 

    8. Import the runbook script (Monitor-Backup.ps1) as a Azure Automation Powershell runbook script, publish & execute it.

    9. Use below commands to create Variable assets & Credential asset in Azure Automation
            
            $SubscriptionId = "[sub-id]"
            $ResourceGroupName = "[res-group-name]"
            $AutomationAccountName = "[automation-acc-name]"
            $ManagerName = "[device-manager-name]"
            $DeviceName = "[device-name]"
            $NumberOfDaysForReport = "[number-of-days-for-report]"
            $IsMailRequired = $true
            $MailSmtpServer = "[server-name]"
            $MailToAddress = "[to-email-address]"
            $MailSubject = "[subject-name]"
            $Creds = Get-Credential -Message "Enter the SMTP user log-in credentials"
            
            Login-AzureRmAccount 
            Set-AzureRmContext -SubscriptionId "$SubscriptionId"
            New-AzureRmAutomationVariable -Encrypted $false -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name "ResourceGroupName" -Value "$ResourceGroupName"
            New-AzureRmAutomationVariable -Encrypted $false -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name "ManagerName" -Value "$ManagerName"
            New-AzureRmAutomationVariable -Encrypted $false -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name "DeviceName" -Value "$DeviceName"
            
            New-AzureRmAutomationVariable -Encrypted $false -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name "NumberOfDaysForReport" -Value "$NumberOfDaysForReport"
            
            #e-mail related variables
            New-AzureRmAutomationVariable -Encrypted $false -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name "IsMailRequired" -Value "$IsMailRequired"
            New-AzureRmAutomationVariable -Encrypted $false -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name "Mail-SMTPServer" -Value "$MailSmtpServer"
            New-AzureRmAutomationVariable -Encrypted $false -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name "Mail-ToAddress" -Value "$MailToAddress"
            New-AzureRmAutomationVariable -Encrypted $false -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name "Mail-Subject" -Value "$MailSubject"
            New-AzureRmAutomationCredential -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name "Mail-Credential" -Value $Creds
            
    10. To ensure that the automation account created can access the StorSimple Device Manager service, you need to assign appropriate 
        permissions to the automation account. Go to Access control in your StorSimple Device Manager service. 
        Click + Add and provide the name of your Azure Automation Account. Save the settings.
        Refer https://docs.microsoft.com/azure/storsimple/storsimple-8000-automation-azurerm-runbook

     ----------------------------
.PARAMS
    ResourceGroupName: Input the name of the resource group on which to retrieve the StorSimple job(s).
    ManagerName: Input the name of the resource (StorSimple device manager) on which to retrieve the StorSimple job(s).
    DeviceName: Input the name of the StorSimple device on which to retrieve the StorSimple job(s).
    NumberOfDaysForReport: Input the number of days for which to get Backup status report.

    IsMailRequired: Input the ismailrequired arg as $true if you want to receive the results. Possible values [$true/$false]
    Mail-Credential (Optional): Input a user account that has permission to perform this action.
    Mail-SMTPServer (Optional): Input the name of the SMTP server that sends the email message.
    Mail-ToAddress (Optional): Input the addresses to which the mail is sent.
                    If you have multiple addresses, then add addresses as a comma-separated string, such as someone@example.com,someone@example.com
    Mail-Subject (Optional): Input the subject of the email message.
#>

if (!(Get-Command Get-AutomationConnection -errorAction SilentlyContinue))
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

$DeviceName = Get-AutomationVariable -Name "DeviceName" 
if ($DeviceName -eq $null) 
{ 
    throw "The DeviceName asset has not been created in the Automation service."
}

$NumberOfDaysForReport = Get-AutomationVariable -Name "NumberOfDaysForReport" 
if ($NumberOfDaysForReport -eq $null) 
{ 
    throw "The NumberOfDaysForReport asset has not been created in the Automation service."
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

function GenerateFilterODataQuery()
{
    Param
    (
        [Parameter(Mandatory = $true)]
        [string]$filterByStatus,

        [Parameter(Mandatory = $true)]
        [int]$filterByDuration
    )

    $filter = "jobtype eq 'ScheduledBackup'"
    $filterByStartTime = (Get-Date).AddDays(-($filterByDuration))
    $filterByEndTime = (Get-Date)

    if (!([string]::IsNullOrEmpty($filterByStatus))) {
        $filter += " and status eq '$($filterByStatus)'"
    }

    if (!([string]::IsNullOrEmpty($filterByDuration))) {
        $filter += " and starttime ge '$($filterByStartTime.ToString('r'))' and starttime le '$($filterByEndTime.ToString('r'))'"
    }

    return $filter
}

function GetDurationTime()
{
    param
    (
        [Parameter(Mandatory = $true)]
        [datetime]$JobStartTime,
        [Parameter(Mandatory = $true)]
        [datetime]$JobEndTime
    )
    
    $durationInString = ""
    $Duration = ([datetime]$JobEndTime) - ([datetime]$JobStartTime)

    if ($Duration.Days -eq 1) { $durationInString += "$($Duration.Days) day"}
    elseif ($Duration.Days -gt 1) { $durationInString += "$($Duration.Days) days"}
    
    if ($durationInString.Length -eq 0) {
        if ($Duration.Hours -eq 1) { $durationInString += "$($Duration.Hours) hour"}
        elseif ($Duration.Hours -gt 1) { $durationInString += "$($Duration.Hours) hours"}
    }else {
        if ($Duration.Hours -eq 1) { $durationInString += " and $($Duration.Hours) hour"}
        elseif ($Duration.Hours -gt 1) { $durationInString += " and $($Duration.Hours) hours"}
    }

    if ($durationInString.Length -eq 0) {
        if ($Duration.Minutes -eq 1) { $durationInString += "$($Duration.Minutes) minute"}
        elseif ($Duration.Minutes -gt 1) { $durationInString += "$($Duration.Minutes) minutes"}
    }else {
        if ($Duration.Minutes -eq 1) { $durationInString += " and $($Duration.Minutes) minute"}
        elseif ($Duration.Minutes -gt 1) { $durationInString += " and $($Duration.Minutes) minutes"}
    }

    if ($durationInString.Length -eq 0) {
        if ($Duration.Seconds -eq 1) { $durationInString += "$($Duration.Seconds) second"}
        elseif ($Duration.Seconds -gt 1) { $durationInString += "$($Duration.Seconds) seconds"}
    }else {
        if ($Duration.Seconds -eq 1) { $durationInString += " and $($Duration.Seconds) second"}
        elseif ($Duration.Seconds -gt 1) { $durationInString += " and $($Duration.Seconds) seconds"}
    }

    return $durationInString
}

function EnumerateJobs()
{
    Param
    (
        [Parameter(Mandatory = $true)]
        [Object]$PolictyToVolumeList,

        [Parameter(Mandatory = $true)]
        [Object]$Jobs
    )

    $JobsHistory = @()
    foreach ($job in $Jobs)
    {
        $VolumeNames = ($PolictyToVolumeList | where BackupPolicyName -eq $job.EntityLabel).Volumes
        $durationInString = GetDurationTime $job.StartTime $job.EndTime
        $ErrorDetails = ($job.Error | select Message).Message -Join ', '

        $object = New-Object System.Object
        $object | Add-Member -Type NoteProperty -Name BackupPolicyName -Value $job.EntityLabel
        $object | Add-Member -Type NoteProperty -Name Volumes -Value $VolumeNames
        $object | Add-Member -Type NoteProperty -Name JobType -Value $job.JobType
        $object | Add-Member -Type NoteProperty -Name BackupType -Value $job.BackupType
        $object | Add-Member -Type NoteProperty -Name Status -Value $job.Status
        $object | Add-Member -Type NoteProperty -Name StartTime -Value $job.StartTime
        $object | Add-Member -Type NoteProperty -Name EndTime -Value $job.EndTime
        $object | Add-Member -Type NoteProperty -Name Duration -Value $durationInString
        $object | Add-Member -Type NoteProperty -Name 'Error Message' $ErrorDetails

        $JobsHistory += $object
    }

    return $JobsHistory
}

$SLEEPTIMEOUT = 10    # Value in seconds
$TokenUrl = "https://management.azure.com" #Run '(Get-AzureRmEnvironment).ResourceManagerUrl' get the Fairfax url.

if ($IsMailRequired)
{
    # Get mail from address 
    $Mail_FromAddress = $Mail_Credential.UserName
    $Mail_Subject = $Mail_Subject + " " + (Get-Date -Format "dd-MMM-yyyy")
    $Mail_ToAddress = $Mail_ToAddress -split ','
}

$ServicePrincipalConnection = Get-AutomationConnection -Name AzureRunAsConnection
if ($ServicePrincipalConnection -eq $null)  { 
    throw "Either AzureRunAsConnection asset has not been created in the Automation service or you're not running the script in an Azure automation account."  
}

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

$ClientCertificate = Get-AutomationCertificate -Name AzureRunAsCertificate
if ($ClientCertificate -eq $null) {
   throw "Could not retrieve certificate."
}

# Set Current directory path
$ScriptDirectory = "C:\Modules\User\Microsoft.Azure.Management.StorSimple8000Series"

# Load all dependent dlls
[Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Microsoft.IdentityModel.Clients.ActiveDirectory.dll")) | Out-Null
[Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Microsoft.Rest.ClientRuntime.Azure.dll")) | Out-Null
[Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Microsoft.Rest.ClientRuntime.dll")) | Out-Null
[Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Newtonsoft.Json.dll")) | Out-Null
[Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Microsoft.Rest.ClientRuntime.Azure.Authentication.dll")) | Out-Null
[Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Microsoft.Azure.Management.Storsimple8000series.dll")) | Out-Null

$SyncContext = New-Object System.Threading.SynchronizationContext
[System.Threading.SynchronizationContext]::SetSynchronizationContext($SyncContext)

$TokenUri = New-Object System.Uri -ArgumentList $TokenUrl

$ClientAssertionCertificate = New-Object Microsoft.IdentityModel.Clients.ActiveDirectory.ClientAssertionCertificate -ArgumentList $ClientId, $ClientCertificate

# Verify User Credentials
Write-Verbose "Connecting to Azure [SubscriptionId = $SubscriptionId][TenantID = $TenantId][ApplicationID = $ClientId][Certificate = $ClientCertificate.Subject]"
Write-Output "Connecting to Azure"
$Credentials = [Microsoft.Rest.Azure.Authentication.ApplicationTokenProvider]::LoginSilentWithCertificateAsync($TenantId, $ClientAssertionCertificate).GetAwaiter().GetResult()
if ($Credentials -eq $null) {
   throw "Failed to authenticate!"
}

try {
    $StorSimpleClient = New-Object Microsoft.Azure.Management.StorSimple8000Series.StorSimple8000SeriesManagementClient -ArgumentList $TokenUri, $Credentials

    # Sleep before connecting to Azure (PowerShell)
    Start-Sleep -s $SLEEPTIMEOUT
} catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

If ($StorSimpleClient -eq $null -or $StorSimpleClient.GenerateClientRequestId -eq $false) {
    throw "Unable to connect Azure"
}

# Set SubscriptionId
$StorSimpleClient.SubscriptionId = $SubscriptionId

# Get all backup policies under device
try {
    $backupPolicies = [Microsoft.Azure.Management.StorSimple8000Series.BackupPoliciesOperationsExtensions]::ListByDevice($StorSimpleClient.BackupPolicies, $DeviceName, $ResourceGroupName, $ManagerName)
} catch {
    throw $_.Exception
}

$PolictyToVolumeList = @()
foreach ($BackupPolicy in $BackupPolicies) {
    # Fetch volume name(s)
    $VolumeNames = ($BackupPolicy.VolumeIds | % {
                        if($_.Length -gt 0) {
                            $_.split(',') | % { $_.SubString($_.LastIndexOf('/') + 1) }
                        }
                    }) -Join ','

    $object = New-Object System.Object
    $object | Add-Member -Type NoteProperty -Name BackupPolicyName -Value $BackupPolicy.Name
    $object | Add-Member -Type NoteProperty -Name Volumes -Value $VolumeNames
    $PolictyToVolumeList += $object
}

# Generate oDataQuery based on JobStatus & Duration
$oDataQuery = GenerateFilterODataQuery 'Failed' $NumberOfDaysForReport

# Get all device jobs alon with query filter
try {
    $FailedJobs = [Microsoft.Azure.Management.StorSimple8000Series.JobsOperationsExtensions]::ListByDevice($StorSimpleClient.Jobs, $DeviceName, $ResourceGroupName, $ManagerName, $oDataQuery)
} catch {
    throw $_.Exception
}

# Enumerate failed jobs
if ($FailedJobs -ne $null -and $FailedJobs.Length -gt 0) {
    $JobsHistory = EnumerateJobs $PolictyToVolumeList $FailedJobs
}

# Generate oDataQuery based on JobStatus & Duration
$oDataQuery = GenerateFilterODataQuery 'Running' $NumberOfDaysForReport

# Get all device jobs alon with query filter
try {
    $RunningJobs += [Microsoft.Azure.Management.StorSimple8000Series.JobsOperationsExtensions]::ListByDevice($StorSimpleClient.Jobs, $DeviceName, $ResourceGroupName, $ManagerName, $oDataQuery)
} catch {
    throw $_.Exception
}

# Enumerate failed jobs
if ($RunningJobs -ne $null -and $RunningJobs.Length -gt 0) {
    $JobsHistory += EnumerateJobs $PolictyToVolumeList $RunningJobs
}

# Generate oDataQuery based on JobStatus & Duration
$oDataQuery = GenerateFilterODataQuery 'Succeeded' $NumberOfDaysForReport

# Get all device jobs alon with query filter
try {
    $SucceededJobs = [Microsoft.Azure.Management.StorSimple8000Series.JobsOperationsExtensions]::ListByDevice($StorSimpleClient.Jobs, $DeviceName, $ResourceGroupName, $ManagerName, $oDataQuery)
} catch {
    throw $_.Exception
}

# Enumerate failed jobs
if ($SucceededJobs -ne $null -and $SucceededJobs.Length -gt 0) {
    $JobsHistory += EnumerateJobs $PolictyToVolumeList $SucceededJobs
}

if ($IsMailRequired)
{
    # Send a mail
    $Mail_Body = ($JobsHistory | ConvertTo-Html | Out-String)
    $Mail_Body = $Mail_Body -replace "<head>", "<head><style>body{font-family: 'Segoe UI',Arial,sans-serif; color: #366EC4; font-size: 13px;}table { border-right: 1px solid #434343;  border-top: 1px solid #434343; } th, td { border-left: 1px solid #434343; border-bottom: 1px solid #434343; padding: 5px 5px; }</style>"
    $Mail_Body = $Mail_Body -replace "<table>", "<table cellspacing='0' cellpadding='0' width='700px'>"

    Write-Output "Attempting to send a status mail"
    Send-MailMessage -Credential $Mail_Credential -From $Mail_FromAddress -To $Mail_ToAddress -Subject $Mail_Subject -SmtpServer $Mail_SMTPServer -Body $Mail_Body -BodyAsHtml:$true -UseSsl
    Write-Output "Mail sent successfully"
}

# Print result
$JobsHistory | Format-Table -GroupBy Status -Auto
