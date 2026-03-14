# Notify

A macOS app that automatically tracks your deliveries and returns by reading shipping emails from Gmail. Packages are grouped into Today, Upcoming, Delivered, and Returns — with a menu bar widget for at-a-glance delivery status.

## Requirements

- macOS 15+
- Xcode 16+
- An Apple Developer account (free tier works)
- A Google account + Google Cloud project

## Setup

### 1. Clone and open the project

```bash
git clone <repo-url>
cd notify
open notify.xcodeproj
```

### 2. Configure your Google OAuth credentials

The app authenticates with Gmail using Google Sign-In. You need your own OAuth Client ID.

**Create a Google Cloud project and OAuth credentials:**

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project (or use an existing one)
3. Navigate to **APIs & Services → Library** and enable the **Gmail API**
4. Navigate to **APIs & Services → Credentials**
5. Click **Create Credentials → OAuth Client ID**
6. Choose **macOS** as the application type
7. Copy the generated Client ID — it looks like: `XXXXXXXXXX-XXXXXXXX.apps.googleusercontent.com`

**Add your credentials to the project:**

```bash
cp Secrets.xcconfig.template Secrets.xcconfig
```

Open `Secrets.xcconfig` and fill in your values:

```
GOOGLE_CLIENT_ID = YOUR_CLIENT_ID.apps.googleusercontent.com
GOOGLE_URL_SCHEME = com.googleusercontent.apps.YOUR_CLIENT_ID
```

Where `YOUR_CLIENT_ID` is the part of your Client ID before `.apps.googleusercontent.com`.

> `Secrets.xcconfig` is gitignored and will never be committed. Don't skip this step — the app won't build correctly without it.

### 3. Configure your Apple Developer team and App Group

The app and its widget share data via an App Group. You need to set this up under your own Apple Developer account.

**Update the bundle identifiers and team:**

In Xcode, select the `notify` project in the Project Navigator, then for each target (`notify` and `notifyWidgetExtension`):

1. Under **Signing & Capabilities**, set your **Team**
2. Change the **Bundle Identifier** to something unique to you (e.g. `com.yourname.notify`)

**Update the App Group identifier:**

The App Group is how the main app shares delivery data with the widget. You need to replace the existing identifier (`group.org.roberthughesdev.notify`) with your own in four places:

- `notify/notify.entitlements` (line 9)
- `notifyWidget/notifyWidget.entitlements` (line 9)
- `notifyWidgetExtension.entitlements` (line 7)
- `notify/Services/DeliveryStore.swift` (line 14)
- `notifyWidget/NotifyWidget.swift` (line 56)

In Xcode, under **Signing & Capabilities** for each target, remove the old App Group and add a new one matching your chosen identifier.

### 4. Build and run

Select the `notify` scheme and hit **Run** (⌘R). Sign in with your Google account when prompted.

## Run at login (auto-start + auto-restart)

You can configure macOS to launch Notify automatically at login and restart it if it ever crashes, using a `launchd` LaunchAgent.

### 1. Build a release archive

In Xcode, go to **Product → Archive**, then **Distribute App → Copy App** to export `notify.app` somewhere permanent, e.g. `/Applications/notify.app`. The LaunchAgent will point to this path — don't move the app after setting it up or the agent will fail to launch.

### 2. Find the executable path

The LaunchAgent needs the path to the binary inside the app bundle, not the `.app` itself:

```
/Applications/notify.app/Contents/MacOS/notify
```

### 3. Create the LaunchAgent plist

Create the file `~/Library/LaunchAgents/org.roberthughesdev.notify.plist`:

```bash
touch ~/Library/LaunchAgents/org.roberthughesdev.notify.plist
```

Open it in any text editor and paste:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>org.roberthughesdev.notify</string>

    <key>ProgramArguments</key>
    <array>
        <string>/Applications/notify.app/Contents/MacOS/notify</string>
    </array>

    <key>KeepAlive</key>
    <true/>

    <key>RunAtLoad</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/tmp/notify.log</string>

    <key>StandardErrorPath</key>
    <string>/tmp/notify.error.log</string>
</dict>
</plist>
```

### 4. Load the agent

```bash
launchctl load ~/Library/LaunchAgents/org.roberthughesdev.notify.plist
```

The app will start immediately and will relaunch automatically on crash or after a reboot.

### Useful commands

```bash
# Start manually
launchctl start org.roberthughesdev.notify

# Stop (will restart automatically due to KeepAlive — see note below)
launchctl stop org.roberthughesdev.notify

# Permanently disable and unload
launchctl unload ~/Library/LaunchAgents/org.roberthughesdev.notify.plist

# View logs
tail -f /tmp/notify.log
tail -f /tmp/notify.error.log
```

> **Note on KeepAlive:** Because `KeepAlive` is `true`, using `launchctl stop` will stop the process momentarily but `launchd` will restart it. To fully stop the app, use `launchctl unload` instead.

## How it works

1. On launch, the app signs into Gmail via Google OAuth (read-only scope)
2. It searches your inbox for shipping and return emails from the past N weeks (configurable in-app, 1–12 weeks)
3. Emails are parsed locally on your device to extract carrier, tracking number, expected delivery date, and status
4. Results are grouped into sections and synced to the widget via an App Group
5. The widget refreshes every 10 minutes and shows today's expected deliveries

Supported carriers: Amazon, UPS, FedEx, USPS, DHL.

## Privacy

All processing happens on your device. Your emails are never sent to any server — the app only uses the Gmail API's read-only scope to fetch raw message data, which is parsed locally.
