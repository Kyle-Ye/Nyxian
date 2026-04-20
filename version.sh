#!/bin/bash
# Increment build number across all targets and append country + username

cd "$SRCROOT"

# Current date
current_date=$(date "+%Y%m%d")

# Read previous build number
previous_build_number=$(awk -F "=" '/BUILD_NUMBER/ {print $2}' Config.xcconfig | tr -d ' ')

# Extract date, counter, country, and user from previous build number
previous_date="${previous_build_number%%.*}"
rest="${previous_build_number#*.}"
counter="${rest%%.*}"
suffix="${rest#*.}"
previous_country="${suffix%%.*}"
previous_user="${suffix#*.}"

# Increment or reset counter
if [[ "$current_date" == "$previous_date" ]]; then
  new_counter=$((counter + 1))
else
  new_counter=1
fi

# Preserve the existing suffix unless explicitly overridden for local builds.
country_code="${NYXIAN_BUILD_COUNTRY:-${previous_country:-XX}}"
build_user="${NYXIAN_BUILD_USER:-${previous_user:-$(whoami)}}"

# New build number with country + user
new_build_number="${current_date}.${new_counter}.${country_code}.${build_user}"

# Replace in config
sed -i -e "/BUILD_NUMBER =/ s/= .*/= $new_build_number/" Config.xcconfig

# Remove sed backup
rm -f Config.xcconfig-e
