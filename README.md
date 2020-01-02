# StorSimple Device Management Tools
This project will contain samples scripts which can be leveraged for automating StorSimple device management.

## Run Azure PowerShell script
The script used in this example lists all the jobs on a StorSimple device. This includes the jobs that succeeded, failed, or are in progress. Perform the following steps to download and run the script.

1.  Launch Azure PowerShell. Create a new folder and change directory to the new folder.

```
      mkdir C:\scripts\StorSimpleSDKTools
      cd C:\scripts\StorSimpleSDKTools
```
    
2.  [Download nuget CLI](http://www.nuget.org/downloads) under the folder created in the previous step. There are various versions of nuget.exe. Choose the version corresponding to your SDK. Each download link points directly to an .exe file. Be sure to right-click and save the file to your computer rather than running it from the browser. 

You can also run the following command to download and store the script in the same folder that you created earlier. Refer [NuGet Documentation](https://docs.microsoft.com/en-gb/nuget/).
    
```
      wget https://dist.nuget.org/win-x86-commandline/latest/nuget.exe -Out nuget.exe
```
            
3.  Download the StorSimple Device Manager and dependent SDK libraries.

```
      C:\scripts\StorSimpleSDKTools\nuget.exe install Microsoft.Azure.Management.Storsimple8000series
      C:\scripts\StorSimpleSDKTools\nuget.exe install Microsoft.IdentityModel.Clients.ActiveDirectory -Version 2.28.3
      C:\scripts\StorSimpleSDKTools\nuget.exe install Microsoft.Rest.ClientRuntime.Azure.Authentication -Version 2.2.9-preview
```
    
4.  Download the script from the sample GitHub project and execute the script.

```
      wget https://github.com/anoobbacker/storsimpledevicemgmttools/raw/master/<script-name> -Out <script-name>
      .\<scripname> -SubscriptionId <subid> -ResourceGroupName <resource group> -ManagerName <device manager> -DeviceName <device name>
```
