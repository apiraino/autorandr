#!/bin/sh

set -e

logger -t autorandr "ACTION: $ACTION" # "change"
logger -t autorandr "SUBSYSTEM: $SUBSYSTEM" # "drm"

# BUG: wait a bit before checking the config, the UDEV rule might run before the actual change -_-
sleep 1

# BUG: device on /sys/class/drm does not update without forcing an update with xrandr
logger -t autorandr "Reading monitor configuration..."
xrandr > /dev/null

# change this to your external monitor device
EXTERNAL_MONITOR=HDMI2
EXTERNAL_MONITOR_STATUS=$( cat /sys/class/drm/card0-HDMI-A-2/status )

echo "External monitor is: $EXTERNAL_MONITOR_STATUS"

# Is the external monitor connected?
if [ "$EXTERNAL_MONITOR_STATUS" = "connected" ]; then
    TYPE="double"
    /usr/bin/xrandr --output $EXTERNAL_MONITOR --mode 1920x1080 --pos 0x0 --rotate normal --output eDP1 --primary --mode 1920x1080 --pos 0x1080 --rotate normal
else
    TYPE="single"
    /usr/bin/xrandr --output $EXTERNAL_MONITOR --off --output eDP1 --mode 1920x1080 --pos 0x0 --rotate normal
fi

logger -t autorandr "Switched to $TYPE monitor mode"

exit 0
