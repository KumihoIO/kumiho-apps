import { NextRequest, NextResponse } from 'next/server';

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8001';
const KUMIHO_SERVICE_TOKEN = process.env.KUMIHO_SERVICE_TOKEN;

export async function GET(request: NextRequest) {
    try {
        const token = request.headers.get('X-Kumiho-Token') || KUMIHO_SERVICE_TOKEN || '';
        const tenantId = request.headers.get('X-Kumiho-Tenant-ID') || '';

        const headers: Record<string, string> = {
            'X-Kumiho-Token': token,
        };
        if (tenantId) {
            headers['X-Kumiho-Tenant-ID'] = tenantId;
        }

        const searchParams = request.nextUrl.search;
        const response = await fetch(`${API_URL}/api/v1/tenant/whoami${searchParams}`, {
            headers,
            cache: 'no-store',
        });

        if (!response.ok) {
            let errorData = { error: 'Failed to fetch user info' };
            try {
                errorData = await response.json();
            } catch (e) {
                // Ignore json parse error, use default
            }
            return NextResponse.json(
                errorData,
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
