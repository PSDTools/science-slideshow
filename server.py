#!/usr/bin/env python3
"""
Simple Flask server for a photo slideshow.
Automatically fetches images from a PUBLIC Google Drive folder.
No API keys needed - just the folder ID!
"""

from flask import Flask, jsonify, send_from_directory
from flask_cors import CORS
import os
import json
import re
import time
import pickle
import urllib.request
import urllib.error
from threading import Thread, Lock

app = Flask(__name__)
CORS(app)

CONFIG_FILE = 'config.json'
CACHE_FILE = 'image_cache.pkl'
CACHE_DURATION = 3600  # 1 hour

# Thread-safe global cache
image_list = []
last_update = 0
cache_lock = Lock()

def load_config():
    """Load configuration from config.json."""
    if not os.path.exists(CONFIG_FILE):
        print(f"ERROR: {CONFIG_FILE} not found!")
        return None
    with open(CONFIG_FILE, 'r') as f:
        return json.load(f)

config = load_config()

def fetch_public_folder(folder_id):
    """Fetch image list from a public Google Drive folder (no API key needed)."""
    global image_list, last_update

    if not folder_id:
        print("ERROR: No folder_id in config.json")
        return []

    print(f"Fetching images from public folder: {folder_id}")

    try:
        # Fetch the public folder page
        url = f"https://drive.google.com/drive/folders/{folder_id}"
        req = urllib.request.Request(url, headers={
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        })

        with urllib.request.urlopen(req, timeout=30) as response:
            html = response.read().decode('utf-8')

        # Extract file data from the page
        # Google Drive embeds JSON data in the page containing file info
        files = []

        # Pattern to find file IDs and names in the page data
        # Look for patterns like: ["FILE_ID","FILE_NAME",...]
        pattern = r'\["([a-zA-Z0-9_-]{25,})","([^"]+)"'
        matches = re.findall(pattern, html)

        seen_ids = set()
        for file_id, file_name in matches:
            # Filter for image files by extension
            lower_name = file_name.lower()
            if any(lower_name.endswith(ext) for ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp']):
                if file_id not in seen_ids:
                    seen_ids.add(file_id)
                    files.append({
                        'id': file_id,
                        'name': file_name,
                        'url': f"https://drive.google.com/uc?export=view&id={file_id}"
                    })

        # Sort by name
        files.sort(key=lambda x: x['name'])

        with cache_lock:
            image_list = files
            last_update = time.time()

        # Save to cache
        with open(CACHE_FILE, 'wb') as f:
            pickle.dump({'images': image_list, 'time': last_update}, f)

        print(f"Found {len(files)} images")
        return files

    except urllib.error.URLError as e:
        print(f"Network error fetching folder: {e}")
        return []
    except Exception as e:
        print(f"Error fetching folder: {e}")
        return []

def load_cache():
    """Load cached image list."""
    global image_list, last_update
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, 'rb') as f:
                data = pickle.load(f)
                with cache_lock:
                    image_list = data.get('images', [])
                    last_update = data.get('time', 0)
                print(f"Loaded {len(image_list)} images from cache")
        except Exception as e:
            print(f"Error loading cache: {e}")

def update_periodically():
    """Background thread to update images periodically."""
    folder_id = config.get('google_drive', {}).get('folder_id', '') if config else ''
    while True:
        with cache_lock:
            current_last_update = last_update
        if time.time() - current_last_update > CACHE_DURATION:
            fetch_public_folder(folder_id)
        time.sleep(300)  # Check every 5 minutes

@app.route('/api/images')
def get_images():
    """API endpoint to get list of images."""
    folder_id = config.get('google_drive', {}).get('folder_id', '') if config else ''

    with cache_lock:
        current_last_update = last_update

    if time.time() - current_last_update > CACHE_DURATION:
        fetch_public_folder(folder_id)

    with cache_lock:
        return jsonify({
            'images': image_list,
            'count': len(image_list),
            'last_updated': last_update
        })

@app.route('/api/refresh')
def refresh_images():
    """Manually refresh the image list."""
    folder_id = config.get('google_drive', {}).get('folder_id', '') if config else ''
    fetch_public_folder(folder_id)
    with cache_lock:
        return jsonify({
            'status': 'success',
            'count': len(image_list)
        })

@app.route('/api/config')
def get_config():
    """Get frontend configuration."""
    if not config:
        return jsonify({'error': 'Configuration not loaded'}), 500
    return jsonify({
        'weather': config.get('weather', {}),
        'slideshow': config.get('slideshow', {})
    })

@app.route('/health')
def health():
    """Health check endpoint."""
    with cache_lock:
        return jsonify({
            'status': 'ok',
            'images_cached': len(image_list),
            'last_update': last_update
        })

@app.route('/')
def index():
    """Serve the slideshow HTML."""
    return send_from_directory('.', 'slideshow.html')

if __name__ == '__main__':
    if not config:
        print("Cannot start server without configuration.")
        exit(1)

    folder_id = config.get('google_drive', {}).get('folder_id', '')
    print("Starting slideshow server...")
    print(f"Folder ID: {folder_id or '(not configured)'}")

    # Load cache first
    load_cache()

    # Fetch images on startup
    with cache_lock:
        current_image_list = image_list
    if not current_image_list and folder_id:
        fetch_public_folder(folder_id)

    # Start background update thread
    update_thread = Thread(target=update_periodically, daemon=True)
    update_thread.start()

    # Start Flask server
    host = config.get('server', {}).get('host', '0.0.0.0')
    port = config.get('server', {}).get('port', 5000)
    print(f"\nServer running at: http://localhost:{port}")
    app.run(host=host, port=port, debug=False)
