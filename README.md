autolocation
============

Yet another fancy shell script to automatically set OS X Network Location based on SSID or IP address.

# Installation
1. Create network locations named `Home` and `Work` (`Network Preferences -> Location -> Edit Locations...`)
1. Create `.ssh/config.Work` and `.ssh/config.Home` containing your different ssh configs for connecting from the different locations
1. Modify the plist file to point to the location of the `autolocation.sh` script in the `<Program>` section.
1. Copy the plist file to `~/Library/LaunchAgents/`
1. Modify the `autolocation.sh:set_location()` function to make the environment variable swapping work with your terminal configuration
1. Run `launchctl load <location of plist file>`


# What this does
Anytime the network configuration changes, the script will run and it will run some custom scripting based on the chosen network location.

# Updates
I removed the autoswitch functionality based on SSID because if the WiFi is unstable, it can get messy.