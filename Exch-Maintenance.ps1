function global:Exch-Maintenance {    
    param(
        [Parameter(ParameterSetName='START',Mandatory=$true)][switch]$Start,
        [Parameter(ParameterSetName='STOP',Mandatory=$true)][switch]$Stop,
        [Parameter(Mandatory)]$Exch
    )

    $WarningActionPreference = "SilentlyContinue"
    $count=0
    while ((-Not(Get-PSSession|Where-Object ConfigurationName -eq "Microsoft.Exchange")) -and ($count -ne "5")) {
        $count++
        $exch1= (Get-ADComputer -Filter "name -like 's-ex-0*'").name| Get-Random
        try{
            Write-Host Trying to connect $exch1...
            $session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "http://$exch1/Powershell" -Authentication Kerberos -ErrorAction Stop
            Import-PSSession $session -DisableNameChecking -AllowClobber -ErrorAction Stop | out-null
            Write-Host Exchange PSSession loaded successfully! -ForegroundColor magenta
        }
        Catch{$Error[0].Exception.Message }
    }
    if ($Start){
        Set-ServerComponentState $Exch -Component HubTransport -State Draining -Requester Maintenance
        Set-ServerComponentState $Exch -Component ServerWideOffline -State InActive -Requester Maintenance
        Redirect-Message -Server $Exch -Target (get-exchangeserver |Where-Object Name -ne $Exch| Get-Random).fqdn -Confirm:$false -ErrorAction SilentlyContinue
        Suspend-ClusterNode -Name $Exch -ErrorAction silentlycontinue
        Set-MailboxServer $Exch -DatabaseCopyActivationDisabledAndMoveNow $true
        Set-MailboxServer $Exch -DatabaseCopyAutoActivationPolicy Blocked
        while (Get-MailboxDatabaseCopyStatus -Server $Exch| Where-Object status -eq "mounted"){Move-ActiveMailboxDatabase -Server $Exch -Confirm:$false}
        ""
        Write-Host "$Exch ComponentState HubTransport is" (Get-ServerComponentState $Exch -Component HubTransport).State "(Should Inactive)"
        Write-Host "$Exch ComponentState ServerWideOffline is" (Get-ServerComponentState $Exch -Component ServerWideOffline).state "(Should InActive)" 
        Write-Host "$Exch DatabaseCopyActivationDisabledAndMoveNow is" (Get-MailboxServer $Exch).DatabaseCopyActivationDisabledAndMoveNow "(Should True)"
        Write-Host "$Exch DatabaseCopyAutoActivationPolicy is" (Get-MailboxServer $Exch).DatabaseCopyAutoActivationPolicy "(Should Blocked)"
        ""
        if ($DB=(Get-MailboxDatabaseCopyStatus -Server $Exch | Where-Object Status -eq "Mounted").name){
            Write-Host "You Have Some Bases Mounted!!! $DB" -ForeGround RED
        }
        Else {Write-Host "You Have No Bases Mounted!!!" -ForeGround GREEN }
    }
    
    if ($Stop){
        Write-Host "Prepearing to activate server components" -Foreground GREEN
        Set-ServerComponentState $Exch -Component ServerWideOffline -State Active -Requester Maintenance
        Resume-ClusterNode -Name $Exch -ErrorAction silentlycontinue
        Set-MailboxServer $Exch -DatabaseCopyAutoActivationPolicy Unrestricted
        Set-MailboxServer $Exch -DatabaseCopyActivationDisabledAndMoveNow $false
        Set-ServerComponentState $Exch -Component HubTransport -State Active -Requester Maintenance
        Start-Sleep 5
        ""
        Write-Host "$Exch ComponentState HubTransport is" (Get-ServerComponentState $Exch -Component HubTransport).State "(Should Active)"
        Write-Host "$Exch ComponentState ServerWideOffline is" (Get-ServerComponentState $Exch -Component ServerWideOffline).state "(Should Active)"
        Write-Host "$Exch DatabaseCopyActivationDisabledAndMoveNow is" (Get-MailboxServer $Exch).DatabaseCopyActivationDisabledAndMoveNow "(Should False)"
        Write-Host "$Exch DatabaseCopyAutoActivationPolicy is" (Get-MailboxServer $Exch).DatabaseCopyAutoActivationPolicy "(Should Unrestricted)"
        $Missed=Get-MailboxDatabaseCopyStatus -Server $Exch  |Where-Object {($_.Status -ne "Mounted") -and ($_.ActivationPreference -eq 1)}
        if ($Missed){
            $Missed| Format-Table Name, Status, MailboxServer,ActiveDatabaseCopy
            Write-Host "Prepearing to switch back Active Databases" -Foreground GREEN
            Start-Sleep 5
            while (
                $Queue=$Missed|Get-MailboxDatabaseCopyStatus |Where-Object ReplayQueueLength -gt 10){
                    Write-Host "Waiting for ReplayQueueLength" -ForegroundColor Yellow
                    $Queue| Select-Object Name, ReplayQueueLength
                    Start-Sleep 10
                }
            foreach ($mbx in $Missed.DatabaseName){Move-ActiveMailboxDatabase -SkipAllChecks -Identity $mbx -ActivateOnServer $Exch -Confirm:$false}
        }
        Get-MailboxDatabaseCopyStatus -Active | Format-Table Name, Status, MailboxServer,ActiveDatabaseCopy, ActivationPreference
    }
}

