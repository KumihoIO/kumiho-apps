import { NextResponse } from 'next/server';

export async function GET() {
    try {
        const token = process.env.KUMIHO_SERVICE_TOKEN;
        const projectName = process.env.NEXT_PUBLIC_KUMIHO_PROJECT_NAME || 'MyBlog';

        if (!token) {
            console.error('KUMIHO_SERVICE_TOKEN not found in environment');
            return NextResponse.json({ error: 'Server configuration error' }, { status: 500 });
        }

        // Simple JWT decode without verification (server-side trusted token)
        const parts = token.split('.');
        if (parts.length !== 3) {
            console.error('Invalid KUMIHO_SERVICE_TOKEN format');
            return NextResponse.json({ error: 'Invalid token format' }, { status: 500 });
        }

        // Base64 decode the payload
        // Need to handle URL-safe base64
        const base64Url = parts[1];
        let base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
        // Pad with =
        while (base64.length % 4) {
            base64 += '=';
        }

        const payload = JSON.parse(Buffer.from(base64, 'base64').toString());
        const tenantId = payload.tenant_id;

        if (!tenantId) {
            console.error('tenant_id not found in KUMIHO_SERVICE_TOKEN claims');
            return NextResponse.json({ error: 'Invalid token claims' }, { status: 500 });
        }

        return NextResponse.json({
            tenant_id: tenantId,
            project_names: [projectName],
            anonymous_allowed: true
        });

    } catch (error) {
        console.error('Bootstrap error:', error);
        return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }
}
