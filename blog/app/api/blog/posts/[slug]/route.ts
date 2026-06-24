import { NextRequest, NextResponse } from 'next/server';

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8001';
const KUMIHO_SERVICE_TOKEN = process.env.KUMIHO_SERVICE_TOKEN;

const buildForwardHeaders = (request: NextRequest) => {
    const headers: Record<string, string> = {};

    const serviceToken = request.headers.get('x-kumiho-token') || KUMIHO_SERVICE_TOKEN || '';
    if (serviceToken) {
        headers['X-Kumiho-Token'] = serviceToken;
    }

    const tenantId = request.headers.get('x-kumiho-tenant-id');
    if (tenantId) {
        headers['X-Kumiho-Tenant-ID'] = tenantId;
    }

    const authHeader = request.headers.get('authorization');
    if (authHeader) {
        headers['Authorization'] = authHeader;
    }

    return headers;
};

interface RouteParams {
    params: Promise<{ slug: string }>;
}

export async function GET(request: NextRequest, { params }: RouteParams) {
    const { slug } = await params;
    const searchParams = request.nextUrl.searchParams;
    const spacePath = searchParams.get('space_path') || '';

    const revision = searchParams.get('revision');
    let url = `${API_URL}/api/v1/apps/blog/posts/${slug}?space_path=${encodeURIComponent(spacePath)}`;
    if (revision) {
        url += `&revision=${encodeURIComponent(revision)}`;
    }

    try {
        const headers = buildForwardHeaders(request);

        const response = await fetch(
            url,
            {
                headers,
                cache: 'no-store',
            }
        );

        if (!response.ok) {
            return NextResponse.json(
                { error: 'Failed to fetch post' },
                { status: response.status }
            );
        }

        const data = await response.json();
        return NextResponse.json(data);
    } catch (error) {
        return NextResponse.json(
            { error: 'Internal server error' },
            { status: 500 }
        );
    }
}

export async function PUT(request: NextRequest, { params }: RouteParams) {
    const { slug } = await params;
    const searchParams = request.nextUrl.searchParams;
    const spacePath = searchParams.get('space_path') || '';
    const publish = searchParams.get('publish') || 'false';

    try {
        const body = await request.json();
        const headers = {
            ...buildForwardHeaders(request),
            'Content-Type': 'application/json',
        };

        const response = await fetch(
            `${API_URL}/api/v1/apps/blog/posts/${slug}?space_path=${encodeURIComponent(spacePath)}&publish=${publish}`,
            {
                method: 'PUT',
                headers,
                body: JSON.stringify(body),
            }
        );

        if (!response.ok) {
            const error = await response.json();
            return NextResponse.json(error, { status: response.status });
        }

        const data = await response.json();
        return NextResponse.json(data);
    } catch (error) {
        return NextResponse.json(
            { error: 'Internal server error' },
            { status: 500 }
        );
    }
}

export async function DELETE(request: NextRequest, { params }: RouteParams) {
    const { slug } = await params;
    const searchParams = request.nextUrl.searchParams;
    const spacePath = searchParams.get('space_path') || '';

    try {
        const headers = buildForwardHeaders(request);

        const response = await fetch(
            `${API_URL}/api/v1/apps/blog/posts/${slug}?space_path=${encodeURIComponent(spacePath)}`,
            {
                method: 'DELETE',
                headers,
            }
        );

        if (!response.ok) {
            const error = await response.json();
            return NextResponse.json(error, { status: response.status });
        }

        return NextResponse.json({ message: 'Post deleted' });
    } catch (error) {
        return NextResponse.json(
            { error: 'Internal server error' },
            { status: 500 }
        );
    }
}

export async function POST(request: NextRequest, { params }: RouteParams) {
    // Handle publish (POST /posts/{slug}/publish)
    // But wait, the backend route is /posts/{slug}/publish
    // kumiho-api.ts calls /api/blog/posts/{slug}/publish
    // So we need another route file for that: [slug]/publish/route.ts
    // Or we can handle it here if we check the URL? No, Next.js routing is file-based.
    // So this file only handles GET, PUT, DELETE for /posts/{slug}
    return NextResponse.json({ error: 'Method not allowed' }, { status: 405 });
}
