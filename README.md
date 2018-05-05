## Automatic monitor switch when an external source is plugged


*** This guide applies for Linux using the LXDE windows manager ***


### A brief overview
Automatic monitor switch is a very useful utility when you often move your laptop. At home you have one or more external monitors, at the office you have another one or you code while commuting from A to B.

However, on my LXDE installation, apparently there's not a tool that automatically provides such a feature, so switching can be accomplished the usual Linux way: a bit of scripting and a lot of googling.
Namely you have to intercept the [UDEV](https://en.wikipedia.org/wiki/Udev) event, if the graphic driver in the kernel supports your chipset.

I wanted a solution that __does not sit on the background polling on kernel events__. I wanted something __triggered by__ kernel events, that's what UDEV is there for.

### Requirements
```
# for xrandr
$ sudo apt-get install x11-xserver-utils
```

### Find your device
Check whether the kernel is aware of the plug/unplug events. Tail the kernel events with udevadm while you plug/unplug the external monitor:
```
$ udevadm monitor --property
```
if you see something like the following, you're good to go:
```
KERNEL[28.029974] change   /devices/pci0000:00/0000:00:02.0/drm/card0 (drm)
ACTION=change
DEVNAME=/dev/dri/card0
DEVPATH=/devices/pci0000:00/0000:00:02.0/drm/card0
DEVTYPE=drm_mino
HOTPLUG=1
MAJOR=226
MINOR=0
SEQNUM=2959
SUBSYSTEM=drm

UDEV  [28.038149] change   /devices/pci0000:00/0000:00:02.0/drm/card0 (drm)
ACTION=change
DEVNAME=/dev/dri/card0
DEVPATH=/devices/pci0000:00/0000:00:02.0/drm/card0
DEVTYPE=drm_minor
HOTPLUG=1
ID_FOR_SEAT=drm-pci-0000_00_02_0
ID_PATH=pci-0000:00:02.0
ID_PATH_TAG=pci-0000_00_02_0
MAJOR=226
MINOR=0
SEQNUM=2959
SUBSYSTEM=drm
TAGS=:seat:uaccess:master-of-seat:
USEC_INITIALIZED=4743165
```
The useful info here are:
- `action=change`: type of action triggered
- `devname=/dev/dri/card0`: name of the graphic card device
- `devpath=/devices/pci0000:00/...`: path of the graphic card device

### Write the UDEV rule
Write down the `DEVPATH` and `DEVNAME` from the previous output, that's where UDEV sees your graphic cards. To double check the path/name of your device you can query it with:
```
$ udevadm info -n /dev/dri/card0
$ udevadm info -q path -n /dev/dri/card0
```
Create a new UDEV rule `/etc/udev/95-monitor-switch.rules`, replace _user_ with your Linux user:
```
ACTION=="change", KERNEL=="card0", SUBSYSTEM=="drm", ENV{DISPLAY}=":0", ENV{XAUTHORITY}="/home/user/.Xauthority", RUN+="/path/to/autorandr.sh"
```
This rule can probably be refined and YMMV, but _it works for me_ (:copyright: 2016).

Test the syntax of your rule executing a dry-run on your graphic card path:
```
udevadm test -a change /devices/pci0000:00/0000:00:02.0/drm/card0 | less
```
You should see your new rule appearing and no errors.

### Compose the monitor switch commands
You need to create two `xrandr` commands: one for the single monitor and one with the extended desktop on the external monitor. In order to do so, use `arandr` and note down the configuration commands created.

Purely as an example, here's mines; I have a Dell XPS13 laptop with a FullHD screen (the `eDPI1` primary device) and a Dell U2414 external monitor (the `DPI` secondary device):
* Switch to single monitor: `/usr/bin/xrandr --output DP1 --off --output eDP1 --mode 1920x1080 --pos 0x0 --rotate normal`
* Switch to double monitor: `/usr/bin/xrandr --output DP1 --mode 1920x1080 --pos 0x0 --output eDP1 --primary --mode 1920x1080 --pos 0x1080` (notice how `DPI1` becomes the primary monitor and `eDPI1` is stacked under `DPI1`).

Check how many connected monitors you have with `xrandr --listmonitors` after running alternatively these two commands. You will notice the monitor count flips from `1` to `2` and viceversa.

Also you can check their status by peeking at the `status` attribute of the kernel device. In my case these two devices translates to the following paths:
```
$ cat /sys/class/drm/card0-DP-1/status
$ cat /sys/class/drm/card0-eDP-1/status
```
Note down these paths, we'll use them later.

### Write the auto-switching script
Put the `xrandr` commands in the *if-then* in the `/path/to/autorandr.sh` file you chose in the UDEV rule. Set the `EXTERNAL_MONITOR_STATUS` variable to read whether the external monitor is connected and execute the proper `xrandr` command.
```
#!/bin/sh

set -e

# Is the external monitor connected?
EXTERNAL_MONITOR_STATUS=$( /sys/class/drm/card0-DP-1/status )
if [ $EXTERNAL_MONITOR_STATUS == "connected" ]; then
    TYPE="double"
    /usr/bin/xrandr ... (command for single+external monitors)
else
    TYPE="single"
    /usr/bin/xrandr ... (command for single monitor)
fi

# log to syslog (not necessary)
logger -t autorandr "Switched to $TYPE monitor mode"

# show a popup
/usr/bin/notify-send --urgency=low -t 500 "Switched to $TYPE monitor configuration"

exit 0
```

### Test
Test the bash script with the external monitor plugged or unplugged. You should see the monitor switch happening.

### Bugs
Of course things might not be so *simple*. For example I've encountered an issue running the `xrandr` command to attach the external monitor: the monitor did not show up with the available resolutions, therefore the `xrandr` command failed.

With some more google-fu, turns out the solution is to set `Option "HotPlug" "false"` in your Xorg config file, wherever it is located (usually in `/usr/share/X11/xorg.conf.d/*`). If you don't have a config file with a `Device` directive, you need to manually create it.

For example a minimal `/usr/share/X11/xorg.conf.d/20-intel.conf` did the trick for me (I have an Intel i915 chipset):
```
Section "Device"
    Identifier "Intel Graphics"
    Driver "intel"
    Option "HotPlug" "false"
    EndSection
```
Restart X (or reboot) for this change to take effect.
However after this change `Xorg` error reports started popping out upon startup, so I must have overriden some default settings of Xorg; well... what the hell, I'll fix that another time.

I've also experienced that `xrandr` is sometimes slow to detect the new monitor resolutions (although the command shows them all correctly). As a workaround you can have `xrandr` poll the device configuration and exit when the switch is done.

I've put a sample script `autorandr.sh` as a customizable template. Device ids are mines, YMMV.

### Conclusions

**Linux on desktop sucks**. Why did I have to spend an evening copying and pasting stuff from the Interwebz? Why did I have to figure out how things worked until I managed to hack together a BASH script triggered by a kernel event? OSX users have this utility *out of the box*.

You can of course customize this script based on your configurations, this is just a succint guide on the steps to follow.

If after reading this guide you think that I just wasted my time because there's a tool that does this automagically, __please let me know__, I'll be super-happy to try it! :-)

### Sources

- [The thread on HN that urged me to itch this scratch](https://news.ycombinator.com/item?id=11570940)
- [The always GREAT Arch wiki](https://wiki.archlinux.org/index.php/Udev)
- [This thread on StackExchange](http://unix.stackexchange.com/questions/4489/a-tool-for-automatically-applying-randr-configuration-when-external-display-is-pl/13917)
- [This outdated but still useful guide for Ubuntu](https://help.ubuntu.com/community/DynamicMultiMonitor) (the UDEV rule they describe didn't work for me, but it was a start on what I needed)
- [man udevadm](http://linux.die.net/man/8/udevadm)
