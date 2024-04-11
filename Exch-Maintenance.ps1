function global:Exch-Maintenance {

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
