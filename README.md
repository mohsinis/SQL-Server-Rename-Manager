# SQL Server Rename & Alias Management Utility

A PowerShell script to automate SQL Server instance renaming and synchronize SQL Native Client aliases across multiple servers.

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

## 🚀 Installation

1. Save the script:
   ```powershell
   Invoke-WebRequest -Uri <SCRIPT_URL> -OutFile "Complete-SqlRename.ps1"
