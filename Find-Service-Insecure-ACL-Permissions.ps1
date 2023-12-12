<#
import-module activedirectory

Function Get-AD-Computers {
    param([string]$OU,
          [bool]$print=$false
    )
    
    $computersArray = @(Get-ADComputer -SearchBase $OU -Filter * | Select -Expand Name)

    if($print) {
        foreach($computerName in $computersArray) { Write-Host $computerName  }
    }
    return $computersArray
}

$computersArray  = @()
$computersArray += Get-AD-Computers "OU=Computers,DC=Contoso,DC=com" $false
#>

$start_time = Get-Date
$computersArray = Import-Csv C:\temp\hosts.csv | % { $_.ComputerName }

# Define the number of Runspaces (i.e.: threads) to use
$runspaces = 100

# This is the array we want to ultimately add our information to
[Collections.Arraylist]$finalResults = @()

# Main function: runs task in multiple runspaces and returns the results
function Run-MultiThreadedTask {
    param (
        [string[]]$hosts,
        [int]$runspaces, 
        [int]$Timeout
    )

    [Collections.Arraylist]$RunspaceCollection = @()

	# Create a Runspace Pool (with a min and max number of runspaces).
    $pool = [Runspacefactory]::CreateRunspacePool(1, $runspaces)
	
	# Open the RunspacePool
    $pool.Open()

	# Define a scriptblock to actually do the work
	$ScriptBlock = {
		Param($Computer)
		
        try {
            $scriptResults = Invoke-Command -computer $Computer -ScriptBlock {
                $comp = $($args[0])
                $results = @() 
                $servicesInfo = Get-WmiObject -Class Win32_Service | `
                    Select-Object Name, DisplayName, Caption, Description, PathName, StartName, StartMode, State, Status | `
                    where { $_.PathName -inotmatch ":\\Windows\\" -and ($_.StartMode -eq "Auto" -or $_.StartMode -eq "Manual") -and ($_.State -eq "Running" -or $_.State -eq "Stopped") } | `
                    Select Name, DisplayName, Caption, Description, PathName, StartName, StartMode, State, Status
                        
                foreach($serviceInfo in $servicesInfo) {
                    $executablePath = $serviceInfo.PathName.Substring(0, $serviceInfo.PathName.LastIndexOf(".exe") + 4)
                    $executablePath = $executablePath.Replace("`"","")
                    try {
                        $acls = (Get-ACL $executablePath).access | 
                            where { 
                                $_.IdentityReference -notlike "NT AUTHORITY\SYSTEM" `
                                -and $_.IdentityReference -notlike "BUILTIN\Administrators"  `
                                -and $_.IdentityReference -notlike "NT SERVICE\TrustedInstaller" `
                                -and (  $_.FileSystemRights -ilike "*Full Control*" `
                                    -or $_.FileSystemRights -ilike "*Write*" `
                                    -or $_.FileSystemRights -ilike "*Change*" `
                                    -or $_.FileSystemRights -ilike "*Modify*" `
                                )
                            }
                        foreach($acl in $acls) {
                            $obj = New-Object PSCustomObject -Property @{
                                ComputerName = $comp
                                Name = $serviceInfo.Name
                                ExecutablePath = $executablePath
                                DisplayName = $serviceInfo.DisplayName
                                Caption  = $serviceInfo.Caption
                                Description = $serviceInfo.Description
                                PathName   = $serviceInfo.PathName
                                StartName = $serviceInfo.StartName
                                StartMode  = $serviceInfo.StartMode
                                State  = $serviceInfo.State
                                Status  = $serviceInfo.Status
                                ACL_IdentityReference = $acl.IdentityReference
                                ACL_FileSystemRights = $acl.FileSystemRights
                                ACL_AccessControlType = $acl.AccessControlType
                            }
                            $results += $obj
                        }
                    }
                    catch { $results += $serviceInfo }
                }
                $results
            } -ArgumentList $Computer

            $scriptResults
        }
        catch { }
        		
	}

    
	foreach($computer in $hosts) {
		# Create a PowerShell object to run, and add the script and argument to it.
		$Powershell = [PowerShell]::Create().AddScript($ScriptBlock).AddArgument($Computer)

		# Specify runspace to use.
        # This is what lets us run concurrents sessions.
		$Powershell.RunspacePool = $pool

		# Create Runspace collection
		# When we create the collection, we also define that each Runspace should begin running
		$RunspaceCollection += New-Object -TypeName PSObject -Property @{
            StartTime = Get-Date
            ComputerName = $computer
			Runspace = $PowerShell.BeginInvoke()
			PowerShell = $PowerShell  
		}
	}
	
	# Main "waiting function. We need to wait for all runspaces to finish (or timeout). When they do - we collect our results (as well as clean up the runspaces).
	While ($RunspaceCollection) {
		Foreach ($Runspace in $RunspaceCollection.ToArray()) {
			# Check if Runspace has completed
			If ($Runspace.Runspace.IsCompleted) {
				# Get results from Runspace
				[void]$finalResults.Add($Runspace.PowerShell.EndInvoke($Runspace.Runspace))
				
				# Cleanup Runspace
				$Runspace.PowerShell.Dispose()
				$RunspaceCollection.Remove($Runspace)	
			}
            # Check Runspace has exceeded the timeout limit
            elseif (!$Runspace.Runspace.IsCompleted) {
                if( ((Get-Date) - $Runspace.StartTime).totalseconds -gt $Timeout ) {
                    Write-Error "[$($Runspace.ComputerName)] Thread exceeded $Timeout seconds limit"
                    $Runspace.Powershell.dispose()
                    $Runspace = $null                    
                }
            }
		}
        # Sleep for specified time before looping again
        $sleepTimer = 200
        Start-Sleep -Milliseconds $sleepTimer
	}
	$finalResults
}

# Run the Run-MultiThreadedTask function and display the results
$results = Run-MultiThreadedTask $computersArray $runspaces 10


$results | % { $_ | Select ComputerName, Name, ExecutablePath, ACL_IdentityReference, ACL_FileSystemRights, ACL_AccessControlType, DisplayName, Caption, Description, PathName, StartName, StartMode, State, Status } | ogv -Title "Services With Weak ACL permissions"
$results | % { $_ | Select ComputerName, Name, ExecutablePath, ACL_IdentityReference, ACL_FileSystemRights, ACL_AccessControlType, DisplayName, Caption, Description, PathName, StartName, StartMode, State, Status } | Export-Csv C:\temp\Services_with_Weak_ACL_Permissions.csv -Encoding Unicode -NoTypeInformation
$end_time = Get-Date
$time_taken = $end_time - $start_time
$msg = "Total time jobs took: {0}h:{1}m:{2}s" -f ($time_taken).Hours, ($time_taken).Minutes, ($time_taken).Seconds
Write-Host $msg