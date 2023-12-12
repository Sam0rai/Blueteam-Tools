# Blueteam-Tools
Tools for the usage of the Blue Team.

* **Find-GPO-Non-Default-Trustees.ps1** <br>
**Purpose:** Identifying GPOs (Group Policy Objects) which non-default users \ AD groups (a.k.a: "Trustees") can modify or delete. <br>
**Requirements:** Need to have RSAT ("Remote Server Admin Tools") installed on the machine this script will execute from. <br>
**Version:** 1.0 <br>

This tool was created as a response (or perhaps- a pre-curser) to FSecureLABS's tool: [SharpGPOAbuse](https://github.com/FSecureLABS/SharpGPOAbuse).<br>
Red Teamers can leverage overly permissive permissions on GPOs to change them, such as adding their own script to the GPO - 
which in turn may run on various hosts in the target organization that GPO is applied on.
This technique may help them achieve remote code execution, privilege escalation, persistance, etc.

**Find-GPO-Non-Default-Trustees.ps1** can be used by both the Red Team, as well as the Blue Team (even by a low-privileged user), to iterate over all GPOs in the Domain Controller, 
and recieve a list of all GPOs which have non-default users or AD groups (i.e.: not "Domain Admins", "Enterprise Admins" or "SYSTEM") that can modify or delete those GPOs.
The list displays the GPO name, the user or AD group and their corresponding permissions. <br>

**Note:** If such a GPO is found - the list will contain ALL the users and AD groups with permissions to change it (including the default one mentioned above).
This was done in order to know if default trustees do in fact have permissions to change the GPO, or whether they were removed.
<br><br>

* **Find-Service-Insecure-ACL-Permissions.ps1**
**Purpose:** Identifying privilege escalation attack surface via service executable hijacking; i.e.: services which point to an executable on disk which has weak ACL permissions on it, allowing attackers to replace it with their malicious service executable. <br>
**Requirements:** None (though there's commented code in it for importing the "ActiveDirectory" module, if it exists on the host from which the script is run). <br>
**Version:** 1.0 <br>
