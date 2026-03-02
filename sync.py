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
import requests
import re
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

def copy_config(config):
    # Pass the config to the frontend as well
    with open(API_DIR / "config.json", "w") as f:
        json.dump(config, f)

def main():
    print("[sync] Starting sync loop...")
    while True:
        try:
            config = load_config()
            copy_config(config)
            sync_weather(config)
            sync_images(config)
        except Exception as e:
            print(f"[sync] Fatal loop error: {e}")
            
        # Wait 5 minutes before next sync
        time.sleep(300)

if __name__ == "__main__":
    main()
