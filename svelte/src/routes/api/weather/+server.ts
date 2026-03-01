import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getConfig } from '$lib/server/config';
import { fetchWeather } from '$lib/server/weather';

export const GET: RequestHandler = async () => {
	const config = getConfig();
	const w = config.weather ?? {};
	const apiKey = w.api_key ?? '';
	const stationId = w.station_id ?? '';

	if (!apiKey || !stationId) {
		return json({ error: 'Weather not configured' }, { status: 404 });
	}

	const { data, error } = await fetchWeather(apiKey, stationId);
	if (error || !data) {
		return json({ error: error ?? 'Unknown error' }, { status: 502 });
	}
	return json(data);
};
