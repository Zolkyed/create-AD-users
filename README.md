# Active Directory User Management Script

This PowerShell script automates the creation and disabling of Active Directory (AD) user accounts based on a CSV file.

--- 

## Requirements

- PowerShell with Active Directory Module
- Administrator privileges
- SMTP details for email notifications

--- 

## Parameters

- `-diff`: Export users to be created or disabled to CSV files.
- `-nodesac`: Export only users to be disabled.
- `-nomail`: Prevent email notifications.