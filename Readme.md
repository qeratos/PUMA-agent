# PUMA - Powershell kUMA agent with others SIEM support


## Description
This project aimed to collect all logs from Windows event journals, pack them in to CEF and send by UDP to your SIEM. 

Here used [WinAPI Documentation](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/advanced-security-auditing-faq).

## How to use
1. You need to create collector in your SIEM or other system.
2. Allow UDP traffic to collector specifed port.
3. Download this code and copy to your directory(Must be disk C:).


## Dependences
There is no dependeces, only operational system must be Windows.


## Installation 
1. Download repo to your PC.
2. Unzip it to your work directory (Must be disk C:/PUMA.ps1).
3. It can be started using PowerShell or added in to scheduler. For adding in to scheduler follow **Creating task guide**.


## Creating task guide
