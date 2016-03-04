#! /bin/bash -e

# ---
# RightScript Name: RL10 Linux Upgrade IV-4282
# Description: Check whether a RightLink upgrade is available and perform the upgrade.
# Inputs:
#   UPGRADES_FILE_LOCATION:
#     Input Type: single
#     Category: RightScale
#     Description: External location of 'upgrades' file
#     Default: text:https://rightlink.rightscale.com/rightlink/upgrades
#     Required: false
#     Advanced: true
#   UPGRADE_VERSION:
#     Input Type: single
#     Category: RightScale
#     Description: The new version of RightLink to upgrade to. If this input is specified it will override
#       the input UPGRADES_FILE_LOCATION that contains the location of the upgrade's file location.
#       A specific version can be used such as 10.3.1 or use 10 to get the latest version available.
#     Default: blank
#     Required: false
#     Advanced: true
# ...
#

# Will compare current version of rightlink 'running' with latest version provided from 'upgrades'
# file. If they differ, will update to latest version.  Note that latest version can be an older version
# if a downgrade is best as found in the $UPGRADES_FILE_LOCATION

UPGRADES_FILE_LOCATION=${UPGRADES_FILE_LOCATION:-"https://rightlink.rightscale.com/rightlink/upgrades"}

# Determine directory location of rightlink / rsc
[[ -e /usr/local/bin/rightlink ]] && bin_dir=/usr/local/bin || bin_dir=/opt/bin

# Determine if the version of rsc supports retry
[[ $(${bin_dir}/rsc --help | grep retry) ]] && retry_command="--retry=5 --timeout=10" || retry_command=""

upgrade_rightlink() {
  sleep 1
  # Use 'logger' here instead of 'echo' since stdout from this is not sent to
  # audit entries as RightLink is down for a short time during the upgrade process.

  res=$(${bin_dir}/rsc rl10 upgrade /rll/upgrade exec=${bin_dir}/rightlink-new 2>/dev/null || true)
  if [[ "$res" =~ successful ]]; then
    # Delete the old version if it exists from the last upgrade.
    sudo rm -rf ${bin_dir}/rightlink-old
    # Keep the old version in case of issues, ie we need to manually revert back.
    sudo mv ${bin_dir}/rightlink ${bin_dir}/rightlink-old
    sudo cp ${bin_dir}/rightlink-new ${bin_dir}/rightlink
    logger -t rightlink "rightlink updated"
  else
    logger -t rightlink "Error: ${res}"
    exit 1
  fi

  # Check updated version in production by connecting to local proxy
  # The update takes a few seconds so retries are done.
  for retry_counter in {1..5}; do
    new_installed_version=$(${bin_dir}/rsc ${retry_command} rl10 show /rll/proc/version 2>/dev/null || true)
    if [[ "$new_installed_version" == "$desired" ]]; then
      logger -t rightlink "New version active - ${new_installed_version}"
      break
    else
      logger -t rightlink "Waiting for new version to become active."
      sleep 5
    fi
  done
  if [[ "$new_installed_version" != "$desired" ]]; then
    logger -t rightlink "New version does not appear to be desired version: ${new_installed_version}"
    exit 1
  fi

  # Report to audit entry that RightLink was upgraded.
  for retry_counter in {1..5}; do
    instance_href=$(${bin_dir}/rsc ${retry_command} --rl10 --x1 ':has(.rel:val("self")).href' cm15 index_instance_session /api/sessions/instance || true)
    if [[ -n "$instance_href" ]]; then
      logger -t rightlink "Instance href found: ${instance_href}"
      break
    else
      logger -t rightlink "Instance href not found, retrying"
      sleep 5
    fi
  done

  if [[ -n "$instance_href" ]]; then
    audit_entry_href=$(${bin_dir}/rsc ${retry_command} --rl10 --xh 'location' cm15 create /api/audit_entries "audit_entry[auditee_href]=${instance_href}" \
                     "audit_entry[detail]=RightLink updated to '${new_installed_version}'" "audit_entry[summary]=RightLink updated" 2>/dev/null)
    if [[ -n "$audit_entry_href" ]]; then
      logger -t rightlink "audit entry created at ${audit_entry_href}"
    else
      logger -t rightlink "failed to create audit entry"
    fi
  else
    logger -t rightlink "unable to obtain instance href for audit entries"
  fi

  # Update RSC after RightLink has successfully updated.
  if [[ -x ${bin_dir}/rsc ]]; then
    sudo mv ${bin_dir}/rsc ${bin_dir}/rsc-old
  fi
  sudo mv /tmp/rightlink/rsc ${bin_dir}/rsc
  # If new RSC is correctly installed then remove the old version
  if [[ -x ${bin_dir}/rsc ]]; then
    sudo rm -rf ${bin_dir}/rsc-old
  else
    logger -t rightlink "failed to update to new version of RSC"
    sudo mv ${bin_dir}/rsc-old ${bin_dir}/rsc
  fi
  exit 0
}

# Determine current version of rightlink
current_version=$(${bin_dir}/rsc ${retry_command} rl10 show /rll/proc/version)

if [[ -z "$current_version" ]]; then
  echo "Can't determine current version of RightLink"
  exit 1
fi

# If $UPGRADE_VERSION is specified then use that for desired version, otherwise check external
# upgrades file location for possible upgrade version
if [[ -z "$UPGRADE_VERSION" ]]; then
  # Fetch information about what we should become. The "upgrades" file consists of lines formatted
  # as "current_version:upgradeable_new_version". If the "upgrades" file does not exist,
  # or if the current version is not in the file, no upgrade is done.
  re="^\s*${current_version}\s*:\s*(\S+)\s*$"
  match=`curl --silent --show-error --retry 3 ${UPGRADES_FILE_LOCATION} | egrep ${re} || true`
  if [[ "$match" =~ $re ]]; then
    desired="${BASH_REMATCH[1]}"
  else
    echo "Cannot determine latest version from upgrade file"
    echo "Tried to match /^${current_version}:/ in ${UPGRADES_FILE_LOCATION}"
    exit 0
  fi
else
  desired="$UPGRADE_VERSION"
fi

if [[ "$desired" == "$current_version" ]]; then
  echo "RightLink is already up-to-date (current=${current_version})"
  exit 0
fi

echo "RightLink needs update:"
echo "  from current=${current_version}"
echo "  to   desired=${desired}"

echo "downloading RightLink version '${desired}'"

# Download new version
cd /tmp
sudo rm -rf rightlink rightlink.tgz
curl --silent --show-error --retry 3 --output rightlink.tgz https://rightlink.rightscale.com/rll/${desired}/rightlink.tgz
tar zxf rightlink.tgz || (cat rightlink.tgz; exit 1)

# Check downloaded version
sudo mv rightlink/rightlink ${bin_dir}/rightlink-new
echo "checking new version"
new=`${bin_dir}/rightlink-new --version | awk '{print $2}'`
if [[ "$new" == "$desired" ]]; then
  echo "new version looks right: ${new}"

  # We pre-run the self-check now so we can fail fast.
  . <(sudo sed '/^export/!s/^/export /' /var/lib/rightscale-identity)
  self_check_output=$(${bin_dir}/rightlink-new --selfcheck 2>&1)
  if [[ "$self_check_output" =~ "Self-check succeeded" ]]; then
    echo "new version passed connectivity check"
  else
    echo "initial self-check failed:"
    echo "$self_check_output"
    exit 1
  fi

  echo "restarting RightLink to pick up new version"
  # Fork a new task since this main process is started
  # by RightLink and we are restarting it.
  upgrade_rightlink &
else
  echo "Updated version does not appear to be desired version: ${new}"
  exit 1
fi
