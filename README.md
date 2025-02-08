# SQL Server Rename & Alias Management Utility

A PowerShell script to automate SQL Server instance renaming and synchronize SQL Native Client aliases across multiple servers.

---

## 📌 Features

- **SQL Instance Renaming**  
  Safely renames SQL Server instances using `sp_dropserver` and `sp_addserver`.
  
- **Computer Name Management**  
  Optional Windows computer rename to match SQL Server name.

- **Alias Synchronization**  
  Updates SQL Native Client aliases on:
  - Local server
  - Remote servers (via SMB)

- **Safety Mechanisms**  
  - Automatic system database backups
  - Connection termination with retry logic
  - Emergency multi-user mode restoration

---

## ⚙️ Prerequisites

- **PowerShell 5.1+** (Windows)
- **Administrative Rights** on all target servers
- **SQL Server Management Objects** (SMO)
- **Network Access**:
  - Port 445 (SMB) for remote servers
  - SQL Server ports (default: 1433)
- **Credentials**:
  - Local admin on SQL Server
  - Domain admin for remote servers

---

## 🚀 Installation

1. **Save the script**:
    ```powershell
    Invoke-WebRequest -Uri "<https://raw.githubusercontent.com/mohsinis/SQL-Server-Rename-Manager/refs/heads/main/Complete-SqlRename.ps1>" -OutFile "Complete-SqlRename.ps1"
    ```

2. **Enable script execution**:
    ```powershell
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
    ```

---

## 🖥️ Usage

### Basic Local Rename
```powershell
.\Complete-SqlRename.ps1 -NewServerName "NEW-SQL-01"
```

### Full Rename with Computer Name Change
```powershell
.\Complete-SqlRename.ps1 -NewServerName "NEW-SQL-01" -RenameComputer
```

### Rename with Remote Alias Updates
```powershell
.\Complete-SqlRename.ps1 -NewServerName "NEW-SQL-01" -RemoteServers "APP-01","APP-02"
```
## 📋 Parameters

| Parameter         | Description                                  | Example                      |
|-------------------|----------------------------------------------|------------------------------|
| `-NewServerName`  | Target SQL Server name (Mandatory)           | `-NewServerName "SQL-PROD-01"` |
| `-SqlInstance`    | SQL instance name (Default: local instance)  | `-SqlInstance ".\SQL2019"`     |
| `-RenameComputer` | Rename Windows computer to match SQL name    | `-RenameComputer`             |
| `-RemoteServers`  | Comma-separated list of remote servers       | `-RemoteServers "WEB-01","APP-02"` |

## 🔍 Post-Rename Checklist

1. Update application connection strings
2. Modify linked server configurations
3. Update SQL Agent jobs and SSIS packages
4. Verify replication/AlwaysOn configurations
5. Test client connectivity using aliases
6. Update monitoring systems and documentation

## 🚨 Troubleshooting

### Connection Failures
```powershell
Test-NetConnection -ComputerName <SERVER> -Port 445
Get-Service -ComputerName <SERVER> -Name RemoteRegistry
```
### Access Denied Errors

- Ensure Domain Admin credentials  
- Verify registry write permissions  

### Aliases Not Found

```powershell
reg query \\<SERVER>\HKLM\SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo
```

## ⚠️ Disclaimer

- Test thoroughly in non-production environments
- Ensure valid backups before execution
- Run during maintenance windows
- Notify dependent teams before execution

## 📜 License
This project is licensed under the [MIT License](https://raw.githubusercontent.com/mohsinis/SQL-Server-Rename-Manager/main/LICENSE).

## 🏷️ Version
1.0.0 - Updated 2025-02-08





