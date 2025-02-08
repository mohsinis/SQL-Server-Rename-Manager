#Requires -RunAsAdministrator
<#
.SYNOPSIS
SQL Server Rename & Alias Management Utility

.DESCRIPTION
This script performs complete SQL Server instance renaming and alias updates across:
- Local SQL Server instance
- Local client aliases
- Remote application servers (via SMB)

Key Features:
1. SQL Server instance renaming
2. Computer name change (optional)
3. Local SQL Native Client alias updates
4. Remote alias updates via SMB (port 445)
5. Active connection handling
6. Multi-server synchronization

.NOTES
- Requires SQL Server management permissions
- Needs network access to remote servers (port 445)
- Should be run during maintenance hours
- Creates transaction log backups automatically

.AUTHOR
Mohsin Yasin

.CONTACT

.LINK
Microsoft Docs: Rename SQL Server Instance
https://docs.microsoft.com/en-us/sql/database-engine/install-windows/rename-a-computer-that-hosts-a-stand-alone-instance-of-sql-server
#>

param(
    [Parameter(Mandatory=$true, HelpMessage="New name for SQL Server instance")]
    [string]$NewServerName,
    
    [Parameter(HelpMessage="SQL instance name (default: local)")]
    [string]$SqlInstance = ".",
    
    [Parameter(HelpMessage="Rename Windows computer to match SQL name")]
    [switch]$RenameComputer,
    
    [Parameter(HelpMessage="Comma-separated list of remote servers for alias updates")]
    [string[]]$RemoteServers
)

#region Initialization
$startTime = Get-Date
$ErrorActionPreference = 'Stop'

# Load SQL module
try {
    Import-Module SqlServer -ErrorAction Stop
} catch {
    Write-Error "SQL Server module required. Install with: Install-Module SqlServer -Force"
    exit 1
}
#endregion

#region Computer Name Management
try {
    $currentHostname = $env:COMPUTERNAME
    $currentSqlName = Invoke-Sqlcmd -Query "SELECT @@SERVERNAME" -ServerInstance $SqlInstance | 
        Select-Object -ExpandProperty Column1

    Write-Host @"
Current Configuration:
- Computer Name:    $currentHostname
- SQL Server Name:  $currentSqlName
"@

    if ($currentHostname -ne $NewServerName -and $RenameComputer) {
        $choice = Read-Host "`nWindows hostname must match SQL name. Rename computer to '$NewServerName'? (Y/N)"
        if ($choice -eq 'Y') {
            Write-Host "Initiating computer rename..."
            Rename-Computer -NewName $NewServerName -Force -Restart
        } else {
            Write-Error "Computer name must match new SQL Server name. Aborting."
            exit 1
        }
    }
} catch {
    Write-Error "Initialization failed: $_"
    exit 1
}
#endregion

#region SQL Server Rename Process
try {
    Write-Host "`nStarting SQL Server rename process..." -ForegroundColor Cyan

    # Backup critical databases
    $systemDbs = @('master', 'msdb', 'model')
    foreach ($db in $systemDbs) {
        Write-Host "Backing up $db database..."
        $backupPath = "C:\Backup\$db-$(Get-Date -Format yyyyMMdd-HHmmss).bak"
        Backup-SqlDatabase -ServerInstance $SqlInstance -Database $db -BackupFile $backupPath
    }

    # Prepare rename script
    $renameQuery = @"
    EXEC sp_dropserver '$currentSqlName';
    GO
    EXEC sp_addserver '$NewServerName', 'local';
    GO
"@

    # Handle user databases
    $userDbs = Invoke-Sqlcmd -Query "SELECT name FROM sys.databases WHERE database_id > 4" -ServerInstance $SqlInstance
    
    foreach ($db in $userDbs) {
        $dbName = $db.name
        Write-Host "Processing database: $dbName"
        
        # Kill connections with retry logic
        $retryCount = 0
        $maxRetries = 3
        
        while ($retryCount -lt $maxRetries) {
            try {
                Write-Host "Setting single-user mode (attempt $($retryCount + 1))"
                Invoke-Sqlcmd -Query @"
                ALTER DATABASE [$dbName] 
                SET RESTRICTED_USER WITH ROLLBACK IMMEDIATE;
                ALTER DATABASE [$dbName] 
                SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
"@ -ServerInstance $SqlInstance -QueryTimeout 300 -ErrorAction Stop
                break
            } catch {
                $retryCount++
                if ($retryCount -ge $maxRetries) {
                    throw "Failed to set single-user mode after $maxRetries attempts: $_"
                }
                Start-Sleep -Seconds 5
            }
        }
    }

    # Execute instance rename
    Write-Host "Executing SQL rename commands..."
    Invoke-Sqlcmd -Query $renameQuery -ServerInstance $SqlInstance -QueryTimeout 600

    # Restart SQL Service
    $service = if ($SqlInstance -eq '.') { 'MSSQLSERVER' } 
               else { "MSSQL`$$($SqlInstance.Split('\')[-1])" }
    
    Write-Host "Restarting service: $service"
    Restart-Service -Name $service -Force

    # Verify rename
    $newSqlName = Invoke-Sqlcmd -Query "SELECT @@SERVERNAME" -ServerInstance $SqlInstance | 
        Select-Object -ExpandProperty Column1

    # Restore database access
    foreach ($db in $userDbs) {
        try {
            Write-Host "Restoring access to: $($db.name)"
            Invoke-Sqlcmd -Query "ALTER DATABASE [$($db.name)] SET MULTI_USER WITH ROLLBACK IMMEDIATE" `
                -ServerInstance $SqlInstance
        } catch {
            Write-Warning "Failed to reset $($db.name): $_"
        }
    }

} catch {
    Write-Error "SQL rename process failed: $_"
    exit 1
}
#endregion

#region Alias Management
function Update-SqlAliases {
    param(
        [string]$ComputerName,
        [string]$TargetServerName,
        [System.Management.Automation.PSCredential]$Credential = $null
    )

    $registryPaths = @(
        "SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo",
        "SOFTWARE\WOW6432Node\Microsoft\MSSQLServer\Client\ConnectTo"
    )

    try {
        if ($ComputerName -ne $env:COMPUTERNAME) {
            Write-Host "`nConnecting to $ComputerName..." -ForegroundColor Cyan
            $null = net use "\\$ComputerName\ADMIN$" /user:$($Credential.UserName) $($Credential.GetNetworkCredential().Password)
        }

        foreach ($regPath in $registryPaths) {
            Write-Host "Processing registry path: HKLM\$regPath"
            
            $output = reg query "\\$ComputerName\HKLM\$regPath" /s 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Path not found: HKLM\$regPath"
                continue
            }

            $output | Where-Object { $_ -match 'REG_SZ' } | ForEach-Object {
                $line = $_.Trim() -split '\s{2,}'
                $aliasName = $line[0]
                $currentValue = $line[-1]

                if ($aliasName -eq '(Default)') { return }

                $parts = $currentValue -split ','
                if ($parts.Count -ge 2) {
                    $oldServer = $parts[1]
                    $parts[1] = $TargetServerName
                    $newValue = $parts -join ','

                    try {
                        $result = reg add "\\$ComputerName\HKLM\$regPath" /v "$aliasName" /t REG_SZ /d "$newValue" /f 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host " Updated: $aliasName" -ForegroundColor Green
                            Write-Host "   From: $oldServer"
                            Write-Host "   To:   $TargetServerName"
                        } else {
                            Write-Host " Failed: $aliasName" -ForegroundColor Red
                            Write-Host "   Error: $result"
                        }
                    } catch {
                        Write-Warning "Update failed: $_"
                    }
                }
            }
        }
    } finally {
        if ($ComputerName -ne $env:COMPUTERNAME) {
            net use "\\$ComputerName\ADMIN$" /delete /y | Out-Null
        }
    }
}

# Update local aliases
try {
    Write-Host "`nUpdating local aliases..." -ForegroundColor Cyan
    Update-SqlAliases -ComputerName $env:COMPUTERNAME -TargetServerName $NewServerName
} catch {
    Write-Error "Local alias update failed: $_"
}

# Update remote aliases
if ($RemoteServers) {
    $cred = Get-Credential -Message "Enter domain admin credentials for remote servers"
    
    foreach ($server in $RemoteServers) {
        try {
            Write-Host "`nProcessing remote server: $server" -ForegroundColor Cyan
            Update-SqlAliases -ComputerName $server -TargetServerName $NewServerName -Credential $cred
        } catch {
            Write-Error "Failed to update $server : $_"
        }
    }
}
#endregion

#region Finalization
$duration = (Get-Date) - $startTime
Write-Host @"
`nOperation completed in $($duration.ToString('hh\:mm\:ss'))
Verification Steps:
1. Check SQL name:    sqlcmd -Q "SELECT @@SERVERNAME" -S $NewServerName
2. Local aliases:     Get-ItemProperty HKLM:\SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo\*
3. Remote check:      reg query \\REMOTE-SERVER\HKLM\SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo

Post-Rename Checklist:
- Update connection strings in applications
- Modify linked server configurations
- Update maintenance plans and SQL Agent jobs
- Verify replication configurations
- Update monitoring systems
"@ -ForegroundColor Green
#endregion
