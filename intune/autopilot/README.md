# Windows Autopilot — Zero-Touch Provisioning Lab

## Objective
Stand up a full Autopilot deployment end-to-end: hardware hash capture, device group registration, deployment profile, Enrollment Status Page (ESP), and app/policy assignment — closing the hands-on gap behind the "Proven experience implementing and managing Windows Autopilot" requirement.

## Environment
- Test VM (Hyper-V/Azure VM) or spare physical device
- Intune tenant (dev/lab)
- Entra ID (Azure AD) joined

## Steps

### 1. Capture hardware hash
- [ ] Run `Get-WindowsAutopilotInfo` PowerShell script on target device
- [ ] Export hash to CSV

### 2. Register device
- [ ] Import CSV into Intune > Devices > Enrollment > Windows Autopilot devices
- [ ] Assign to Autopilot device group (dynamic or assigned)

### 3. Deployment profile
- [ ] Create deployment profile: Azure AD join, user-driven / self-deploying
- [ ] Configure OOBE settings (skip privacy/EULA, hide account type, allow/block pre-provisioned deployment)
- [ ] Assign profile to device group

### 4. Enrollment Status Page (ESP)
- [ ] Configure ESP: block device use until apps/profiles install
- [ ] Set timeout and error handling behavior
- [ ] Assign to same device group

### 5. App / policy assignment
- [ ] Assign at least one Win32 app as required, install during ESP
- [ ] Assign compliance policy and at least one configuration profile
- [ ] Confirm Conditional Access applies post-enrollment

### 6. Reset and test
- [ ] Reset test device (`Settings > Reset this PC` or wipe via Intune)
- [ ] Time the full OOBE-to-desktop enrollment
- [ ] Screenshot each ESP phase (Device setup, Account setup, App install)

## Results
_Fill in after running: total enrollment time, any failures, ESP phase that took longest._

## Lessons Learned
_Fill in: what broke, what the real troubleshooting step was, what you'd do differently in production._

## Screenshots
_Add exported screenshots or config JSON here._
