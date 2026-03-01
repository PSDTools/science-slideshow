import type { RequestHandler } from './$types';
import { proxyImage } from '$lib/server/images';

export const GET: RequestHandler = async ({ params }) => {
	const { fileId } = params;
	const result = await proxyImage(fileId);
	if (!result) {
		return new Response('Not found', { status: 404 });
	}
	return new Response(result.data, {
		headers: {
			'Content-Type': result.mime,
			'Cache-Control': 'public, max-age=86400'
		}
	});
};
