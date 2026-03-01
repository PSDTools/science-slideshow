import { readFileSync, writeFileSync } from 'fs';
import { resolve } from 'path';

export interface ArcConfig {
	xRight: number;
	xLeft: number;
	yHorizon: number;
	yPeak: number;
	arcExp: number;
}

export interface AppConfig {
	google_drive?: { folder_id?: string };
	weather?: { api_key?: string; station_id?: string };
	slideshow?: { image_duration_seconds?: number; weather_duration_seconds?: number };
	arc?: Partial<ArcConfig>;
	server?: { host?: string; port?: number };
}

let _config: AppConfig | null = null;
let _configPath: string | null = null;

/** Load config.json (one directory above the SvelteKit project root). */
export function getConfig(): AppConfig {
	if (_config) return _config;
	_configPath = resolve(process.cwd(), '../config.json');
	try {
		_config = JSON.parse(readFileSync(_configPath, 'utf-8')) as AppConfig;
	} catch (e) {
		console.error('[config] Failed to load config.json from', _configPath, e);
		_config = {};
	}
	return _config;
}

/** Merge `patch` into the in-memory config and persist to disk. */
export function saveConfig(patch: Partial<AppConfig>): void {
	const cfg = getConfig();
	Object.assign(cfg, patch);
	const path = _configPath ?? resolve(process.cwd(), '../config.json');
	writeFileSync(path, JSON.stringify(cfg, null, 4), 'utf-8');
}
