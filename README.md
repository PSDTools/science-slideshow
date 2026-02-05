# Raspberry Pi Photo Slideshow

Automatically displays photos from a public Google Drive folder. Set it and forget it.

**No API keys. No Google Cloud. No accounts.**

---

## Install

```bash
git clone https://github.com/PSDTools/science-slideshow.git ~/slideshow
cd ~/slideshow
pip3 install -r requirements.txt --break-system-packages
```

---

## Setup

### 1. Make your Google Drive folder public

1. Right-click your folder → **Share**
2. Change to **"Anyone with the link"** can view
3. Copy the link

### 2. Get your folder ID

Your link looks like: `https://drive.google.com/drive/folders/ABC123XYZ`

The folder ID is: `ABC123XYZ`

### 3. Edit config.json

```json
{
    "google_drive": {
        "folder_id": "ABC123XYZ"
    }
}
```

### 4. Run

```bash
python3 server.py
```

Open http://localhost:5000 — done!

---

## Auto-Start on Boot

```bash
chmod +x ~/slideshow/start_slideshow.sh
mkdir -p ~/.config/lxsession/LXDE-pi
echo "@/home/pi/slideshow/start_slideshow.sh" >> ~/.config/lxsession/LXDE-pi/autostart
sudo reboot
```

Now just add/remove images from your Google Drive folder. The Pi updates automatically every hour.

---

## config.json

```json
{
    "google_drive": {
        "folder_id": "your-folder-id"
    },
    "weather": {
        "api_key": "",
        "station_id": ""
    },
    "slideshow": {
        "image_duration_seconds": 10,
        "weather_duration_seconds": 15
    },
    "server": {
        "port": 5000
    }
}
```

Weather is optional — leave it empty for photos only.

---

## URLs

| URL | What it does |
|-----|--------------|
| http://localhost:5000 | Slideshow |
| http://localhost:5000/api/refresh | Force refresh now |
| http://localhost:5000/health | Status |

---

## Portrait Mode

```bash
sudo nano /boot/firmware/config.txt
```

Add: `display_rotate=1` and reboot.

---

## How It Works

1. Pi fetches your public Google Drive folder
2. Finds all images (jpg, png, gif, webp)
3. Displays them in a fullscreen slideshow
4. Auto-refreshes every hour

That's it. No APIs, no tokens, no cloud console.
