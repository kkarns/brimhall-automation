#######################################################################################################################
## 
## name:        
##      brimhall-automation.ps1
##
##      powershell script to run a remote security script by Jason Brimhall, via sqlcmd and powershell wrapper.
##      credits to Jason Brimhall for the idea from his T-SQL Tuesday blog post: 
##          http://jasonbrimhall.info/2018/07/10/just-cant-cut-that-cord/
##      
## syntax:
##      .\brimhall-automation.ps1
##
## dependencies:
##      windows task to run this every day 
##      set of permanent links to destination linked servers, (not on-the-fly links this time as in sp_Blitz automation)
##
## updated:
##      -- Tuesday, October 2, 2018 3:40 PM         -- initial commit
##
## todo:
##

## Functions ##########################################################################################################

##########################################################################################################
##
## LogWrite - write messages to log file 
##
Function LogWrite
{
   Param ([string]$logstring)
   Add-content $Logfile -value $logstring 
}


##########################################################################################################
##
## ExtractPassword - Get a password from the encrypted credentials file 
##
Function ExtractPassword
{
    Param
    (
         [Parameter(Mandatory=$true, Position=0)]   [string] $tryCredentialsFile,
         [Parameter(Mandatory=$true, Position=1)]   [string] $tryServerUsername,
         [Parameter(Mandatory=$true, Position=2)] [AllowEmptyString()]  [string] $tryServerPassword
    )

##
## Get the destination password from the encrypted credentials file 
## 
## https://blogs.technet.microsoft.com/robcost/2008/05/01/powershell-tip-storing-and-using-password-credentials/
## note the pre-requisite (as explained in the blog)
##     credentials.txt   
## which comes from:  
##     read-host -assecurestring | convertfrom-securestring | out-file credentials-xyz.txt
##

if(![System.IO.File]::Exists($tryCredentialsFile))
    {
    echo ("Error. Halted. Missing encrypted credentials file.")
    LogWrite ("Error. Halted. Missing encrypted credentials file.")
    throw ("Error. Halted. Missing encrypted credentials file.")
    }

$passwordSecureString = get-content $tryCredentialsFile | convertto-securestring
$credentialsObject = new-object -typename System.Management.Automation.PSCredential -argumentlist $tryServerUsername,$passwordSecureString
LogWrite ("credentials            :  " + $credentialsObject)
LogWrite ("decrypted username     :  " + $credentialsObject.GetNetworkCredential().UserName)
LogWrite ("decrypted password     :  " + "<redacted>")          ## redact this asap  + $credentialsObject.GetNetworkCredential().password
$tryServerPassword = $credentialsObject.GetNetworkCredential().password

return $tryServerPassword

}


##########################################################################################################
##
## RunBrimhall - run Jason Brimhall query http://jasonbrimhall.info/2018/07/10/just-cant-cut-that-cord/
##
Function RunBrimhall
{
    Param
    (
         [Parameter(Mandatory=$true, Position=0)]       [string] $serverUsername,
         [Parameter(Mandatory=$true, Position=1)]       [string] $serverPassword,
         [Parameter(Mandatory=$true, Position=2)]       [string] $serverInstance,
         [Parameter(Mandatory=$true, Position=3)]       [string] $serverBrimhallInDb,
         [Parameter(Mandatory=$true, Position=4)]       [string] $targetLinkName,
         [Parameter(Mandatory=$true, Position=5)]       [int]    $nDays,
         [Parameter(Mandatory=$true, Position=6)]       [string] $outputDatabaseName,
         [Parameter(Mandatory=$true, Position=7)]       [string] $outputSchemaName,       
         [Parameter(Mandatory=$true, Position=8)]       [string] $outputTableName
    )

##
## use a "here string" aka "splat operator", insert the parameters into the sqlcmd command string
##
## sqlcmd -U BATMAN -P opensesame -S SRCSERVER   -d MASTER     -Q "EXEC sp_Brimhall @TargetLinkName = N'LINKED.SERVER.NAME', @NDays = 1, @OutputDatabaseName = N'MASTER', @OutputSchemaName   = N'dbo', @OutputTableName    = N'DefTracePermissions';"
##           ^^^^^^    ^^^^^^^^^^    ^^^^^^^^^^^    ^^^^^^^^^^                                          ^^^^^^^^^^^^^^^^^           ^^                          ^^^^^^                           ^^^                           ^^^^^^^^^^^^   
##           $sun      $spw          $sin           $sbd                                                $tln                        $nds                        $odn                             $osn                          $otn   
##
##  $sun  $serverUsername,      0  
##  $spw  $serverPassword,      1  
##  $sin  $serverInstance,      2  
##  $sbd  $serverBrimhallInDb,  3  
##  $tln  $targetLinkName,      4  
##  $nds  $nDays,               5  
##  $odn  $outputDatabaseName,  6  
##  $osn  $outputSchemaName,    7
##  $otn  $outputTableName      8
          
$command = @"
sqlcmd -U {0} -P {1} -S {2} -d {3} -Q "EXEC sp_Brimhall @TargetLinkName = N'{4}', @NDays = {5}, @OutputDatabaseName = N'{6}', @OutputSchemaName   = N'{7}', @OutputTableName    = N'{8}';"
"@ -f $serverUsername, $serverPassword, $serverInstance, $serverBrimhallInDb, $targetLinkName, $nDays, $outputDatabaseName, $outputSchemaName, $outputTableName    

echo "--------------------------------------"
$command
echo "--------------------------------------"
LogWrite ("command               :  " + "<redacted>" )  ## to troubleshoot temporarily replace this with $command ... or "<redacted>"

Invoke-Expression -Command:$command -OutVariable out | Tee-Object -Variable out
LogWrite ("output                :  " + $out)
}


## Main Code ##########################################################################################################

try {

##                      
## set local code path and initialize settings file 
##
$myDir = Split-Path -Parent $MyInvocation.MyCommand.Path
[xml]$ConfigFile = Get-Content "$myDir\Settings.xml"

## setup the logfile
$LogDir = $myDir + "\logs"
if(-not ([IO.Directory]::Exists($LogDir))) {New-Item -ItemType directory -Path $LogDir}
$Logfile = ($LogDir + "\brimhall-automation-" + $(get-date -f yyyy-MM-dd-HHmmss) + ".log")
echo "results are logged to:  "$Logfile 
LogWrite ("Started at:  " + $(get-date -f yyyy-MM-dd-HHmmss))
$date1 = Get-Date

##
## Get linked server name variables from the settings.xml file, and read into hashtable
##

$serversHash = @{}
$i = 0
foreach ($setting in $ConfigFile.SelectNodes("/brimhall_automation/*") ) {
    if($setting.Name -Match 'serverInstance*')
    {
        $serversHash[$i] = $setting.InnerText
        LogWrite ("($i):  " + $setting.InnerText )
        $i++
    }
}

$outputServer           = $ConfigFile.brimhall_automation.outputServer
$outputDatabaseName     = $ConfigFile.brimhall_automation.outputDatabaseName 
$outputServerUser       = $ConfigFile.brimhall_automation.outputServerUser   
$outputInstance         = $ConfigFile.brimhall_automation.outputInstance   
$credentialsFileDest    = $ConfigFile.brimhall_automation.credentialsFileDest
$outputSchemaName       = $ConfigFile.brimhall_automation.outputSchemaName    
$outputTableName        = $ConfigFile.brimhall_automation.outputTableName    

LogWrite ("outputServer        :  " + $outputServer)
LogWrite ("outputDatabaseName  :  " + $outputDatabaseName)
LogWrite ("outputServerUser    :  " + $outputServerUser)
LogWrite ("outputInstance      :  " + $outputInstance)
LogWrite ("credentialsFileDest :  " + $credentialsFileDest)
LogWrite ("outputSchemaName    :  " + $outputSchemaName)
LogWrite ("outputTableName     :  " + $outputTableName)



##
## same for all connections -- extract password for destination linked server  
##

$tryCredentialsFile = $MyDir+ "\" + $credentialsFileDest
$tryServerUsername  = $outputServerUser
$tryServerPassword  = $outputServerPass
$outputServerPass = ExtractPassword -tryCredentialsFile $tryCredentialsFile -tryServerUsername $tryServerUsername -tryServerPassword $tryServerPassword

$nDays = 1

for($i = 0; $i -lt $serversHash.Count; $i++) 
{ 
    $targetLinkName = $serversHash[$i]
    $targetLinkName
    
    ## call RunBrimhall 
    RunBrimhall -serverUsername $outputServerUser -serverPassword $outputServerPass -serverInstance $outputInstance -serverBrimhallInDb $outputDatabaseName -targetLinkName $targetLinkName -nDays $nDays -outputDatabaseName $outputDatabaseName -outputSchemaName $outputSchemaName -outputTableName $outputTableName
} 


throw ("Halted.  This is the end.  Who knew.")


}
Catch {
    ##
    ## log any error
    ##    
    LogWrite $Error[0]
}
Finally {

    ##
    ## go back to the software directory where we started
    ##
    set-location $myDir

    LogWrite ("finished at:  " + $(get-date -f yyyy-MM-dd-HHmmss))
}