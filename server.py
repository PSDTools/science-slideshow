#!/usr/bin/env python3
"""
Simple Flask server for a photo slideshow.
Automatically fetches images from a PUBLIC Google Drive folder.
No API keys needed - just the folder ID!
"""

from flask import Flask, jsonify, send_from_directory, Response
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
        # Google Drive embeds JSON data with HTML-encoded quotes
        files = []

        # Unescape HTML entities
        html = html.replace('&quot;', '"').replace('&#39;', "'")

        # Find all image filenames (excluding Google's static assets)
        img_extensions = r'\.(?:jpg|jpeg|png|gif|webp|bmp)'
        name_pattern = rf'"([^"/]+{img_extensions})"'
        all_names = re.findall(name_pattern, html, re.IGNORECASE)

        # Filter out Google's own images
        image_names = [n for n in all_names if not n.startswith('//') and 'gstatic' not in n]
        image_names = list(dict.fromkeys(image_names))  # Remove duplicates, keep order

        # For each image name, find the file ID that appears before it
        for name in image_names:
            # Find position of this filename
            search_str = f'"{name}"'
            pos = html.find(search_str)
            if pos > 0:
                # Look backwards for a file ID (33 chars, alphanumeric with - and _)
                context_before = html[max(0, pos-600):pos]
                # File IDs in Drive are typically 33 characters
                ids = re.findall(r'"([a-zA-Z0-9_-]{33})"', context_before)
                if ids:
                    # Take the last (closest) ID
                    file_id = ids[-1]
                    files.append({
                        'id': file_id,
                        'name': name,
                        'url': f"https://drive.google.com/uc?export=view&id={file_id}"
                    })

        # Remove duplicates by ID and use local proxy URL
        seen_ids = set()
        unique_files = []
        for f in files:
            if f['id'] not in seen_ids:
                seen_ids.add(f['id'])
                unique_files.append({
                    'id': f['id'],
                    'name': f['name'],
                    'url': f"/image/{f['id']}"  # Use local proxy
                })
        files = unique_files

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

IMAGE_CACHE_DIR = 'image_cache'

# Create cache directory
os.makedirs(IMAGE_CACHE_DIR, exist_ok=True)

@app.route('/image/<file_id>')
def proxy_image(file_id):
    """Proxy and cache Google Drive images."""
    # Validate file_id (alphanumeric, dash, underscore only)
    if not re.match(r'^[a-zA-Z0-9_-]+$', file_id):
        return "Invalid file ID", 400

    # Check local cache first
    cache_path = os.path.join(IMAGE_CACHE_DIR, f"{file_id}.jpg")
    if os.path.exists(cache_path):
        return send_from_directory(IMAGE_CACHE_DIR, f"{file_id}.jpg", mimetype='image/jpeg')

    # Fetch from Google Drive
    try:
        drive_url = f"https://drive.google.com/uc?export=view&id={file_id}"
        req = urllib.request.Request(drive_url, headers={
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        })

        with urllib.request.urlopen(req, timeout=30) as response:
            image_data = response.read()

        # Save to cache
        with open(cache_path, 'wb') as f:
            f.write(image_data)

        return Response(image_data, mimetype='image/jpeg')
    except Exception as e:
        return f"Error loading image: {e}", 500

@app.route('/')
def index():
    """Serve the slideshow HTML."""
    return send_from_directory('.', 'slideshow.html')

@app.route('/weather')
def weather_test():
    """Show weather slide with test data."""
    return '''<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Weather Test</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            width: 100vw;
            height: 100vh;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            display: flex;
            flex-direction: column;
            justify-content: center;
            align-items: center;
            text-align: center;
            padding: 40px;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            color: white;
        }
        .station { font-size: 36px; opacity: 0.9; margin-bottom: 20px; }
        .temp { font-size: 120px; font-weight: 700; margin: 20px 0; }
        .details { display: flex; gap: 40px; margin-top: 40px; flex-wrap: wrap; justify-content: center; }
        .detail { background: rgba(255,255,255,0.15); padding: 25px 35px; border-radius: 15px; }
        .detail .label { font-size: 14px; opacity: 0.8; text-transform: uppercase; margin-bottom: 8px; }
        .detail .value { font-size: 32px; font-weight: 600; }
        .updated { position: absolute; bottom: 30px; font-size: 16px; opacity: 0.6; }
    </style>
</head>
<body>
    <div class="station">KTEST001</div>
    <div class="temp">72°F</div>
    <div class="details">
        <div class="detail"><div class="label">Humidity</div><div class="value">45%</div></div>
        <div class="detail"><div class="label">Wind</div><div class="value">8 mph</div></div>
        <div class="detail"><div class="label">Pressure</div><div class="value">30.12"</div></div>
    </div>
    <div class="updated">Updated: ''' + time.strftime("%I:%M %p") + '''</div>
</body>
</html>'''

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
