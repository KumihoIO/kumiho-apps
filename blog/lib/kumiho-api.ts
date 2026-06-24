import { BlogPost, BlogPostCreate } from './types';
import { auth } from './firebase';
export type { BlogPost, BlogPostCreate };

export interface Project {
    name: string;
    description?: string;
}

export interface Space {
    name: string;
    path: string;
    description?: string;
}

const isServer = typeof window === 'undefined';
const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8001';
const SERVER_KUMIHO_TOKEN = process.env.KUMIHO_SERVICE_TOKEN;

// Configuration state
const config = {
    tenantId: '',
    projectNames: [] as string[],
};

export const configureKumiho = (tenantId: string, projectNames: string[]) => {
    config.tenantId = tenantId;
    config.projectNames = projectNames;
};

export const getProjectName = () => config.projectNames[0] || process.env.NEXT_PUBLIC_KUMIHO_PROJECT_NAME || "MyBlog";

// Server-side uses FastAPI's /api/v1/ directly
// Client-side uses Next.js proxy routes at /api/ (which forward to FastAPI)
const getBaseUrl = () => isServer ? `${API_URL}/api/v1` : '/api';

// Blog endpoints path - different for server (direct) vs client (proxy)
const getBlogPath = () => isServer ? 'apps/blog' : 'blog';
const getTenantPath = () => isServer ? 'tenant' : 'auth';

const getHeaders = (baseHeaders: HeadersInit = {}, userToken?: string) => {
    const headers = new Headers(baseHeaders);

    // Server-side: include service token for direct FastAPI calls
    // Client-side: no token needed - Next.js API routes add it
    if (isServer && SERVER_KUMIHO_TOKEN) {
        headers.set('X-Kumiho-Token', SERVER_KUMIHO_TOKEN);
    }

    if (userToken) {
        headers.set('Authorization', `Bearer ${userToken}`);
    }

    if (config.tenantId) {
        headers.set('X-Kumiho-Tenant-ID', config.tenantId);
    }

    return headers;
};

/**
 * Fetch with automatic token refresh on authentication errors.
 * 
 * If a request fails with 401 or 500 (which can indicate token issues),
 * this function will attempt to refresh the Firebase token and retry once.
 * 
 * @param url - The URL to fetch
 * @param options - Fetch options
 * @param originalToken - The original token used (for retry comparison)
 * @returns Promise<Response>
 */
async function fetchWithTokenRetry(
    url: string,
    options: RequestInit,
    originalToken?: string
): Promise<Response> {
    const response = await fetch(url, options);

    // If request succeeded, return immediately
    if (response.ok) {
        return response;
    }

    // On auth errors or server errors that might be token-related, try refreshing
    if ((response.status === 401 || response.status === 500) && !isServer) {
        try {
            // Get current Firebase user
            const user = auth.currentUser;
            if (user) {
                console.log('Token might be expired, refreshing...');

                // Force refresh the token
                const freshToken = await user.getIdToken(true);

                // Only retry if we got a different token
                if (freshToken !== originalToken) {
                    console.log('Got fresh token, retrying request...');

                    // Update headers with fresh token
                    const freshOptions = {
                        ...options,
                        headers: getHeaders(
                            (options.headers as HeadersInit) || {},
                            freshToken
                        )
                    };

                    // Retry the request once
                    const retryResponse = await fetch(url, freshOptions);

                    if (retryResponse.ok) {
                        console.log('Retry succeeded with fresh token');
                    }

                    return retryResponse;
                }
            }
        } catch (error) {
            console.error('Token refresh failed:', error);
            // Fall through to return original response
        }
    }

    // Return original response if no retry or retry not applicable
    return response;
}


export const kumihoApi = {
    async listPosts(spacePath?: string, token?: string): Promise<BlogPost[]> {
        const path = spacePath || `/${getProjectName()}`;
        const response = await fetchWithTokenRetry(
            `${getBaseUrl()}/${getBlogPath()}/posts?space_path=${encodeURIComponent(path)}`,
            {
                cache: 'no-store',
                headers: getHeaders({}, token)
            },
            token
        );

        if (!response.ok) {
            throw new Error(`Failed to fetch posts: ${response.statusText}`);
        }

        return response.json();
    },

    async getPost(slug: string, spacePath?: string, revision?: string, token?: string): Promise<BlogPost> {
        const path = spacePath || `/${getProjectName()}`;
        let url = `${getBaseUrl()}/${getBlogPath()}/posts/${slug}?space_path=${encodeURIComponent(path)}`;
        if (revision) {
            url += `&revision=${encodeURIComponent(revision)}`;
        }

        const response = await fetchWithTokenRetry(
            url,
            {
                cache: 'no-store',
                headers: getHeaders({}, token)
            },
            token
        );

        if (!response.ok) {
            throw new Error(`Failed to fetch post: ${response.statusText}`);
        }

        return response.json();
    },

    async createPost(post: BlogPostCreate, publish: boolean = false, token?: string): Promise<BlogPost> {
        const response = await fetch(`${getBaseUrl()}/${getBlogPath()}/posts?publish=${publish}`, {
            method: 'POST',
            headers: getHeaders({
                'Content-Type': 'application/json',
            }, token),
            body: JSON.stringify(post),
        });

        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.detail || 'Failed to create post');
        }

        return response.json();
    },

    async updatePost(slug: string, post: BlogPostCreate, spacePath?: string, publish: boolean = false, token?: string): Promise<BlogPost> {
        const path = spacePath || `/${getProjectName()}`;
        const response = await fetch(
            `${getBaseUrl()}/${getBlogPath()}/posts/${slug}?space_path=${encodeURIComponent(path)}&publish=${publish}`,
            {
                method: 'PUT',
                headers: getHeaders({
                    'Content-Type': 'application/json',
                }, token),
                body: JSON.stringify(post),
            }
        );

        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.detail || 'Failed to update post');
        }

        return response.json();
    },

    async publishPost(slug: string, revisionNumber: string = '1', spacePath?: string, token?: string): Promise<void> {
        const path = spacePath || `/${getProjectName()}`;
        const response = await fetch(
            `${getBaseUrl()}/${getBlogPath()}/posts/${slug}/publish?revision_number=${revisionNumber}&space_path=${encodeURIComponent(path)}`,
            {
                method: 'POST',
                headers: getHeaders({}, token)
            }
        );

        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.detail || 'Failed to publish post');
        }
    },

    async deletePost(slug: string, spacePath?: string, token?: string): Promise<void> {
        const path = spacePath || `/${getProjectName()}`;
        const response = await fetch(
            `${getBaseUrl()}/${getBlogPath()}/posts/${slug}?space_path=${encodeURIComponent(path)}`,
            {
                method: 'DELETE',
                headers: getHeaders({}, token)
            }
        );

        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.detail || 'Failed to delete post');
        }
    },

    async listProjects(token?: string): Promise<Project[]> {
        const response = await fetch(`${getBaseUrl()}/projects`, {
            cache: 'no-store',
            headers: getHeaders({}, token)
        });

        if (!response.ok) {
            throw new Error(`Failed to fetch projects: ${response.statusText}`);
        }

        return response.json();
    },

    async listSpaces(parentPath: string, recursive: boolean = false, token?: string): Promise<Space[]> {
        const response = await fetchWithTokenRetry(
            `${getBaseUrl()}/spaces?parent_path=${encodeURIComponent(parentPath)}&recursive=${recursive}`,
            {
                cache: 'no-store',
                headers: getHeaders({}, token)
            },
            token
        );

        if (!response.ok) {
            if (response.status === 404) {
                return [];
            }
            throw new Error(`Failed to fetch spaces: ${response.statusText}`);
        }

        return response.json();
    },

    async createSpace(name: string, parentPath: string, token?: string): Promise<Space> {
        const response = await fetch(`${getBaseUrl()}/spaces`, {
            method: 'POST',
            headers: getHeaders({
                'Content-Type': 'application/json',
            }, token),
            body: JSON.stringify({
                parent_path: parentPath,
                name: name
            }),
        });

        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.detail || 'Failed to create space');
        }

        return response.json();
    },

    async getSettings(projectName: string, token?: string): Promise<{
        project_name: string;
        post_item_kind: string;
        pagination_count: number;
        display_type: string;
        display_category_filters: boolean;
    }> {
        const response = await fetchWithTokenRetry(
            `${getBaseUrl()}/${getBlogPath()}/settings?project_name=${encodeURIComponent(projectName)}`,
            {
                cache: 'no-store',
                headers: getHeaders({}, token)
            },
            token
        );

        if (!response.ok) {
            throw new Error(`Failed to fetch settings: ${response.statusText}`);
        }

        return response.json();
    },

    async saveSettings(
        projectName: string,
        settings: {
            post_item_kind: string;
            pagination_count: number;
            display_type: string;
            display_category_filters: boolean;
        },
        token?: string
    ): Promise<void> {
        const response = await fetch(`${getBaseUrl()}/${getBlogPath()}/settings`, {
            method: 'POST',
            headers: getHeaders({
                'Content-Type': 'application/json',
            }, token),
            body: JSON.stringify({
                project_name: projectName,
                ...settings
            }),
        });

        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.detail || 'Failed to save settings');
        }
    },

    async getCurrentUser(token?: string): Promise<{ email: string; id: string }> {
        const response = await fetch(`${getBaseUrl()}/${getTenantPath()}/whoami?project_name=${encodeURIComponent(getProjectName())}`, {
            cache: 'no-store',
            headers: getHeaders({}, token)
        });

        if (!response.ok) {
            // If auth fails, return anonymous
            console.error(`getCurrentUser failed: ${response.status} ${response.statusText}`);
            try {
                const err = await response.json();
                console.error('Error details:', err);
            } catch (e) { /* ignore */ }
            return { email: 'anonymous', id: 'anonymous' };
        }

        return response.json();
    },
};
