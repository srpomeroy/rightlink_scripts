# ---
# RightScript Name: RL10 Windows Setup Automatic Upgrade IV-4282
# Description: Creates a scheduled job that performs a daily check to see if
#   an upgrade to RightLink is available and upgrades if there is.
# Inputs:
#   ENABLE_AUTO_UPGRADE:
#     Input Type: single
#     Category: RightScale
#     Description: Enables or disables automatic upgrade of RightLink10.
#     Default: text:true
#     Required: false
#     Advanced: true
#     Possible Values:
#       - text:true
#       - text:false
# ...
#

# This script either creates or updates a scheduled job that will run once a day that checks to
# see if there is an upgrade for RightLink

$scheduledJob = SCHTASKS.exe /Query /TN 'rightlink_check_upgrade' 2> $null
if ($env:ENABLE_AUTO_UPGRADE -eq 'false') {
  if ($scheduledJob) {
    SCHTASKS.exe /Delete /TN 'rightlink_check_upgrade' /F
    Write-Output 'Automatic upgrade disabled'
  } else {
    Write-Output 'Automatic upgrade never enabled - no action done'
  }
} else {
  # Random hour 0-23
  $jobHour = Get-Random -Min 0 -Max 24
  # Random minute 0-59
  $jobMinute = Get-Random -Min 0 -Max 60
  # Create time format of ##:## needed for SCHTASKS
  $jobStartTime = '{0:d2}:{1:d2}' -f $jobHour, $jobMinute

  if ($scheduledJob) {
    Write-Output 'Recreating schedule job'
    SCHTASKS.exe /Change /RU 'SYSTEM' /TN 'rightlink_check_upgrade' /ST $jobStartTime
  } else {
    # Determine if running a rightscript or a recipe
    if ((Get-Location) -match 'scripts') {
      $rscCommand = "schedule_right_script /api/right_net/scheduler/schedule_right_script right_script=\\\`"RL10 Windows Upgrade  IV-4282\\\`""
    } else {
      $rscCommand = "schedule_recipe /api/right_net/scheduler/schedule_recipe recipe=rlw::upgrade"
    }
    SCHTASKS.exe /Create /RU 'SYSTEM' /ST $jobStartTime /SC DAILY `
    /TR "Powershell.exe & \\\`"C:\Program Files\RightScale\RightLink\rsc.exe\\\`" --rl10 cm15 $rscCommand" `
    /TN 'rightlink_check_upgrade'
  }

  # Check to make sure that the job was scheduled
  $newScheduledJob = SCHTASKS.exe /Query /TN 'rightlink_check_upgrade' 2> $null
  if ($newScheduledJob) {
    Write-Output 'Automatic upgrade enabled.'
  } else {
    Write-Output 'The scheduled job failed to be created!'
    Exit 1
  }
}
