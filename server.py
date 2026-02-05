#!/usr/bin/env python3
"""
Simple Flask server to fetch images from a PUBLIC Google Drive folder.
No OAuth needed - just an API key.
"""

from flask import Flask, jsonify, send_from_directory
from flask_cors import CORS
import os
import json
import pickle
import requests
import time
from threading import Thread, Lock

app = Flask(__name__)
CORS(app)

# Load configuration
CONFIG_FILE = 'config.json'

def load_config():
    """Load configuration from config.json."""
    if not os.path.exists(CONFIG_FILE):
        print(f"ERROR: {CONFIG_FILE} not found!")
        return None

    with open(CONFIG_FILE, 'r') as f:
        return json.load(f)

config = load_config()

# Configuration from config file
FOLDER_ID = config['google_drive']['folder_id'] if config else ''
API_KEY = config['google_drive'].get('api_key', '') if config else ''
CACHE_FILE = 'image_cache.pkl'
CACHE_DURATION = 3600  # 1 hour

# Thread-safe global cache
image_list = []
last_update = 0
cache_lock = Lock()

def fetch_images_from_drive():
    """Fetch all images from the public Google Drive folder."""
    global image_list, last_update

    if not FOLDER_ID:
        print("ERROR: Google Drive folder_id not configured in config.json")
        return []

    if not API_KEY:
        print("ERROR: Google Drive api_key not configured in config.json")
        return []

    print("Fetching images from Google Drive...")

    url = "https://www.googleapis.com/drive/v3/files"
    params = {
        'q': f"'{FOLDER_ID}' in parents and mimeType contains 'image/' and trashed=false",
        'fields': 'files(id, name, mimeType)',
        'pageSize': 100,
        'orderBy': 'name',
        'key': API_KEY
    }

    try:
        response = requests.get(url, params=params)
        response.raise_for_status()
        data = response.json()

        files = data.get('files', [])

        new_image_list = [
            {
                'id': file['id'],
                'name': file['name'],
                'url': f"https://drive.google.com/uc?export=view&id={file['id']}"
            }
            for file in files
        ]

        with cache_lock:
            image_list = new_image_list
            last_update = time.time()

        # Save to cache
        with open(CACHE_FILE, 'wb') as f:
            pickle.dump({'images': image_list, 'time': last_update}, f)

        print(f"Found {len(image_list)} images")
        return image_list

    except Exception as e:
        print(f"Error fetching images: {e}")
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

def update_images_periodically():
    """Background thread to update images periodically."""
    while True:
        with cache_lock:
            current_last_update = last_update

        if time.time() - current_last_update > CACHE_DURATION:
            fetch_images_from_drive()
        time.sleep(300)  # Check every 5 minutes

@app.route('/api/images')
def get_images():
    """API endpoint to get list of images."""
    with cache_lock:
        current_last_update = last_update

    # If cache is old, fetch new data
    if time.time() - current_last_update > CACHE_DURATION:
        fetch_images_from_drive()

    with cache_lock:
        return jsonify({
            'images': image_list,
            'count': len(image_list),
            'last_updated': last_update
        })

@app.route('/api/refresh')
def refresh_images():
    """Manually refresh the image list."""
    fetch_images_from_drive()
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
        'weather': {
            'api_key': config['weather']['api_key'],
            'station_id': config['weather']['station_id']
        },
        'slideshow': config['slideshow']
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
        print("Please create config.json with your settings.")
        exit(1)

    print("Starting slideshow server...")
    print(f"Folder ID: {FOLDER_ID or '(not configured)'}")

    # Load cache first
    load_cache()

    # Fetch images on startup
    with cache_lock:
        current_image_list = image_list

    if not current_image_list and FOLDER_ID and API_KEY:
        fetch_images_from_drive()

    # Start background update thread
    update_thread = Thread(target=update_images_periodically, daemon=True)
    update_thread.start()

    # Start Flask server
    host = config['server']['host']
    port = config['server']['port']
    print(f"\nServer running at: http://localhost:{port}")
    print(f"Open http://localhost:{port} in Chromium to see the slideshow")
    app.run(host=host, port=port, debug=False)
