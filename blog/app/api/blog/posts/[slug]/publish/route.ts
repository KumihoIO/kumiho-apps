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

export async function POST(request: NextRequest, { params }: RouteParams) {
    const { slug } = await params;
    const searchParams = request.nextUrl.searchParams;
    const spacePath = searchParams.get('space_path') || '';
    const revisionNumber = searchParams.get('revision_number') || '1';

    try {
        const headers = buildForwardHeaders(request);

        const response = await fetch(
            `${API_URL}/api/v1/apps/blog/posts/${slug}/publish?space_path=${encodeURIComponent(spacePath)}&revision_number=${encodeURIComponent(revisionNumber)}`,
            {
                method: 'POST',
                headers,
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
