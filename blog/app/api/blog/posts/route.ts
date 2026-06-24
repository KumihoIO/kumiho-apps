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

export async function GET(request: NextRequest) {
    const searchParams = request.nextUrl.searchParams;
    const spacePath = searchParams.get('space_path') || '/MyBlog/posts/tech-news/Kumiho';

    try {
        const headers = buildForwardHeaders(request);
        
        const response = await fetch(
            `${API_URL}/api/v1/apps/blog/posts?space_path=${encodeURIComponent(spacePath)}`,
            {
                headers,
                cache: 'no-store',
            }
        );

        if (!response.ok) {
            const errorBody = await response.text();
            console.error('Blog posts proxy failed:', response.status, errorBody);
            return NextResponse.json(
                { error: 'Failed to fetch posts' },
                { status: response.status }
            );
        }

        const data = await response.json();
        return NextResponse.json(data);
    } catch (error) {
        console.error('Blog posts route error:', error);
        return NextResponse.json(
            { error: 'Internal server error' },
            { status: 500 }
        );
    }
}

export async function POST(request: NextRequest) {
    try {
        const body = await request.json();
        const headers = {
            ...buildForwardHeaders(request),
            'Content-Type': 'application/json',
        };

        const response = await fetch(`${API_URL}/api/v1/apps/blog/posts`, {
            method: 'POST',
            headers,
            body: JSON.stringify(body),
        });

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
