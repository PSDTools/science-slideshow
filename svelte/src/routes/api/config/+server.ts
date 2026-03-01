import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getConfig } from '$lib/server/config';

export const GET: RequestHandler = () => {
	const config = getConfig();
	const w = config.weather ?? {};
	return json({
		weather: {
			station_id: w.station_id ?? '',
			enabled: Boolean(w.api_key && w.station_id)
		},
		slideshow: config.slideshow ?? {},
		arc: config.arc ?? {}
	});
};
