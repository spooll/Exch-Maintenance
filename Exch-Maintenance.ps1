function global:Exch-Maintenance {
<#
.SYNOPSIS
    Function to start and stop Exchange Server Maintenance.
.DESCRIPTION
    You don`t need edit this script, but use it in local Exchange Server session.
    Its total 70-lines function script instead of 3 572-lines scripts by MS (with skipped Sig.): 
    StartDagServerMaintenance, StopDagServerMaintenance, RedistributeActiveDatabases, 
    which are difficult and lazy to parse (has anyone figured out what's inside?).

    For your convenience, it is recommended to write the function in the profile file,
    which located in C:\Users\YourName\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1
    Start Exchange Management Shell, type "Notepad $profile", and if you have warning
    "The system cannot find..." , you should create it first, by running "New-item $profile -Force",
    then copy-paste script text, and reopen EMS.
.PARAMETER Start
    It`s set HubTransport, ServerWideOffline, DatabaseCopyActivationDisabledAndMoveNow, DatabaseCopyAutoActivationPolicy
    and ClusterNode in Maintenance, redirect current messages in queue to random Exch server and Move-ActiveMailboxDatabase
    to random server each, then run some status check. 
.PARAMETER Stop
    It`s bring back HubTransport, ServerWideOffline, DatabaseCopyActivationDisabledAndMoveNow, DatabaseCopyAutoActivationPolicy
    Active and ClusterNode online, Activate Local Database Copys with Activation Preference 1 and get current status of mounted databases.
    ActivationPreference should display 1.

    Name                  Status MailboxServer ActivationPreference
    ----                  ------ ------------- --------------------
    HeavyDB01\S-EX-01    Mounted S-EXCH-01                          1
    LightDB01\S-EX-02    Mounted S-EXCH-02                          1
    LightDB02\S-EX-03    Mounted S-EXCH-03                          1
    HeavyDB02\S-EX-04    Mounted S-EXCH-04                          1
.EXAMPLE
    Exch-Maintenance -Start
    Exch-Maintenance -Stop
#>
    param(
        [switch]$Start,
        [switch]$Stop
    )

    $WarningActionPreference = "SilentlyContinue"
    while (-Not(Get-PSSession|Where-Object ConfigurationName -eq "Microsoft.Exchange")) {
        $exch= (Get-ADComputer -Filter "name -like 's-exch-0*'").name| Get-Random                                            #Put your Exchange server names template here!!!
        $session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "http://$exch/Powershell" -Authentication Kerberos
        Import-PSSession $session -DisableNameChecking -AllowClobber | out-null
        Write-Host Exchange PSSession loaded successfully! -ForegroundColor magenta
    }
    if ($Start){
        Set-ServerComponentState $env:COMPUTERNAME -Component HubTransport -State Draining -Requester Maintenance
        Set-ServerComponentState $env:COMPUTERNAME -Component ServerWideOffline -State InActive -Requester Maintenance
        Redirect-Message -Server $env:COMPUTERNAME -Target (get-exchangeserver |Where-Object Name -ne $env:COMPUTERNAME| Get-Random).fqdn -Confirm:$false -ErrorAction SilentlyContinue
        Suspend-ClusterNode -Name $env:COMPUTERNAME -ErrorAction silentlycontinue
        Set-MailboxServer $env:COMPUTERNAME -DatabaseCopyActivationDisabledAndMoveNow $true
        Set-MailboxServer $env:COMPUTERNAME -DatabaseCopyAutoActivationPolicy Blocked
        while (Get-MailboxDatabaseCopyStatus | Where-Object status -eq "mounted"){
            foreach ($mb in (Get-MailboxDatabaseCopyStatus | Where-Object status -eq "mounted")) {
                Move-ActiveMailboxDatabase -Server $env:COMPUTERNAME -Confirm:$false
            }
        }
        ""
        Write-Host "$env:COMPUTERNAME ComponentState HubTransport is" (Get-ServerComponentState $env:COMPUTERNAME -Component HubTransport).State "(Should Inactive)"
        Write-Host "$env:COMPUTERNAME ComponentState ServerWideOffline is" (Get-ServerComponentState $env:COMPUTERNAME -Component ServerWideOffline).state "(Should InActive)" 
        Write-Host "$env:COMPUTERNAME DatabaseCopyActivationDisabledAndMoveNow is" (Get-MailboxServer $env:COMPUTERNAME).DatabaseCopyActivationDisabledAndMoveNow "(Should True)"
        Write-Host "$env:COMPUTERNAME DatabaseCopyAutoActivationPolicy is" (Get-MailboxServer $env:COMPUTERNAME).DatabaseCopyAutoActivationPolicy "(Should Blocked)"
        ""
        if ($DB=(Get-MailboxDatabaseCopyStatus -Server $env:COMPUTERNAME | Where-Object Status -eq "Mounted").name){
            Write-Host "You Have Some Bases Mounted!!! $DB" -ForeGround RED
        }
        Else {
            Write-Host "You Have No Bases Mounted!!!" -ForeGround GREEN
        }
    }
    
    if ($Stop){
        $Missed=Get-MailboxDatabaseCopyStatus -Server $env:COMPUTERNAME  |Where-Object {($_.Status -ne "Mounted") -and ($_.ActivationPreference -eq 1)}
        Write-Host "Prepearing to activate server components" -Foreground GREEN
        Set-ServerComponentState $env:COMPUTERNAME -Component ServerWideOffline -State Active -Requester Maintenance
        Resume-ClusterNode -Name $env:COMPUTERNAME -ErrorAction silentlycontinue
        Set-MailboxServer $env:COMPUTERNAME -DatabaseCopyAutoActivationPolicy Unrestricted
        Set-MailboxServer $env:COMPUTERNAME -DatabaseCopyActivationDisabledAndMoveNow $false
        Set-ServerComponentState $env:COMPUTERNAME -Component HubTransport -State Active -Requester Maintenance
        Start-Sleep 5
        ""
        Write-Host "$env:COMPUTERNAME ComponentState HubTransport is" (Get-ServerComponentState $env:COMPUTERNAME -Component HubTransport).State "(Should Active)"
        Write-Host "$env:COMPUTERNAME ComponentState ServerWideOffline is" (Get-ServerComponentState $env:COMPUTERNAME -Component ServerWideOffline).state "(Should Active)"
        Write-Host "$env:COMPUTERNAME DatabaseCopyActivationDisabledAndMoveNow is" (Get-MailboxServer $env:COMPUTERNAME).DatabaseCopyActivationDisabledAndMoveNow "(Should False)"
        Write-Host "$env:COMPUTERNAME DatabaseCopyAutoActivationPolicy is" (Get-MailboxServer $env:COMPUTERNAME).DatabaseCopyAutoActivationPolicy "(Should Unrestricted)"
        if ($Missed){
            Get-MailboxDatabaseCopyStatus * -Active | Format-Table Name, Status, MailboxServer,ActivationPreference
            Write-Host "Prepearing to switch back Active Databases" -Foreground GREEN
            Start-Sleep 5
            while (
                $Queue=Get-MailboxDatabaseCopyStatus -Server $env:COMPUTERNAME  |Where-Object ReplayQueueLength -gt 10){
                    Write-Host "Waiting for ReplayQueueLength" -ForegroundColor Yellow
                    $Queue| Select-Object Name, ReplayQueueLength
                    Start-Sleep 10
                }
            foreach ($mbx in $Missed.DatabaseName){
                Move-ActiveMailboxDatabase -SkipAllChecks -Identity $mbx -ActivateOnServer $env:COMPUTERNAME -Confirm:$false
            }
        }
        Get-MailboxDatabaseCopyStatus * -Active | Format-Table Name, Status, MailboxServer, ActivationPreference
    }
}
