# Raspberry Pi Photo & Weather Slideshow

Turn your Raspberry Pi into a beautiful photo frame that automatically shows pictures from Google Drive and local weather data.

```
+---------------------------+
|                           |
|     Your Photos from      |
|      Google Drive         |
|            +              |
|     Live Weather Data     |
|                           |
|   Runs 24/7 on your Pi!   |
+---------------------------+
```

---

## One-Line Install

```bash
git clone https://github.com/PSDTools/science-slideshow.git ~/slideshow && cd ~/slideshow && pip3 install -r requirements.txt --break-system-packages
```

Then edit `config.json` with your settings and add your `credentials.json` file. [Full setup instructions below](#step-by-step-setup).

---

## What You'll Need

- Raspberry Pi (3, 4, or 5)
- Monitor/TV (works great in portrait mode!)
- Google account
- 15-20 minutes for setup

---

## Quick Start (for the impatient)

```bash
# 1. Clone/copy files to your Pi
mkdir ~/slideshow && cd ~/slideshow

# 2. Install dependencies
pip3 install -r requirements.txt --break-system-packages

# 3. Edit config.json with your settings (see below)

# 4. Add your Google credentials.json file

# 5. Run it!
python3 server.py
```

Then open http://localhost:5000 in a browser.

---

## Step-by-Step Setup

### Step 1: Configure Your Settings

Everything is in one file: **`config.json`**

```json
{
    "google_drive": {
        "folder_id": "paste-your-folder-id-here"
    },
    "weather": {
        "api_key": "paste-your-api-key-here",
        "station_id": "paste-your-station-id-here"
    },
    "slideshow": {
        "image_duration_seconds": 10,
        "weather_duration_seconds": 15,
        "weather_refresh_minutes": 15,
        "images_refresh_minutes": 60
    },
    "server": {
        "host": "0.0.0.0",
        "port": 5000
    }
}
```

#### How to get your Google Drive Folder ID:

1. Open your Google Drive folder in a browser
2. Look at the URL: `https://drive.google.com/drive/folders/ABC123XYZ`
3. Copy the part after `/folders/` — that's your folder ID!

#### How to get Weather Underground credentials (optional):

1. Go to https://www.wunderground.com/member/api-keys
2. Sign up / log in
3. Copy your API key
4. Find a weather station near you at https://www.wunderground.com/wundermap
5. Click on a station and copy its ID (like `KNYNEWY123`)

> **No weather?** Just leave the weather fields empty — the slideshow will show only your photos.

---

### Step 2: Get Google Drive Access

You need to create credentials so your Pi can read your Drive folder.

#### A. Create a Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Click **"Select a project"** → **"New Project"**
3. Name it `Slideshow` → Click **"Create"**

#### B. Enable the Google Drive API

1. In the search bar, type **"Google Drive API"**
2. Click on it → Click **"Enable"**

#### C. Create OAuth Credentials

1. Go to **APIs & Services** → **Credentials**
2. Click **"Create Credentials"** → **"OAuth client ID"**
3. If asked to configure consent screen:
   - Choose **"External"**
   - App name: `Slideshow`
   - Add your email
   - Click through all the "Save and Continue" buttons
4. Back at OAuth client ID:
   - Application type: **"Desktop app"**
   - Name: `Slideshow`
   - Click **"Create"**
5. Click **"Download JSON"**
6. Rename the downloaded file to **`credentials.json`**
7. Put it in your slideshow folder

---

### Step 3: Set Up Your Raspberry Pi

#### Install the OS

1. Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
2. Choose **Raspberry Pi OS (64-bit) with Desktop**
3. Flash to your SD card

#### Install Dependencies

```bash
# Update your Pi
sudo apt update && sudo apt upgrade -y

# Install required software
sudo apt install -y python3-pip chromium-browser unclutter

# Install Python packages
cd ~/slideshow
pip3 install -r requirements.txt --break-system-packages
```

#### (Optional) Rotate Display to Portrait

```bash
sudo nano /boot/firmware/config.txt
```

Add this line at the end:
```
display_rotate=1
```

Save (Ctrl+X, Y, Enter) and reboot.

---

### Step 4: First Run & Authentication

The first time you run the server, it will ask you to log in to Google:

```bash
cd ~/slideshow
python3 server.py
```

A browser window will open:

1. Choose your Google account
2. Click **"Continue"** (ignore the "unverified app" warning — it's YOUR app!)
3. Click **"Allow"** to grant access

You'll see:
```
Found X images
Server running at: http://localhost:5000
```

Your login is now saved! You won't need to do this again.

---

### Step 5: Test It!

With the server running, open a browser:

```bash
chromium-browser http://localhost:5000
```

You should see your slideshow!

---

### Step 6: Auto-Start on Boot

Make it start automatically when your Pi boots:

```bash
# Make the startup script executable
chmod +x ~/slideshow/start_slideshow.sh

# Create autostart config
mkdir -p ~/.config/lxsession/LXDE-pi
nano ~/.config/lxsession/LXDE-pi/autostart
```

Add this line:
```
@/home/pi/slideshow/start_slideshow.sh
```

Save and reboot:
```bash
sudo reboot
```

Your slideshow will now start automatically!

---

## Adding & Removing Photos

Just add or remove images from your Google Drive folder!

- Changes appear automatically within 1 hour
- Want it faster? Visit: `http://localhost:5000/api/refresh`

**Supported formats:** JPG, PNG, GIF, WebP — basically any image!

---

## Useful URLs

While running, you can check on your slideshow:

| URL | What it does |
|-----|--------------|
| `http://localhost:5000` | The slideshow itself |
| `http://localhost:5000/health` | Server status |
| `http://localhost:5000/api/images` | List of all images |
| `http://localhost:5000/api/refresh` | Force refresh images now |

---

## Troubleshooting

### "No images showing"

1. Check the log: `cat ~/slideshow/server.log`
2. Make sure `credentials.json` is in the folder
3. Verify your folder ID in `config.json`
4. Try running authentication again (Step 4)

### "Authentication failed"

```bash
# Delete the saved token and try again
rm ~/slideshow/token.pickle
python3 server.py
```

### "Server won't start"

```bash
# Check if something else is using port 5000
sudo lsof -i :5000

# Kill it if needed
sudo kill -9 <PID>
```

### "Weather not showing"

- Check that your API key and station ID are in `config.json`
- Weather fields are optional — leave them empty for photos only

### "Slideshow doesn't auto-start"

1. Check the autostart file exists: `cat ~/.config/lxsession/LXDE-pi/autostart`
2. Make sure the script is executable: `chmod +x ~/slideshow/start_slideshow.sh`
3. Check the path matches your username (it's `/home/pi/` by default)

---

## File Overview

```
~/slideshow/
├── config.json          # YOUR SETTINGS GO HERE
├── credentials.json     # Google credentials (you provide)
├── server.py            # The backend server
├── slideshow.html       # The frontend display
├── start_slideshow.sh   # Auto-start script
├── requirements.txt     # Python dependencies
├── token.pickle         # Saved Google login (auto-created)
├── image_cache.pkl      # Cached image list (auto-created)
└── server.log           # Server logs (auto-created)
```

---

## Tips & Tricks

**Restarting the slideshow:**
```bash
sudo reboot
```

**Viewing live logs:**
```bash
tail -f ~/slideshow/server.log
```

**Changing slide timing:**
Edit `config.json` and restart the server.

**Using a different port:**
Change `"port": 5000` in `config.json`.

---

## How It Works

1. **Flask server** connects to Google Drive and fetches your image list
2. **Images are cached** so it works even if internet drops briefly
3. **HTML slideshow** displays photos + weather in fullscreen
4. **Chromium kiosk mode** hides all browser UI for a clean look
5. **Everything refreshes automatically** — just set it and forget it!

---

## Need Help?

- Check the [troubleshooting section](#troubleshooting) above
- View your logs: `cat ~/slideshow/server.log`
- Open an issue on GitHub

Enjoy your slideshow!
