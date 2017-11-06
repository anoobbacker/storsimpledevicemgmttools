<#
.DESCRIPTION
    This scipt starts a manual backup & deletes the backup cloud snapshots older than specified retention days.

    Steps to execute the script: 
    ----------------------------
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
            wget https://raw.githubusercontent.com/anoobbacker/storsimpledevicemgmttools/master/Manage-CloudSnapshots.ps1 -Out Manage-CloudSnapshots.ps1
     
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

    8. Import the runbook script (Monitor-Backup.ps1) as a Azure Automation Powershell runbook script, publish & execute it.

     ----------------------------
.PARAMS
    ResourceGroupName: Input the name of the resource group on which to create/update the volume.
    ManagerName: Input the name of the resource (StorSimple device manager) on which to create/update the volume.
    DeviceName: Input the name of the StorSimple device on which to create/update the volume.

    BackupPolicyName: Input the name of the Backup policy to use to create the cloud snapshot.
    RetentionInDays: Input the days of the retention to use to delete the older backups. Default value 20 days.

    Mail-Credential: Input a user account that has permission to perform this action.
    Mail-ToAddress: Input the addresses to which the mail is sent.
                    If you have multiple addresses, then add addresses as a comma-separated string, such as someone@example.com,someone@example.com
    Mail-Subject: Input the subject of the email message. 
    Mail-SMTPServer: Input the name of the SMTP server that sends the email message.

    WhatIf: Input the WhatIf arg as $true if you want to see what changes the script will make. Possible values [$false, $true]
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

$DeviceName = Get-AutomationVariable -Name "DeviceName" 
if ($DeviceName -eq $null) 
{ 
    throw "The DeviceName asset has not been created in the Automation service."
}

$BackupPolicyName = Get-AutomationVariable -Name "BackupPolicyName" 
if ($BackupPolicyName -eq $null) 
{ 
    throw "The BackupPolicyName asset has not been created in the Automation service."
}

$RetentionInDays = Get-AutomationVariable -Name "RetentionInDays" -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($RetentionInDays))
{
    $RetentionInDays = 20
}

$WhatIf = Get-AutomationVariable -Name "WhatIf" 
if ($WhatIf -eq $null) 
{ 
    throw "The WhatIf asset has not been created in the Automation service."
}

$Mail_SMTPServer = Get-AutomationVariable -Name "Mail-SMTPServer"
if ($Mail_SMTPServer -eq $null) 
{ 
    throw "The Mail-SMTPServer asset has not been created in the Automation service."  
}

$Mail_ToAddress = Get-AutomationVariable -Name "Mail-ToAddress"
if ($Mail_ToAddress -eq $null)
{
    throw "The Mail-ToAddress asset has not been created in the Automation service."
}

$Mail_Subject = Get-AutomationVariable -Name "Mail-Subject"
if ($Mail_Subject -eq $null)
{
    throw "The Mail-Subject asset has not been created in the Automation service."
}

$Mail_Credential = Get-AutomationPSCredential -Name "Mail-Credential"
if ($Mail_Credential -eq $null)
{
    throw "The Mail-Credential asset has not been created in the Automation service."
}

$ClientCertificate = Get-AutomationCertificate -Name AzureRunAsCertificate
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

# Get from address 
$Mail_FromAddress = $Mail_Credential.UserName
$Mail_Subject = $Mail_Subject + " " + (Get-Date -Format "dd-MMM-yyyy")
$Mail_ToAddress = $Mail_ToAddress -split ','
$Mail_Body = "<html><head></head><body>"

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

# Print method
Function PrettyWriter($Content, $Color = "Yellow") { 
    Write-Host $Content -Foregroundcolor $Color 
}

# Create a query filter
Function GenerateBackupFilter() {
    param([String] $FilterByEntityId, [DateTime] $FilterByStartTime, [DateTime] $FilterByEndTime)
    $queryFilter = $null
    if ($FilterByStartTime -ne $null) {
        $queryFilter = "createdTime ge '$($FilterByStartTime.ToString('r'))'"
    }

    if($FilterByEndTime -ne $null) {
        if(![string]::IsNullOrEmpty($queryFilter)) {
            $queryFilter += " and "
        }
        $queryFilter += "createdTime le '$($FilterByEndTime.ToString('r'))'"
    }

    if ( !([string]::IsNullOrEmpty($FilterByEntityId)) ) {
        if(![string]::IsNullOrEmpty($queryFilter)) {
            $queryFilter += " and "
        }
        if ( $FilterByEntityId -like "*/backupPolicies/*" ) {
            $queryFilter += "backupPolicyId eq '$($FilterByEntityId)'"
        } else {
            $queryFilter += "volumeId eq '$($FilterByEntityId)'"
        }
    }

    return $queryFilter
}

try {
    $TokenUri = New-Object System.Uri -ArgumentList $TokenUrl

    $SyncContext = New-Object System.Threading.SynchronizationContext
    [System.Threading.SynchronizationContext]::SetSynchronizationContext($SyncContext)

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

    # Set backup expiration date
    $Today = Get-Date
    $ExpirationDate = $Today.AddDays(-$RetentionInDays)

    # Set backup type (CloudSnapshot)
    $BackupType = 'CloudSnapshot'

    if ( $WhatIf ) 
    {
        PrettyWriter "WhatIf: Perform manual backup." "Red"
        $Mail_Body += "<br />WhatIf: Perform manual backup."
    }
    else 
    {
        Write-Output "Starting start a manual backup."
        $Mail_Body += "<br />Starting start a manual backup ($BackupPolicyName)."

        $Result = [Microsoft.Azure.Management.StorSimple8000Series.BackupPoliciesOperationsExtensions]::BackupNowAsync($StorSimpleClient.BackupPolicies, $DeviceName, $BackupPolicyName, $BackupType, $ResourceGroupName, $ManagerName)
        if ($Result -ne $null -and $Result.IsFaulted) {
            Write-Output $Result.Exception
            break
        }
        PrettyWriter "Successfully started the manual backup job."
        $Mail_Body += "<br />Successfully started the manual backup job."
    }

    $CompletedSnapshots =@()

    # Get all backups by Device
    $BackupPolicyId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.StorSimple/managers/$ManagerName/devices/$DeviceName/backupPolicies/$BackupPolicyName"
    $BackupStartTime = Get-Date -Date "1970-01-01 00:00:00Z"
    $BackupFilter = GenerateBackupFilter $BackupPolicyId $BackupStartTime $ExpirationDate

    $oDataQuery = New-Object Microsoft.Rest.Azure.OData.ODataQuery[Microsoft.Azure.Management.StorSimple8000Series.Models.BackupFilter] -ArgumentList $BackupFilter

    $CompletedSnapshots = [Microsoft.Azure.Management.StorSimple8000Series.BackupsOperationsExtensions]::ListByDevice($StorSimpleClient.Backups, $DeviceName, $ResourceGroupName, $ManagerName, $oDataQuery)

    $TotalSnapshotCnt = 0
    $OldSnapshotCnt = 0
    $SkippedSnapshotCnt = 0
    Write-Output "Find the backup snapshots prior to $ExpirationDate ($RetentionInDays days) and delete them. `nQuery: $BackupFilter<br />"
    $Mail_Body += "<br /><br />Find the backup snapshots prior to $ExpirationDate ($RetentionInDays days) and delete them. <br /><b>Query:</b> $BackupFilter<br />"
    foreach ($Snapshot in $CompletedSnapshots) 
    {
        $TotalSnapshotCnt++
        $SnapShotName = $SnapShot.Name
        $SnapshotStartTimeStamp = $Snapshot.CreatedOn
        if ($SnapshotStartTimeStamp -lt $ExpirationDate)
        {
            $OldSnapshotCnt++
            try {
                if ( $WhatIf ) 
                {
                    PrettyWriter "WhatIf: Trigger delete of snapshot $($SnapShotName) which was created on $($SnapshotStartTimeStamp)" "Red"
                    $Mail_Body += "<br />WhatIf: Trigger delete of snapshot <b>$($SnapShotName)</b> which was created on <b>$($SnapshotStartTimeStamp)</b>"
                }
                else 
                {
                    PrettyWriter "Deleting $($SnapShotName) which was created on $($SnapshotStartTimeStamp)."
                    $Mail_Body += "<br />Deleting <b>$($SnapShotName)</b> which was created on <b>$($SnapshotStartTimeStamp)</b>."
                    $Result = [Microsoft.Azure.Management.StorSimple8000Series.BackupsOperationsExtensions]::DeleteAsync($StorSimpleClient.Backups, $DeviceName, $SnapShotName, $ResourceGroupName, $ManagerName)
                    if ($Result -ne $null -and $Result.IsFaulted) {
                        Write-Error $Result.Exception
                    }
                }
            }
            catch {
                # Print error details
                Write-Error $_.Exception.Message
                $Mail_Body = "<br /><br /><b>Exception:</b><br />$_.Exception.Message"
                break
            }
        }
        else
        {
            $SkippedSnapshotCnt++
            #Write-Output "Skipping $SnapShotName at $SnapshotStartTimeStamp"
        }
    }    
}
catch {
    # Print error details
    Write-Error $_.Exception.Message
    $Mail_Body = "<br /><br /><b>Exception:</b><br />$_.Exception.Message"
}

$Mail_Body += "<br /><br /><b>Summary details:</b> <br /> Total snapshots count: $TotalSnapshotCnt <br /> Old snapshots count: $OldSnapshotCnt<br /> Latest snapshots count: $SkippedSnapshotCnt"
$Mail_Body += "</body></html>"
Write-Output "`nAttempting to send a status mail"
Send-MailMessage -Credential $Mail_Credential -From $Mail_FromAddress -To $Mail_ToAddress -Subject $Mail_Subject -SmtpServer $Mail_SMTPServer -Body $Mail_Body -BodyAsHtml:$true -UseSsl
Write-Output "Mail sent successfully"

PrettyWriter "`n`nSummary details:"
Write-Output "Total snapshots count: $TotalSnapshotCnt"
Write-Output "Old snapshots Count: $OldSnapshotCnt"
Write-Output "Latest Snapshots Count: $SkippedSnapshotCnt"
