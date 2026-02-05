# Raspberry Pi Photo & Weather Slideshow

Turn your Raspberry Pi into a beautiful photo frame that automatically shows pictures from a public Google Drive folder and local weather data.

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

Then edit `config.json` with your settings. [Full setup below](#step-by-step-setup).

---

## What You'll Need

- Raspberry Pi (3, 4, or 5)
- Monitor/TV
- A **public** Google Drive folder with images
- 5-10 minutes for setup

---

## Quick Start

1. **Get your Google Drive folder ID**
   - Open your folder in Google Drive
   - URL looks like: `https://drive.google.com/drive/folders/ABC123XYZ`
   - Copy the `ABC123XYZ` part

2. **Get a Google API key** (free, takes 2 minutes)
   - Go to [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
   - Create a project → Create credentials → API key
   - Copy the key

3. **Edit `config.json`**
   ```json
   {
       "google_drive": {
           "folder_id": "your-folder-id-here",
           "api_key": "your-api-key-here"
       }
   }
   ```

4. **Run it**
   ```bash
   python3 server.py
   ```

5. **Open** http://localhost:5000

That's it!

---

## Step-by-Step Setup

### Step 1: Make Your Google Drive Folder Public

1. Open Google Drive
2. Right-click your folder → **Share**
3. Change to **"Anyone with the link"**
4. Copy the folder ID from the URL

### Step 2: Get a Google API Key

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project (or use existing)
3. Go to **APIs & Services** → **Library**
4. Search for **"Google Drive API"** → Click **Enable**
5. Go to **APIs & Services** → **Credentials**
6. Click **Create Credentials** → **API key**
7. Copy your API key

> **Optional:** Click "Edit API key" to restrict it to only the Drive API for security.

### Step 3: Configure

Edit `config.json`:

```json
{
    "google_drive": {
        "folder_id": "paste-your-folder-id",
        "api_key": "paste-your-api-key"
    },
    "weather": {
        "api_key": "",
        "station_id": ""
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

### Step 4: Install on Raspberry Pi

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install dependencies
sudo apt install -y python3-pip chromium-browser unclutter

# Clone and install
git clone https://github.com/PSDTools/science-slideshow.git ~/slideshow
cd ~/slideshow
pip3 install -r requirements.txt --break-system-packages
```

### Step 5: Test It

```bash
python3 server.py
```

Open http://localhost:5000 — you should see your slideshow!

### Step 6: Auto-Start on Boot

```bash
chmod +x ~/slideshow/start_slideshow.sh
mkdir -p ~/.config/lxsession/LXDE-pi
echo "@/home/pi/slideshow/start_slideshow.sh" >> ~/.config/lxsession/LXDE-pi/autostart
sudo reboot
```

---

## Adding Weather (Optional)

Want to show local weather between photos?

1. Go to [Weather Underground](https://www.wunderground.com/member/api-keys)
2. Sign up and get an API key
3. Find a station near you at [Wundermap](https://www.wunderground.com/wundermap)
4. Add to `config.json`:
   ```json
   "weather": {
       "api_key": "your-weather-api-key",
       "station_id": "KNYNEWY123"
   }
   ```

Leave these empty to show only photos.

---

## Adding & Removing Photos

Just add or remove images from your Google Drive folder!

- Supported: JPG, PNG, GIF, WebP
- Changes appear within 1 hour
- Force refresh: http://localhost:5000/api/refresh

---

## Useful URLs

| URL | What it does |
|-----|--------------|
| http://localhost:5000 | The slideshow |
| http://localhost:5000/health | Server status |
| http://localhost:5000/api/images | List all images |
| http://localhost:5000/api/refresh | Refresh now |

---

## Portrait Mode (Optional)

To rotate your display:

```bash
sudo nano /boot/firmware/config.txt
```

Add at the end:
```
display_rotate=1
```

Save and reboot.

---

## Troubleshooting

**No images?**
- Check folder is public (Share → Anyone with the link)
- Verify folder ID and API key in `config.json`
- Check logs: `cat ~/slideshow/server.log`

**API error?**
- Make sure Google Drive API is enabled in Cloud Console
- Check your API key is correct

**Auto-start not working?**
- Check script is executable: `chmod +x ~/slideshow/start_slideshow.sh`
- Verify path in autostart file

---

## Files

```
~/slideshow/
├── config.json          # Your settings
├── server.py            # Backend server
├── slideshow.html       # Frontend display
├── start_slideshow.sh   # Startup script
├── requirements.txt     # Python packages
└── image_cache.pkl      # Auto-created cache
```

---

## How It Works

1. Server fetches image list from your public Google Drive folder using the API
2. Images are cached locally (works offline temporarily)
3. Browser displays fullscreen slideshow
4. Everything refreshes automatically

No OAuth, no tokens, no complicated auth — just a simple API key!
