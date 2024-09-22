# Config
$operationalPath = "C:\Puma-agent\"
$logPath = $operationalPath + "PumaAgentLog.log"
$bufferPath = $operationalPath + "PumaAgentBuffer.buff"
$kumaIp = "your KUMA adress"
$kumaPort =  11234 #Kuma collector port
$logRotate = 30
$logMaxSize = 256
$notificationFlag = $false
#TODO Добавить в конфиг и функционал выгрузку логов из списка кастомных журналов имена должны быть в массиве и проверку на наличие этих журналов

# ----------------------------------------------------------------------------------| NOT TO BE ALTERED |---------------------------------------------------------------------------------#
# CEF header configuration
$Version = "0.5"
$DeviceVendor = "qeratos"
$DeviceProduct = "Puma-agent"
$DeviceVersion = "2.1.3"
$SignatureID = "1337"
# Local variables
$lastEventId = $null
$nConnection = $false
$buffer = [System.Collections.ArrayList]@()
$keepAliveTime = $null
$timeout = 6000000
$rotatePrevDate = $null
$rotateTimeout = 1
$treshold = $true
$notificationTimeout = 6000000
$previousNotification = $null

$logEvents = @{}
$firstStart = $true
$lastEvents = @{}

$lastNetworkTry = $null
$networkTimeout = 30000000
$isNetwork = $true

$computer = $env:computername.ToLower()
# Send by UDP
# EndPoint - destination ip address 
# Port - destination port
# Message - data for udp transmition
function Send-Udp{
      Param ([string] $EndPoint, 
      [int] $Port, 
      [string] $Message)

      $IP = [System.Net.Dns]::GetHostAddresses($EndPoint) 
      $Address = [System.Net.IPAddress]::Parse($IP) 
      $EndPoints = New-Object System.Net.IPEndPoint($Address, $Port) 
      $Socket = New-Object System.Net.Sockets.UDPClient 
      $EncodedText = [Text.Encoding]::UTF8.GetBytes($Message) 
      $SendMessage = $Socket.Send($EncodedText, $EncodedText.Length, $EndPoints) 
      $Socket.Close() 
}

# Function to create CEF header by standart
function Create-CEF{
        Param ([string] $id,
        [string] $machine,
        [string] $entry,
        [string] $inst,
        [string] $usr,
        [string] $msg,
        [string] $time,
        [string] $Severity)

        $Name = $env:computername.ToLower()
        $buffer = "CEF:$Version|$DeviceVendor|$DeviceProduct|$DeviceVersion|$SignatureID|$Name|$Severity|"
        $msg = $msg -replace '\n', ''
        $msg = $msg -replace '\s{2,}', ' '
        $buffer += "EventID=$id MachineName=$machine EntryType=$entry InstanceId=$inst TimeGenerated=$time UserName=$usr Message=$msg"
        return $buffer
}

# Function wich creates message in CEF format from event object
# eventObj event object
function Prepare-Event {
    param (
        $eventObj
    ) 
    $eventBuffered = Select-Object -InputObject $eventObj -Property EventID, MachineName, EntryType, Message, InstanceId, TimeGenerated, UserName
    $data = Create-CEF -id $eventBuffered.EventID -machine $eventBuffered.MachineName -entry $eventBuffered.EntryType -inst $eventBuffered.InstanceId -usr $eventBuffered.UserName -msg $eventBuffered.Message -time $eventBuffered.TimeGenerated-Severity 4
    return $data
}

# Function wich checks size, date of creation LOG and BUFF files and if it bigger than in config -> arcieved it and move in to Archieve
function Rotation-Logs{
    param()
    $ifRotatedPath = ' '
    $today = Get-Date
    $logCreationDate = Get-ItemPropertyValue -Path $logPath -Name CreationTime
    $logSizeMb = [int]((Select-Object -InputObject $(Get-Item -Path $logPath) -Property Length).Length / 1MB)
    $logDays = (New-TimeSpan -Start ($logCreationDate) -End  $today).Days

    $logBufferCreationDate = Get-ItemPropertyValue -Path $bufferPath -Name CreationTime
    $bufferSizeMb = [int]((Select-Object -InputObject $(Get-Item -Path $bufferPath) -Property Length).Length / 1MB)
    $logBufferDays = (New-TimeSpan -Start ($logBufferCreationDate) -End  $today).Days
    $logSizeMb
    $bufferSizeMb
    if (($logDays -ge $logRotate) -or ($logSizeMb -ge $logMaxSize)){
        $filename = $operationalPath + "Archieve\LOG-$DeviceProduct-[$($logCreationDate.ToShortDateString())]--$logDays.zip"
        $none = Compress-Archive -Path $logPath -Force -DestinationPath $filename -CompressionLevel Optimal
        $none = Remove-Item $logPath
        $none = New-Item -Path $logPath 
        $ifRotatedPath += " $filename"
    }

    if (($logBufferDays -ge $logRotate) -or ($bufferSizeMb -ge $logMaxSize)){
        $filename = $operationalPath + "Archieve\BUFFER-$DeviceProduct-[$($logCreationDate.ToShortDateString())]--$logDays.zip"
        $none = Compress-Archive -Path $bufferPath -Force -DestinationPath $filename -CompressionLevel Optimal 
        $none = Remove-Item $bufferPath
        $none = New-Item -Path $bufferPath 
        $ifRotatedPath += " $filename"
    }
    return $ifRotatedPath
}

# Function for enviroment preparing, creating directories and files
function Prepare-Enviroment{
    param()
    
    if (-not(Test-Path -Path $operationalPath)){
        $none = New-Item -Path $operationalPath -ItemType Directory
        $none = New-Item -Path $($operationalPath + 'Archieve') -ItemType Directory
        $none = New-Item -Path $bufferPath 
        $none = New-Item -Path $logPath 
    }else{
        if (-not(Test-Path -Path $bufferPath)){
            $none = New-Item -Path $bufferPath 
        }
        if (-not(Test-Path -Path $logPath )){
            $none = New-Item -Path $logPath 
        }
    }
}

# Function, wich notifies the user of the need to enable VPN-connection
function Show-Notification{
    param()

    Add-Type -AssemblyName System.Windows.Forms
    $global:balmsg = New-Object System.Windows.Forms.NotifyIcon
    $path = (Get-Process -id $pid).Path
    $balmsg.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
    $balmsg.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Warning
    $balmsg.BalloonTipTitle = "Warning $user"
    $user = (Get-ComputerInfo -Property CsUserName).CsUserName -replace '\w+\\',''
    if ((Get-NetAdapter | Where-Object {$_.InterfaceDescription -like "PANGP Virtual Ethernet Adapter*"} | Select-Object Status).Status -ieq "Disabled"){
        $balmsg.BalloonTipText = "There is no connection to $kumaIp, you must enable VPN"
    }else{
        $balmsg.BalloonTipText = "There is no connection to $kumaIp, check network connection!"
    }
    $balmsg.Visible = $true
    $balmsg.ShowBalloonTip(10000)

}

function Network-Supply{
    param(
        $data
    )

    if ($isNetwork){
        if ($nConnection -eq $true){
            # When network access appears, sends all events from the buffer
            if ($buffer.count -ne 0){
                $bufferedSize = $buffer.count
                $sendedEvents = [System.Collections.ArrayList]@()
                foreach ($bufferedEvent in $buffer){
                    Send-Udp -EndPoint $kumaIp -Port $kumaPort -Message (Prepare-Event -eventObj $bufferedEvent)
                    $sendedEvents.Add($bufferedEvent)
                }
                # A bit of logging, records information about sent events from the buffer
                $sendedFromBuffer = $sendedEvents.count
                (Get-Date -Format "MM:dd:yy HH:mm") + " - From buffer $bufferedSize sended successfully $sendedFromBuffer" | Out-File -Append -FilePath $logPath

                # Buffer free
                if ($sendedFromBuffer -ne 0){
                    foreach ($sendedEvent in $sendedEvents){
                        $buffer.Remove($sendedEvent)
                    }
                }
            }
            $nConnection = $false
        }
        # The main function of sending, triggered if everything is OK
        # Write-Host $data
        Send-Udp -EndPoint $kumaIp -Port $kumaPort -Message (Prepare-Event -eventObj $data)
        # Write-Host "With network $(Prepare-Event -eventObj $data)"
    }else{
        if ($notificationFlag){
            if([Double](Get-Date -UFormat %s) - $previousNotification -ge $notificationTimeout){
                $previousNotification = [Double](Get-Date -UFormat %s)
                Show-Notification
            }
        }

        # Triggered when there is no network access and records events both in the buffer for sending and in a file for further analysis
    
        Write-Host "Connection none $(Prepare-Event -eventObj $data)"
        $buffer.Add($(Prepare-Event -eventObj $data))
        $message = (Get-Date -Format "MM:dd:yy HH:mm") + ' - ' + (Prepare-Event -eventObj $data)
        $message | Out-File -Append -FilePath $bufferPath
        $nConnection = $true
    }

}



Prepare-Enviroment
# A little logging of agent startup
$message = (Get-Date -Format "MM:dd:yy HH:mm") + " - Work started!"
$message | Out-File -Append -FilePath $logPath
$message | Out-File -Append -FilePath $bufferPath

$logJournals = Get-EventLog -List 
$fireWallCtr = $(Get-WinEvent -LogName "Microsoft-Windows-Windows Firewall With Advanced Security/Firewall").Count
$NetworkCtr = $(Get-WinEvent -LogName "Microsoft-Windows-NetworkProfile/Operational").Count

Start-Sleep 1
Send-Udp -EndPoint $kumaIp -Port $kumaPort -Message "Started agent at $computer" 

# Main cycle
while ($true){
    foreach ($journal in $logJournals){
        $logEvents[$journal.Log] = $journal.Entries.Count
    }
    if ($fireWallCtr -ne $(Get-WinEvent -LogName "Microsoft-Windows-Windows Firewall With Advanced Security/Firewall").Count){
        $currentCtr = $(Get-WinEvent -LogName "Microsoft-Windows-Windows Firewall With Advanced Security/Firewall").Count
        $difference = $currentCtr - $fireWallCtr
        Write-Host "Diff: $difference Prev: $fireWallCtr Curr: $currentCtr"
        $lastEvent = Get-WinEvent -LogName "Microsoft-Windows-Windows Firewall With Advanced Security/Firewall" | Sort-Object -Property TimeCreated -Descending | Select-Object -First $difference -Property *
        if ($difference -ge 2){
            foreach ($event in $lastEvent){  
                Network-Supply -data $event
            }
        }else{
            Network-Supply -data $lastEvent
        }
                
        $fireWallCtr = $currentCtr
    }
    if($NetworkCtr -ne $(Get-WinEvent -LogName "Microsoft-Windows-NetworkProfile/Operational").Count){
        $currentCtr = $(Get-WinEvent -LogName "Microsoft-Windows-NetworkProfile/Operational").Count
        $difference = $currentCtr - $NetworkCtr
        $lastEvent = Get-WinEvent -LogName "Microsoft-Windows-NetworkProfile/Operational" | Sort-Object -Property TimeCreated -Descending | Select-Object -First $difference -Property *
        if ($difference -ge 2){
            foreach ($event in $lastEvent){
                Network-Supply -data $event
            }
        }else{
            Network-Supply -data $lastEvent
        }
        
        $NetworkCtr = $currentCtr
    }

    
    foreach ($journal in $logEvents.GetEnumerator()){
        if ($journal.value -ne $lastEvents[$journal.key]){
            if (-not $firstStart){
                $difference = $journal.value - $($lastEvents[$journal.key])
                $lastEvent = Get-EventLog -LogName $journal.key -Newest $difference
                if ($difference -ge 2){
                    foreach ($event in $lastEvent){
                        Network-Supply -data $event
                    }
                }else{
                    Network-Supply -data $lastEvent
                }
                
                # Write-Host "Journal $($journal.key) and values $($journal.value)  last: $($lastEvents[$journal.key]) and difference: $difference"
            }

            $lastEvents[$journal.key] = $journal.value
        }
    }
    $firstStart = $false

    # Triggered once per minute and sends a "KeepAlive PC-NAME" event to check for functionality
    if([Double](Get-Date -UFormat %s) - $keepAliveTime -ge $timeout){
        $keepAliveTime = [Double](Get-Date -UFormat %s)   
        Send-Udp -EndPoint $kumaIp -Port $kumaPort -Message "KeepAlive $computer"
    }
    # Reset date when the 1st of a new month arrives
    if([int](Get-Date -UFormat %d) -ieq 1){
        $rotatePrevDate = 0
    }
    # Triggered once a day and starts the log rotation check mechanism
    if ([Double](Get-Date -UFormat %d) - $rotatePrevDate -ge $rotateTimeout) {
        $rotatePrevDate = [Double](Get-Date -UFormat %d)
        $message = (Get-Date -Format "MM:dd:yy HH:mm") + " - Log check!"
        $path = Rotation-Logs
        if ($path -inotlike ' 0 0'){ 
            $path = $path -replace '\s\d+\s\d+\s', ''
            $message += " - Rotated to: $path"
        }
        $message | Out-File -Append -FilePath $logPath
    }
    
    # Network event handler for access and loss + logging is triggered once every 30 seconds
    if([Double](Get-Date -UFormat %s) - $lastNetworkTry -ge $networkTimeout){
        $lastNetworkTry = [Double](Get-Date -UFormat %s)
        #$message = (Get-Date -Format "MM:dd:yy HH:mm") + " - Network test!"
        # $message | Out-File -Append -FilePath $logPath
        if (Test-Connection -ComputerName $kumaIp -Count 1 -Quiet){
            $isNetwork = $true
            if ($treshold -eq $falses){
                $treshold = $true
                $message = (Get-Date -Format "MM:dd:yy HH:mm") + " - Connection restored!"
                $message | Out-File -Append -FilePath $logPath
            }
        }else{
            $isNetwork = $false
            if ($treshold -eq $true){
                $treshold = $false
                $message = (Get-Date -Format "MM:dd:yy HH:mm") + " - Connection broked!"
                $message | Out-File -Append -FilePath $logPath
            }
        }
    }
    
    # 1 second delay to reduce resource consumption (AMD RYZEN 5625U without delay 10%, with delay - about 1%)
    Start-Sleep 1 
}