# Automatic Google Drive Slideshow Setup

This solution automatically fetches all images from your Google Drive folder - no manual list needed!

## Architecture

- **Flask Server** (Python) - Fetches images from Google Drive every hour
- **HTML Slideshow** - Displays weather + images
- Both run locally on your Raspberry Pi

Your folder ID is already configured: **1Qqbx33gluivSQDoYCDXVRCoEzOYRG6Ao**

---

## Setup Steps

### 1. Get Google Drive API Credentials

You need to do this **once** to allow your Pi to access your Drive folder.

#### A. Go to Google Cloud Console
Visit: https://console.cloud.google.com/

#### B. Create a Project
1. Click "Select a project" (top left)
2. Click "New Project"
3. Name it "Slideshow" and click "Create"

#### C. Enable Google Drive API
1. In the search bar, type "Google Drive API"
2. Click on it
3. Click "Enable"

#### D. Create Credentials
1. Click "Create Credentials" → "OAuth client ID"
2. If prompted, configure consent screen:
   - User Type: External
   - App name: "Slideshow"
   - Your email
   - Click "Save and Continue" through all steps
3. Back at Create OAuth client ID:
   - Application type: **Desktop app**
   - Name: "Slideshow Client"
   - Click "Create"
4. Click "Download JSON"
5. Rename the file to `credentials.json`

### 2. Raspberry Pi Setup

#### Install Raspberry Pi OS
- Use Raspberry Pi Imager
- Choose: **Raspberry Pi OS (64-bit) with Desktop**
- Flash to SD card

#### First Boot
```bash
# Update system
sudo apt update
sudo apt upgrade -y

# Install required packages
sudo apt install -y python3-pip chromium-browser unclutter
```

#### Rotate Display to Portrait
```bash
sudo nano /boot/firmware/config.txt
```

Add at the end:
```
display_rotate=1
```

Save and reboot:
```bash
sudo reboot
```

### 3. Install Slideshow Files

Create the directory:
```bash
mkdir ~/slideshow
cd ~/slideshow
```

Copy these files to `/home/pi/slideshow/`:
- `slideshow.html`
- `server.py`
- `requirements.txt`
- `start_slideshow.sh`
- `credentials.json` (the file you downloaded)

#### Install Python Dependencies
```bash
cd ~/slideshow
pip3 install -r requirements.txt --break-system-packages
```

Make the startup script executable:
```bash
chmod +x ~/slideshow/start_slideshow.sh
```

### 4. First-Time Authentication

Run the server manually to authenticate:

```bash
cd ~/slideshow
python3 server.py
```

A browser window will open asking you to:
1. Choose your Google account
2. Click "Continue" (it will warn the app is unverified - that's OK, it's your app!)
3. Click "Continue" again
4. Grant permissions to view your Drive files
5. Click "Allow"

The browser will show "The authentication flow has completed."

You should see in the terminal:
```
Found X images
Server running at: http://localhost:5000
```

Press Ctrl+C to stop the server. The authentication is now saved in `token.pickle` and won't ask again!

### 5. Test the Slideshow

```bash
python3 server.py
```

In another terminal or just open Chromium:
```bash
chromium-browser http://localhost:5000
```

You should see your slideshow! Press Alt+F4 to exit.

### 6. Configure Auto-Start

```bash
mkdir -p ~/.config/lxsession/LXDE-pi
nano ~/.config/lxsession/LXDE-pi/autostart
```

Add:
```
@/home/pi/slideshow/start_slideshow.sh
```

Save and reboot:
```bash
sudo reboot
```

Your slideshow should start automatically! 🎉

---

## File Structure

```
/home/pi/slideshow/
├── slideshow.html           # The slideshow display
├── server.py               # Flask server (fetches images)
├── requirements.txt        # Python dependencies
├── start_slideshow.sh      # Startup script
├── credentials.json        # Google API credentials (you provide)
├── token.pickle           # Auth token (created on first run)
├── image_cache.pkl        # Cached image list
└── server.log             # Server logs
```

---

## Configuration

### Edit slideshow.html

Add your Weather Underground API credentials (around line 22):

```javascript
WEATHER_API_KEY: 'YOUR_API_KEY_HERE',
STATION_ID: 'YOUR_STATION_ID_HERE',
```

Change timing (in seconds):
```javascript
IMAGE_SLIDE_DURATION: 10,           // How long each image shows
WEATHER_SLIDE_DURATION: 15,         // How long weather shows
WEATHER_REFRESH_INTERVAL: 900,      // Update weather every 15 min
```

### Edit server.py

The folder ID is already set, but if you need to change it:

```python
FOLDER_ID = '1Qqbx33gluivSQDoYCDXVRCoEzOYRG6Ao'  # Your folder
CACHE_DURATION = 3600  # How often to refresh images (1 hour)
```

---

## Usage

### Adding/Removing Images

Just add or remove images from your Google Drive folder!

- Images refresh automatically every hour
- Or manually refresh: `http://localhost:5000/api/refresh`

### Checking Status

While the slideshow is running, you can check:
- Health: `http://localhost:5000/health`
- Image list: `http://localhost:5000/api/images`

### Viewing Logs

```bash
cat ~/slideshow/server.log
```

### Restarting the Slideshow

```bash
sudo reboot
```

Or:
```bash
pkill chromium
pkill python3
cd ~/slideshow
./start_slideshow.sh
```

---

## Troubleshooting

### No images showing?
- Check the server log: `cat ~/slideshow/server.log`
- Make sure you completed authentication (step 4)
- Verify credentials.json is in the slideshow folder
- Check folder ID is correct

### Authentication failed?
- Delete `token.pickle` and run `python3 server.py` again
- Make sure credentials.json is valid

### Server won't start?
```bash
# Check if port 5000 is in use
sudo lsof -i :5000

# Kill any process using it
sudo kill -9 <PID>
```

### Weather not showing?
- Add your Weather Underground API key to slideshow.html
- Check browser console (F12) for errors

### Auto-start not working?
- Check autostart file path: `~/.config/lxsession/LXDE-pi/autostart`
- Make sure start_slideshow.sh is executable: `chmod +x ~/slideshow/start_slideshow.sh`
- Check the script paths match your username (change `/home/pi/` if needed)

---

## Benefits of This Setup

✅ **Automatic** - Just add/remove images from Drive  
✅ **Simple** - Only runs on your Pi, no external servers needed  
✅ **Cached** - Works even if internet drops temporarily  
✅ **Secure** - Your credentials stay on your Pi  
✅ **Low maintenance** - Set it and forget it!

---

## Next Steps

1. Set up Google Cloud credentials
2. Copy files to your Pi
3. Run authentication once
4. Add your Weather Underground API key
5. Reboot and enjoy! 🎉
