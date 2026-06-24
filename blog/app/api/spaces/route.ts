import { NextRequest, NextResponse } from 'next/server';

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8001';
const KUMIHO_SERVICE_TOKEN = process.env.KUMIHO_SERVICE_TOKEN;

export async function GET(request: NextRequest) {
    const searchParams = request.nextUrl.searchParams;
    const parentPath = searchParams.get('parent_path');
    const recursive = searchParams.get('recursive') === 'true';

    if (!parentPath) {
        return NextResponse.json(
            { error: 'Missing parent_path parameter' },
            { status: 400 }
        );
    }

    const token = request.headers.get('X-Kumiho-Token') || KUMIHO_SERVICE_TOKEN || '';
    const tenantId = request.headers.get('X-Kumiho-Tenant-ID') || '';

    try {
        const headers: Record<string, string> = {
            'X-Kumiho-Token': token,
        };
        if (tenantId) {
            headers['X-Kumiho-Tenant-ID'] = tenantId;
        }

        const response = await fetch(
            `${API_URL}/api/v1/spaces?parent_path=${encodeURIComponent(parentPath)}&recursive=${recursive}`,
            {
                headers,
                cache: 'no-store',
            }
        );

        if (!response.ok) {
            return NextResponse.json(
                { error: 'Failed to fetch spaces' },
                { status: response.status }
            );
        }

        const data = await response.json();
        return NextResponse.json(data);
    } catch (error) {
        console.error('Error in GET /api/spaces:', error);
        return NextResponse.json(
            { error: 'Internal server error', details: String(error) },
            { status: 500 }
        );
    }
}

export async function POST(request: NextRequest) {
    try {
        const body = await request.json();

        const response = await fetch(`${API_URL}/api/v1/spaces`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-Kumiho-Token': KUMIHO_SERVICE_TOKEN || '',
            },
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
