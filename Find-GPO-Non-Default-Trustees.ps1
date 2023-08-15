<#
Find-GPO-Non-Default-Trustees
-----------------------------
Purpose: Identifying GPOs (Group Policy Objects) which non-default users \ AD groups (a.k.a: "Trustees") can modify or delete.
Requirements: Need to have RSAT ("Remote Server Admin Tools") installed on the machine this script will execute from.
Version: 1.0
#>

<#
.SYNOPSIS
Red Teamers can leverage overly permissive permissions on GPOs to change them (given the appropriate credentials), such as adding their own script to the GPO - 
which in turn may run on various hosts in the target organization.
This technique may help them achieve remote code execution, privilege escalation, persistance, etc.

Find-GPO-Non-Default-Trustees.ps1 can be used by both the Red Team, as well as the Blue Team (even by a low-privileged user), to iterate over all GPOs in the Domain Controller, 
and recieve a list of all GPOs which have non-default users or AD groups (i.e.: not "Domain Admins", "Enterprise Admins" or "SYSTEM") that can modify or delete those GPOs.
The list displays the GPO name, the user or AD group and their corresponding permissions.

[*] Note: If such a GPO is found - the list will contain ALL the users and AD groups with permissions to change it (including the default one mentioned above).
		  This was done in order to know if default trustees do in fact have permissions to change the GPO, or whether they were removed.
#>

# This import requires having RSAT ("Remote Server Admin Tools") installed on the machine this script will execute from.
Import-Module GroupPolicy
 
function FindNonDefaultTrustees($trusteeArray) {
    $defaultTrustees = @("Domain Admins", "Enterprise Admins", "SYSTEM")
    $results = @()
    foreach($trustee in $trusteeArray) {
      if($trustee -in $defaultTrustees) {
        continue
      }
      else {
        $results += $trustee
      }
    }
    return $results
}

$resultsArray = @()
$gpos = Get-GPO -All
# An array of GPO permissions which enable modification of GPO objects.
$gpoChangePermissions = @("GpoEditDeleteModifySecurity", "GpoEditDeleteModify", "GpoEdit", "GpoDelete", "GpoCreate", "GpoModifySecurity")
foreach ($gpo in $gpos) {
    $acl = Get-GPPermissions -Guid $gpo.Id -All -ErrorAction SilentlyContinue
    if ($acl) {
        $changeAccess = $acl | Where-Object { $_.Permission -in $gpoChangePermissions }
        if($changeAccess) {
            $nonDefaultTrusteesArr = @()
            $nonDefaultTrusteesArr += FindNonDefaultTrustees($changeAccess.Trustee.Name)
            if($nonDefaultTrusteesArr.Count -gt 0 ) {
                $changeAccess | ForEach-Object {
                    $obj = New-Object PSCustomObject -Property @{
                        GPOName    = $gpo.DisplayName
                        Permission = $_.Permission
                        Trustee    = $_.Trustee.Name
                    }
                    $resultsArray += $obj
                }
            }
        }
    }
}

$resultsArray | Select GPOName, Trustee, Permission | ogv