# Printer Remediation & Deployment Automation

CSV-driven Win32 app packaging, Graph API automation, and cross-platform (Windows + macOS)
network printer deployment via Intune. Covers 14+ Xerox Phaser 3330 units, three AltaLink
MFPs, one VersaLink test unit, and one WorkCentre unit — deployed, broken, root-caused, and
fixed across two platforms.

## Problem

Windows Win32 apps for network printers (`Printer - 14-17`, `Printer - 14-20`) were failing
install with a rotating set of cryptic error codes:

| Error | Meaning |
|---|---|
| `0x80070001` | `ERROR_INVALID_FUNCTION` — generic OS-level failure, no detail |
| `0x87D1041C` | App reported "installed" but detection rule never found it |
| `0x87D30067` | "Error unzipping downloaded content" — corrupted/inconsistent package |

Driver files and install script logic were correct. The failure was architectural, not a typo.

## Root Cause

Comparing the broken apps against a printer app that was already working reliably across
90+ devices ("Printer 45 - Accounting") surfaced four compounding issues:

1. Wrong installer type. Broken apps used a "PowerShell script" installer type, which Intune invokes with zero arguments — any Mandatory script parameters silently never get passed. The working app used "Command line" installer type with explicit arguments.
2. Copy-paste detection rule bug. Printer - 14-20's registry detection path was still pointing at ...Printers\14-17, copied from the previous app and never updated.
3. Assignment intent mistake. One app was assigned "Available for enrolled devices" instead of "Required" — Available means a user must manually install via Company Portal; Required auto-pushes. Looked "stuck" but was actually just never triggered.
4. In-place package editing. Editing an existing Win32 app's .intunewin file without deleting and recreating the app leaves Intune's backend content reference inconsistent, producing the unzip error even when the rebuilt package itself is valid.

Lesson: when something "should work" but doesn't, stop debugging in isolation — find a config that already works and diff the two side by side. That comparison found in minutes what two days of isolated troubleshooting hadn't.

## Fix & Architecture

Rebuilt around one shared, parameterized package instead of one package per printer:

- Install-Printer.ps1 / Uninstall-Printer.ps1 — idempotent (check-before-act), parameterized by port name, printer IP, printer name, driver name, and an optional bundled INF for driver staging. One shared .intunewin package reused across every printer; only the Win32 app's install/uninstall command line differs per printer.
- Detection: registry "key exists" check at HKLM\Software\Microsoft\Windows NT\CurrentVersion\Print\Printers\<PrinterName> — proved far more reliable under SYSTEM context than a custom Get-Printer detection script.
- Installer type: Command line (not PowerShell script), so parameters actually pass.
- Assignment: Required, to a per-printer Entra ID security group.

## Graph API Automation

Manually repeating the Win32 app creation wizard for 10+ remaining printers doesn't scale. Built Upload-SharedPrinterApps.ps1 (IntuneWin32App PowerShell module) to read printers.csv and, per row, create the app, wire its detection rule, and assign it to the matching Entra group — one script run instead of ~15 manual clicks per printer.

Entra ID / auth setup required for the automation:

- App registration with a native/public client redirect URI of http://localhost (no port) — the module uses a dynamic-port loopback flow; the default https://login.microsoftonline.com/common/oauth2/nativeclient redirect URI is not sufficient and throws AADSTS50011.
- Use the tenant's actual Tenant ID GUID, not a vanity domain — a mismatched or aliased vanity domain can route sign-in to a cached/wrong tenant account (AADSTS50020). Confirm the real tenant ID via Graph Explorer: GET https://graph.microsoft.com/v1.0/organization.
- Add-IntuneWin32App's internal metadata reader resolves relative -FilePath values against the wrong working directory in some environments, throwing "Could not find a part of the path." Fix: always resolve to an absolute path with Resolve-Path before calling the cmdlet.
- Added a null-check guard after Add-IntuneWin32App so a failed app creation fails cleanly with a clear message instead of cascading into a confusing Cannot validate argument on parameter 'ID' error on the following assignment step.

Entra ID group structure: one security group per printer (Printer <name>), created via Create-PrinterGroups.ps1 (idempotent — skips groups that already exist), members added via Add-PrinterGroupDevices.ps1 from a verified device-to-printer-to-user mapping CSV, and audited via Get-PrinterGroupMembers.ps1.

## macOS Deployment

Windows tooling doesn't carry over — different OS, different shell, different print subsystem (Print Spooler vs. CUPS). macOS printer queues are managed via lpadmin (CUPS), deployed as an Intune macOS Platform Script (shell script run as root), not a packaged app — no compilation/packaging step needed for something this simple.

Deployed against a VersaLink C500 test unit ("GBI Printer"). Root-caused a "printer not responding" failure to wireless client isolation / VLAN segmentation — the test Mac and the printer sat on different VLANs (126 vs. 214 inferred from IP octet convention), and cross-VLAN traffic on ports 631/9100/515 wasn't being routed/permitted. Confirmed via direct TCP port testing (Test-NetConnection, later a lower-latency raw TcpClient socket check) rather than assuming a driver/config problem.

Driver package (Xerox Universal macOS Print Drivers) is a single universal installer covering PPDs for most current Xerox model lines (AltaLink, VersaLink, WorkCentre, PrimeLink) rather than one binary per model — confirmed the target model's PPD was already present before building anything, avoiding a repeat of an earlier wrong-driver mistake.

## Inventory Reconciliation

Cross-referenced a photographed/OCR'd physical asset inventory spreadsheet against the live, deployed configuration. Found and resolved:

- Printer identity/IP correction: a unit mistakenly labeled 14-176 (192.168.114.176) was actually 14-30 at 192.168.114.117 — required renaming both the physical device and its Entra ID group.
- Several IP conflicts between the old inventory sheet and already-deployed, working configs — resolved in favor of the verified, working deployment rather than the stale sheet.
- One printer (14-04) had moved to a new DHCP-assigned IP with no record of the change, causing a silent outage until traced via port testing and a DHCP reservation was requested to prevent recurrence.
- Ten additional printers identified in the physical inventory with no corresponding Entra ID group; created via the existing idempotent group-creation script without touching anything already built.

## Scripts

| Script | Purpose |
|---|---|
| Install-Printer.ps1 | Shared, idempotent Windows printer install (port + driver + queue) |
| Uninstall-Printer.ps1 | Shared Windows printer removal |
| Upload-SharedPrinterApps.ps1 | Graph API automation: creates Win32 apps + detection rules + assignments from CSV |
| Create-PrinterGroups.ps1 | Idempotent bulk Entra ID security group creation, one per printer |
| Add-PrinterGroupDevices.ps1 | Adds verified devices to their printer's Entra ID group |
| Get-PrinterGroupMembers.ps1 | Audits current membership across all printer groups |
| GBI-Printer-Mac.sh | Shared, idempotent macOS printer install via lpadmin, deployed as an Intune Platform Script |

## Result

Two previously-broken printers fixed and confirmed installed on real end-user devices. Ten new printers automated end-to-end via Graph API instead of the manual portal wizard. One cross-platform (macOS) deployment path stood up from scratch, including root-causing a network segmentation issue rather than misattributing it to driver/script failure.
