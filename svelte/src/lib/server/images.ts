import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { resolve, join } from 'path';

export interface DriveImage {
	id: string;
	name: string;
	url: string;
}

interface ImageCache {
	images: DriveImage[];
	lastUpdate: number;
}

const CACHE_DURATION_MS = 60 * 60 * 1000; // 1 hour
const PICKLE_PATH = resolve(process.cwd(), '../image_cache.json');
const IMAGE_CACHE_DIR = resolve(process.cwd(), '../image_cache');

// In-memory cache
let memCache: ImageCache = { images: [], lastUpdate: 0 };

// Ensure cache directory exists
mkdirSync(IMAGE_CACHE_DIR, { recursive: true });

// Load persisted cache on startup
try {
	if (existsSync(PICKLE_PATH)) {
		const raw = JSON.parse(readFileSync(PICKLE_PATH, 'utf-8')) as ImageCache;
		memCache = raw;
		console.log(`[images] Loaded ${memCache.images.length} images from disk cache`);
	}
} catch {
	// ignore
}

export function getCachedImages(): ImageCache {
	return memCache;
}

export function isCacheStale(): boolean {
	return Date.now() - memCache.lastUpdate > CACHE_DURATION_MS;
}

/** Fetch image list from a public Google Drive folder page (no API key needed). */
export async function fetchPublicFolder(folderId: string): Promise<DriveImage[]> {
	if (!folderId) {
		console.error('[images] No folder_id configured');
		return [];
	}

	console.log(`[images] Fetching from Google Drive folder: ${folderId}`);
	try {
		const url = `https://drive.google.com/drive/folders/${folderId}`;
		const res = await fetch(url, {
			headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' }
		});
		let html = await res.text();

		// Unescape HTML entities
		html = html.replace(/&quot;/g, '"').replace(/&#39;/g, "'");

		// Find image filenames
		const imgExtRe = /\.(jpg|jpeg|png|gif|webp|bmp)/i;
		const namePattern = /"([^"/]+\.(jpg|jpeg|png|gif|webp|bmp))"/gi;
		let match: RegExpExecArray | null;
		const seen = new Set<string>();
		const names: string[] = [];
		while ((match = namePattern.exec(html)) !== null) {
			const name = match[1];
			if (!seen.has(name) && imgExtRe.test(name)) {
				seen.add(name);
				names.push(name);
			}
		}

		// For each name, find the Drive file ID that appears just before it  
		const seenIds = new Set<string>();
		const files: DriveImage[] = [];
		for (const name of names) {
			const pos = html.indexOf(`"${name}"`);
			if (pos < 0) continue;
			const before = html.slice(Math.max(0, pos - 600), pos);
			const idMatches = [...before.matchAll(/"([a-zA-Z0-9_-]{33})"/g)];
			if (!idMatches.length) continue;
			const fileId = idMatches[idMatches.length - 1][1];
			if (!seenIds.has(fileId)) {
				seenIds.add(fileId);
				files.push({ id: fileId, name, url: `/image/${fileId}` });
			}
		}

		// Sort by name
		files.sort((a, b) => a.name.localeCompare(b.name));

		memCache = { images: files, lastUpdate: Date.now() };
		// Persist to disk
		writeFileSync(PICKLE_PATH, JSON.stringify(memCache));
		console.log(`[images] Found ${files.length} images`);
		return files;
	} catch (e) {
		console.error('[images] Error fetching folder:', e);
		return memCache.images; // return stale on error
	}
}

/** Proxy and locally cache a single Google Drive image. Returns raw bytes and mime type. */
export async function proxyImage(
	fileId: string
): Promise<{ data: Buffer; mime: string } | null> {
	if (!/^[a-zA-Z0-9_-]+$/.test(fileId)) return null;

	const cachePath = join(IMAGE_CACHE_DIR, `${fileId}.jpg`);
	if (existsSync(cachePath)) {
		return { data: readFileSync(cachePath), mime: 'image/jpeg' };
	}

	try {
		const driveUrl = `https://drive.google.com/uc?export=view&id=${fileId}`;
		const res = await fetch(driveUrl, {
			headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' }
		});
		const buf = Buffer.from(await res.arrayBuffer());
		writeFileSync(cachePath, buf);
		return { data: buf, mime: 'image/jpeg' };
	} catch (e) {
		console.error('[images] Error proxying image:', e);
		return null;
	}
}
