import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getConfig } from '$lib/server/config';
import { fetchPublicFolder, getCachedImages } from '$lib/server/images';

export const GET: RequestHandler = async () => {
	const config = getConfig();
	const folderId = config.google_drive?.folder_id ?? '';
	await fetchPublicFolder(folderId);
	const { images } = getCachedImages();
	return json({ status: 'success', count: images.length });
};
