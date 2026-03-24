#!/usr/bin/env python3
"""
sync.py - Slideshow Background Sync Loop
Since Node.js has been removed to preserve Pi RAM, this script periodically fetches
from Google Drive and the Weather API, saving the data as static JSON and JPEG files 
that the purely-static Svelte frontend can read directly from disk.
"""
import os
import json
import time
import subprocess
import requests
import re
from datetime import datetime
from pathlib import Path

# Paths
ROOT_DIR = Path(__file__).parent.absolute()
API_DIR = ROOT_DIR / "svelte" / "build" / "api"
IMG_CACHE_DIR = ROOT_DIR / "svelte" / "build" / "image"
CONFIG_PATH = ROOT_DIR / "config.json"

# Ensure output API and Image cache directories exist
API_DIR.mkdir(parents=True, exist_ok=True)
IMG_CACHE_DIR.mkdir(parents=True, exist_ok=True)

HEADERS = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'}

def load_config():
    if not CONFIG_PATH.exists():
        print("[sync] Missing config.json")
        return {}
    with open(CONFIG_PATH, "r") as f:
        return json.load(f)

def sync_weather(config):
    weather_cfg = config.get("weather", {})
    if not weather_cfg.get("enabled"):
        return
        
    api_key = weather_cfg.get("api_key")
    station_id = weather_cfg.get("station_id")
    if not api_key or not station_id:
        print("[sync] Missing weather api_key or station_id")
        return
        
    print(f"[sync] Fetching weather for {station_id}...")
    try:
        url = f"https://api.weather.com/v2/pws/observations/current?stationId={station_id}&format=json&units=e&apiKey={api_key}"
        res = requests.get(url, headers=HEADERS, timeout=10)
        res.raise_for_status()
        
        data = res.json()
        obs = data.get("observations", [])
        if obs:
            # Write to static API endpoint location for the frontend
            with open(API_DIR / "weather.json", "w") as f:
                json.dump(obs[0], f)
    except Exception as e:
        print(f"[sync] Weather error: {e}")

def sync_images(config):
    folder_id = config.get("google_drive", {}).get("folder_id")
    if not folder_id:
        print("[sync] Missing Google Drive folder_id")
        return
        
    print(f"[sync] Fetching drive folder: {folder_id}...")
    try:
        url = f"https://drive.google.com/drive/folders/{folder_id}"
        res = requests.get(url, headers=HEADERS, timeout=15)
        res.raise_for_status()
        
        html = res.text.replace("&quot;", '"').replace("&#39;", "'")
        
        # Extract images
        img_ext = re.compile(r'\.(jpg|jpeg|png|gif|webp|bmp)', re.I)
        name_pattern = re.compile(r'"([^"/]+\.(jpg|jpeg|png|gif|webp|bmp))"', re.I)
        
        seen_names = set()
        names = []
        for match in name_pattern.finditer(html):
            name = match.group(1)
            if name not in seen_names and img_ext.search(name):
                seen_names.add(name)
                names.append(name)
                
        seen_ids = set()
        files = []
        for name in names:
            pos = html.find(f'"{name}"')
            if pos < 0: continue
            before = html[max(0, pos-600):pos]
            id_matches = re.findall(r'"([a-zA-Z0-9_-]{33})"', before)
            if not id_matches: continue
            file_id = id_matches[-1]
            if file_id not in seen_ids:
                seen_ids.add(file_id)
                # Note: Svelte frontend will load this URL
                files.append({"id": file_id, "name": name, "url": f"/image/{file_id}.jpg"})
                
        files.sort(key=lambda x: x["name"])
        
        with open(API_DIR / "images.json", "w") as f:
            json.dump({"images": files, "count": len(files), "last_updated": int(time.time()*1000)}, f)
            
        print(f"[sync] Found {len(files)} images, downloading thumbnails...")
        # Download missing images
        for f in files:
            img_path = IMG_CACHE_DIR / f"{f['id']}.jpg"
            if not img_path.exists():
                download_thumbnail(f["id"], img_path)
                time.sleep(1) # Be gentle on Drive limits
                
    except Exception as e:
        print(f"[sync] Image fetch error: {e}")

def download_thumbnail(file_id, dest_path):
    print(f"  -> Downloading {file_id}.jpg")
    try:
        url = f"https://drive.google.com/thumbnail?id={file_id}&sz=w1920"
        res = requests.get(url, headers=HEADERS, timeout=12)
        res.raise_for_status()
        with open(dest_path, "wb") as f:
            f.write(res.content)
    except Exception as e:
        print(f"  -> Error downloading {file_id}.jpg: {e}")

SETTINGS_KEYS = {"slideshow", "power_schedule", "arc"}
_last_settings_sync = 0
_cached_drive_settings = {}

def sync_settings(config):
    """Fetch display_settings.json from Google Drive folder (hourly)."""
    global _last_settings_sync, _cached_drive_settings

    # Only fetch once per hour
    if time.time() - _last_settings_sync < 3600:
        return _cached_drive_settings

    folder_id = config.get("google_drive", {}).get("folder_id")
    if not folder_id:
        return _cached_drive_settings

    print("[sync] Checking for display_settings.json in Drive...")
    try:
        # Scrape folder HTML for the settings file
        url = f"https://drive.google.com/drive/folders/{folder_id}"
        res = requests.get(url, headers=HEADERS, timeout=15)
        res.raise_for_status()
        html = res.text.replace("&quot;", '"').replace("&#39;", "'")

        # Find display_settings.json and its file ID
        pattern = re.compile(r'"(display_settings\.json)"', re.I)
        match = pattern.search(html)
        if not match:
            print("[sync] No display_settings.json found in Drive folder")
            _last_settings_sync = time.time()
            return _cached_drive_settings

        pos = html.find('"display_settings.json"')
        before = html[max(0, pos - 600):pos]
        id_matches = re.findall(r'"([a-zA-Z0-9_-]{33})"', before)
        if not id_matches:
            _last_settings_sync = time.time()
            return _cached_drive_settings

        file_id = id_matches[-1]
        dl_url = f"https://drive.google.com/uc?export=download&id={file_id}"
        dl_res = requests.get(dl_url, headers=HEADERS, timeout=10)
        dl_res.raise_for_status()
        settings = dl_res.json()

        # Only keep safe display keys
        _cached_drive_settings = {k: v for k, v in settings.items() if k in SETTINGS_KEYS}
        _last_settings_sync = time.time()
        print(f"[sync] Loaded display_settings.json: {list(_cached_drive_settings.keys())}")
    except Exception as e:
        print(f"[sync] Settings fetch error: {e}")
        _last_settings_sync = time.time()

    return _cached_drive_settings

def merge_config(config, drive_settings):
    """Merge drive display settings over local config for the frontend."""
    merged = json.loads(json.dumps(config))  # deep copy
    for key, value in drive_settings.items():
        if key in SETTINGS_KEYS:
            if isinstance(value, dict) and isinstance(merged.get(key), dict):
                merged[key].update(value)
            else:
                merged[key] = value
    return merged

def copy_config(config):
    # Pass the merged config to the frontend
    with open(API_DIR / "config.json", "w") as f:
        json.dump(config, f)

def check_power_schedule(config):
    """Turn HDMI display on/off based on power_schedule in config."""
    schedule = config.get("power_schedule", {})
    if not schedule.get("enabled"):
        return

    on_time = schedule.get("on_time", "07:00")
    off_time = schedule.get("off_time", "17:00")

    try:
        now = datetime.now().strftime("%H:%M")
        # Compare as strings — works for HH:MM format
        if on_time <= off_time:
            display_on = on_time <= now < off_time
        else:
            # Overnight schedule (e.g., on at 18:00, off at 06:00)
            display_on = now >= on_time or now < off_time

        power_val = "1" if display_on else "0"
        subprocess.run(
            ["vcgencmd", "display_power", power_val],
            capture_output=True, timeout=5
        )
    except Exception as e:
        print(f"[sync] Power schedule error: {e}")

def main():
    print("[sync] Starting sync loop...")
    while True:
        try:
            config = load_config()
            drive_settings = sync_settings(config)
            merged = merge_config(config, drive_settings)
            copy_config(merged)
            sync_weather(merged)
            sync_images(merged)
            check_power_schedule(merged)
        except Exception as e:
            print(f"[sync] Fatal loop error: {e}")

        # Wait 5 minutes before next sync
        time.sleep(300)

if __name__ == "__main__":
    main()
