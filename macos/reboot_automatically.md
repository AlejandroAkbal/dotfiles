# Mac Daily Restart at 3 AM

## How It Works

- 2:55 AM: `pmset` wakes Mac from sleep
- 3:00 AM: `launchd` restarts Mac
- Works while locked, sleeping, or logged out

## Setup (Run Once)

Wake Mac at 2:59 AM:

```bash
sudo pmset repeat wake MTWRFSU 02:59:00
```

Create restart daemon:

```bash
sudo tee /Library/LaunchDaemons/com.local.restart.plist > /dev/null << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.restart</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>-c</string>
        <string>sudo shutdown -r now</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>3</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
</dict>
</plist>
EOF
```

Load daemon:

```bash
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.restart.plist
```

## Verify

Check if loaded:

```bash
sudo launchctl list | grep com.local.restart
```

Should return:
```
-	0	com.local.restart
```

Check wake schedule:

```bash
pmset -g sched
```

Should show:
```
repeating wake: 02:55 every day
```

## Change Restart Time

Remove old daemon:

```bash
sudo launchctl bootout system /Library/LaunchDaemons/com.local.restart.plist
```

Edit Hour value (3 = 3 AM, 6 = 6 AM, 23 = 11 PM):

```bash
sudo tee /Library/LaunchDaemons/com.local.restart.plist > /dev/null << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.restart</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>-c</string>
        <string>sudo shutdown -r now</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>6</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
</dict>
</plist>
EOF
```

Reload:

```bash
sudo launchctl bootstrap system /Library/LaunchDaemons/com.local.restart.plist
```

Also update wake time (5 minutes before restart):

```bash
sudo pmset repeat cancel
sudo pmset repeat wake MTWRFSU 05:55:00
```

## Remove It

Unload daemon:

```bash
sudo launchctl bootout system /Library/LaunchDaemons/com.local.restart.plist
```

Remove plist:

```bash
sudo rm /Library/LaunchDaemons/com.local.restart.plist
```

Cancel wake schedule:

```bash
sudo pmset repeat cancel
```
