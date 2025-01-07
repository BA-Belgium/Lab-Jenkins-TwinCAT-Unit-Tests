#Powershell template for building and deploying a library
$libInstall = $true

#Message filter as described in https://infosys.beckhoff.com/english.php?content=../content/1033/tc3_automationinterface/242727947.html&id=1494948667884962804
function AddMessageFilterClass 
{ 
 $source = @‘ 
 namespace EnvDteUtils
 {
 using System; 
 using System.Runtime.InteropServices; 
 
 public class MessageFilter : IOleMessageFilter 
 { 
 public static void Register() 
 { 
 IOleMessageFilter newFilter = new MessageFilter(); 
 IOleMessageFilter oldFilter = null; 
 CoRegisterMessageFilter(newFilter, out oldFilter); 
 } 

 public static void Revoke() 
 { 
 IOleMessageFilter oldFilter = null; 
 CoRegisterMessageFilter(null, out oldFilter); 
 } 
 
 int IOleMessageFilter.HandleInComingCall(int dwCallType, System.IntPtr hTaskCaller, int dwTickCount, System.IntPtr lpInterfaceInfo)
 { 
 return 0; 
 } 

 int IOleMessageFilter.RetryRejectedCall(System.IntPtr hTaskCallee, int dwTickCount, int dwRejectType) 
 { 
 if (dwRejectType == 2) 
 { 
 return 99; 
 } 
 return -1; 
 } 

 int IOleMessageFilter.MessagePending(System.IntPtr hTaskCallee, int dwTickCount, int dwPendingType) 
 { 
 return 2; 
 } 

 [DllImport("Ole32.dll")] 
 private static extern int CoRegisterMessageFilter(IOleMessageFilter newFilter, out IOleMessageFilter oldFilter); 
 } 

 [ComImport(), Guid("00000016-0000-0000-C000-000000000046"), InterfaceTypeAttribute(ComInterfaceType.InterfaceIsIUnknown)] 
 interface IOleMessageFilter 
 { 
 [PreserveSig] 
 int HandleInComingCall(int dwCallType, IntPtr hTaskCaller, int dwTickCount, IntPtr lpInterfaceInfo);

 [PreserveSig]
 int RetryRejectedCall(IntPtr hTaskCallee, int dwTickCount, int dwRejectType);

 [PreserveSig]
 int MessagePending(IntPtr hTaskCallee, int dwTickCount, int dwPendingType);
 }
 }
‘@
 Add-Type -TypeDefinition $source
}

$verbose = $true
function Log {
    param (
        [Parameter(Position = 0)]
        [string]$InputString,
        [Parameter(Position = 1, Mandatory = $false)]
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::White
    )
    Write-Output $InputString
   # if ($verbose) {Write-Host $InputString}
}


#Automation script
AddMessageFilterClass('') # Call function
[EnvDteUtils.MessageFilter]::Register() # Call static Register Filter Method

# Script parameters
$progID = "TcXaeShell.DTE.17.0" # XaeShell64 COM ProgId
$SuppressUI = $false
$logFile = "$pwd\_ScriptLogs\logfile.txt"
$slnPath = "$pwd\src\sln\lab.sln"
$projName = "plc"
$plcProjName = "plc Project"
$UmRtProcessName = "TcSystemServiceUm"  # Replace with the process you want to check
$UmRtNetId = "192.168.4.1.1.1"
$UmRtTestFramework = "UmRtTestFramework"

# Start logging
Start-Transcript -Path $logFile -Append

# If target dir exists, remove it
#if (Test-Path $targetDir) {
#    Log "Removing existing target directory"
#    Remove-Item -Recurse -Force $targetDir
#}


# Check if the Um Rt process is running
$process = Get-Process -Name $UmRtProcessName -ErrorAction SilentlyContinue

if ($process) {
    # Process found, so kill it
    Stop-Process -Name $UmRtProcessName -Force
    Write-Host "$UmRtProcessName has been killed."
} else {
    Write-Host "$UmRtProcessName is not running."
}

try {
    $projectPath = Get-Location
    # set up the test environment UM runtime 
    #  * delete any existing test environment UM runtime
    #  * create the test environment UM runtime by copying the default UM runtime
    #  * execute the UM runtime with 'project' parameters so it fits the project references
    # Try to remove the folder if it exists
    $destinationFolder = "C:\ProgramData\Beckhoff\TwinCAT\3.1\Runtimes\" + $UmRtTestFramework
    if ((Test-Path -Path $destinationFolder)) {
        Remove-Item -Path $destinationFolder -Recurse -Force
    }
        # Copy the folder if it doesn't exist
    if (-Not (Test-Path -Path $destinationFolder)) {
        Log "UmRtNetId_TestFramework folder was removed"
        Log "Copying UmRtNetId_Default to UmRtTestFramework"
        Copy-Item -Path "C:\ProgramData\Beckhoff\TwinCAT\3.1\Runtimes\UmRt_Default" -Destination $destinationFolder -Recurse
    }
    else {
        Log "UmRtNetId_TestFramework folder was not removed"
    }
    Set-Location -Path $destinationFolder
    $env:TC_INST_NAME = $UmRtTestFramework
    $command = $env:TWINCAT3DIR+"Runtimes\bin\TcSystemServiceUm.exe"
    Log "Start UmRtTestFramework"
    #Start-Process $command -ArgumentList "-t bin -i $UmRtNetId -n $env:TC_INST_NAME -c .\3.1" -WindowStyle Minimized
    Start-Process $command -ArgumentList "-t bin -i $UmRtNetId -n $UmRtTestFramework -c .\3.1" -WindowStyle Minimized

    Set-Location -Path $projectPath
    Log "Create VisualStudio COM interface"# Define the ProgID for the Visual Studio DTE object    
    # Attempt to get the COM type
    $dteType = [type]::GetTypeFromProgID($progID)
    
    if (-not $dteType) {
        Log "The COM object '$progID' is not registered or Visual Studio is not installed." -ForegroundColor Red
        exit 1
    }
    
    # Attempt to create an instance of the COM object
    try {
        $dte = [Activator]::CreateInstance($dteType)
        if ($dte -ne $null) {
            Log "The COM object '$progID' was successfully loaded and initialized." -ForegroundColor Green
    
            # Optionally, display the version of Visual Studio
            Log "Visual Studio Version: $($dte.Version)"
        } else {
            Log "Failed to initialize the COM object '$progID'." -ForegroundColor Red
        }
    } catch {
        Log "An error occurred while trying to load the COM object: $_" -ForegroundColor Red
    }
    $dte.SuppressUI = $SuppressUI
    $dte.MainWindow.Visible = $true
    Log "Open solution $slnPath"
    $sln = $dte.Solution
    $sln.Open($slnPath)
    # open system manager for plc project
    # Listing projects in solution, selecting $projName if found
    Log "Listing projects in solution, selecting $projName if found"
    foreach ($proj in $sln.Projects) {
        Log $proj.Name
        if ($proj.Name -eq $projName) {
            $project = $proj
            break
        }
    }
    if ($project) {
        Log "Selecting sysman for project: $projName"
        $systemManager = $project.Object
        foreach($child in $systemManager){ 
            Log $child.ProjectName
        }
    } else {
        Log "ERROR: Project $projName not found" -ForegroundColor Red
    }    
    #$plcProj = $systemManager.LookupTreeItem("TIPC^$projName^$plcProjName")
    $systemManager.SetTargetNetId($UmRtNetId)
    $systemManager.ActivateConfiguration()
    $systemManager.StartRestartTwinCAT() 

    # Give the TwinCAT test framework some time to produce the results
    Sleep(5)
    Log "Moving test results"
    Move-Item -Path $destinationFolder\testresults.xml -Destination $pwd\_TestResults\testresults.xml

	}
catch {
    # Handle the error    
    Log "Error: $($_.Exception.Message)"
}
finally {
    Log "Exiting..."
    $dte.Quit()
    Log 'Done'
}

# Stop logging
Stop-Transcript

[EnvDTEUtils.MessageFilter]::Revoke()