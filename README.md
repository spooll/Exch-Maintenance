#SYNOPSIS
    Function to start and stop Exchange Server Maintenance.
#DESCRIPTION
    You don`t need edit this script, but use it in local Exchange Server session.
    Its total 70-lines function script instead of 3 572-lines scripts by MS (with skipped Sig.): 
    StartDagServerMaintenance, StopDagServerMaintenance, RedistributeActiveDatabases, 
    which are difficult and lazy to parse (has anyone figured out what's inside?).

    For your convenience, it is recommended to write the function in the profile file,
    which located in C:\Users\YourName\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1
    Start Exchange Management Shell, type "Notepad $profile", and if you have warning
    "The system cannot find..." , you should create it first, by running "New-item $profile -Force",
    then copy-paste script text, and reopen EMS.
#PARAMETER Start
    It`s set HubTransport, ServerWideOffline, DatabaseCopyActivationDisabledAndMoveNow, DatabaseCopyAutoActivationPolicy
    and ClusterNode in Maintenance, redirect current messages in queue to random Exch server and Move-ActiveMailboxDatabase
    to random server each, then run some status check. 
#PARAMETER Stop
    It`s bring back HubTransport, ServerWideOffline, DatabaseCopyActivationDisabledAndMoveNow, DatabaseCopyAutoActivationPolicy
    Active and ClusterNode online, Activate Local Database Copys with Activation Preference 1 and get current status of mounted databases.
    ActivationPreference should display 1.

    Name                  Status MailboxServer ActivationPreference
    ----                  ------ ------------- --------------------
    HeavyDB01\S-EX-01    Mounted S-EXCH-01                          1
    LightDB01\S-EX-02    Mounted S-EXCH-02                          1
    LightDB02\S-EX-03    Mounted S-EXCH-03                          1
    HeavyDB02\S-EX-04    Mounted S-EXCH-04                          1
#EXAMPLE
```powershell
    Exch-Maintenance -Start
    Exch-Maintenance -Stop
