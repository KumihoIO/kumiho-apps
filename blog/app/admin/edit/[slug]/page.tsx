'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import Header from '@/components/Header';
import { kumihoApi, Project, Space } from '@/lib/kumiho-api';
import MDEditor from '@uiw/react-md-editor';
import { use } from 'react';
import { useAuth } from '@/context/AuthContext';

interface PageProps {
    params: Promise<{ slug: string }>;
}

export default function EditPostPage({ params }: PageProps) {
    const { slug } = use(params);
    const router = useRouter();
    const { user, token, loading, isAuthenticated } = useAuth();
    const [isSubmitting, setIsSubmitting] = useState(false);
    const [isLoading, setIsLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);

    // Data for selection
    const [projects, setProjects] = useState<Project[]>([]);
    const [spaces, setSpaces] = useState<Space[]>([]);

    // Selection state
    const [selectedProject, setSelectedProject] = useState<string>('');
    const [selectedSpace, setSelectedSpace] = useState<string>('');

    const [formData, setFormData] = useState({
        title: '',
        content: '',
        tags: '',
    });

    // Redirect if not logged in
    useEffect(() => {
        if (!loading && !isAuthenticated) {
            router.push('/');
        }
    }, [isAuthenticated, loading, router]);

    // Revision state
    const [revisions, setRevisions] = useState<string[]>([]);
    const [selectedRevision, setSelectedRevision] = useState<string>('');

    // Load post and spaces on mount
    useEffect(() => {
        const loadData = async () => {
            // Use default project name (can be overridden by localStorage if set)
            const savedProject = localStorage.getItem('kumiho_blog_project') || 'MyBlog';
            setSelectedProject(savedProject);

            try {
                // Load spaces
                const fetchedSpaces = await kumihoApi.listSpaces(`/${savedProject}`, true);
                setSpaces(fetchedSpaces);

                // Load post
                await loadPost(slug, savedProject, selectedRevision);

                setIsLoading(false);
            } catch (err) {
                console.error('Failed to load post:', err);
                setError('Failed to load post.');
                setIsLoading(false);
            }
        };
        loadData();
    }, [slug]);

    // Reload post when revision changes
    useEffect(() => {
        if (selectedRevision && selectedProject) {
            loadPost(slug, selectedProject, selectedRevision);
        }
    }, [selectedRevision]);

    const loadPost = async (slug: string, project: string, revision?: string) => {
        try {
            const post = await kumihoApi.getPost(slug, `/${project}`, revision, token || undefined);

            setFormData({
                title: post.title,
                content: post.content || '',
                tags: post.tags.join(', '),
            });

            if (post.revisions) {
                setRevisions(post.revisions);
            }

            // If we just loaded the initial post, set the revision
            if (!selectedRevision && post.revision) {
                setSelectedRevision(post.revision);
            }

            // Parse kref to get space path
            try {
                const krefUrl = new URL(post.kref);
                const pathParts = krefUrl.pathname.split('/');
                pathParts.pop();
                const spacePath = '/' + krefUrl.hostname + pathParts.join('/');
                setSelectedSpace(spacePath);
            } catch (e) {
                console.error("Failed to parse kref:", e);
            }
        } catch (err) {
            console.error('Failed to load post revision:', err);
            setError('Failed to load post revision.');
        }
    };

    const handleSave = async (publish: boolean) => {
        setIsSubmitting(true);
        setError(null);

        try {
            const tags = formData.tags
                .split(',')
                .map(tag => tag.trim())
                .filter(tag => tag.length > 0);

            // Construct space path
            const spacePath = selectedSpace || `/${selectedProject}`;

            await kumihoApi.updatePost(slug, {
                title: formData.title,
                content: formData.content,
                tags,
                space_path: spacePath,
            }, spacePath, publish, token || undefined);

            // Reload to get new revision
            // Or redirect? Let's reload the page content to the new revision
            // Actually, updatePost returns the new post, so we can just update state?
            // But simpler to just reload or redirect.
            // Let's redirect to list or stay here?
            // Stay here and reload latest.
            setSelectedRevision(''); // Reset to load latest
            await loadPost(slug, selectedProject);

            setIsSubmitting(false);
            alert(publish ? 'Post published successfully!' : 'Draft saved successfully!');
        } catch (err) {
            setError(err instanceof Error ? err.message : 'Failed to update post');
            setIsSubmitting(false);
        }
    };

    return (
        <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
            <Header />

            <main className="container mx-auto px-4 py-12">
                <div className="max-w-6xl mx-auto">
                    <div className="flex justify-between items-center mb-8">
                        <h1 className="text-4xl font-bold text-gray-900 dark:text-white">
                            Edit Post
                        </h1>

                        {/* Revision Switcher */}
                        <div className="flex items-center gap-2">
                            <label htmlFor="revision" className="text-sm font-medium text-gray-700 dark:text-gray-300">
                                Revision:
                            </label>
                            <select
                                id="revision"
                                value={selectedRevision}
                                onChange={(e) => setSelectedRevision(e.target.value)}
                                className="px-3 py-1 border border-gray-300 dark:border-gray-700 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent bg-white dark:bg-gray-800 text-gray-900 dark:text-white text-sm"
                            >
                                {revisions.map(rev => (
                                    <option key={rev} value={rev}>r{rev}</option>
                                ))}
                            </select>
                        </div>
                    </div>

                    {error && (
                        <div className="bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg p-4 mb-6">
                            <p className="text-red-800 dark:text-red-200">
                                <strong>Error:</strong> {error}
                            </p>
                        </div>
                    )}

                    <form onSubmit={(e) => e.preventDefault()} className="bg-white dark:bg-gray-900 rounded-lg shadow-lg p-8 space-y-6">
                        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                            <div>
                                <label htmlFor="title" className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                                    Title *
                                </label>
                                <input
                                    type="text"
                                    id="title"
                                    required
                                    value={formData.title}
                                    onChange={(e) => setFormData({ ...formData, title: e.target.value })}
                                    className="w-full px-4 py-2 border border-gray-300 dark:border-gray-700 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent bg-white dark:bg-gray-800 text-gray-900 dark:text-white"
                                    placeholder="My Awesome Blog Post"
                                />
                            </div>

                            <div>
                                <label htmlFor="tags" className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                                    Tags (comma-separated)
                                </label>
                                <input
                                    type="text"
                                    id="tags"
                                    value={formData.tags}
                                    onChange={(e) => setFormData({ ...formData, tags: e.target.value })}
                                    className="w-full px-4 py-2 border border-gray-300 dark:border-gray-700 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent bg-white dark:bg-gray-800 text-gray-900 dark:text-white"
                                    placeholder="kumiho, tutorial, api"
                                />
                            </div>
                        </div>

                        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                            <div>
                                <label htmlFor="category" className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                                    Category *
                                </label>
                                    <select
                                        id="category"
                                        required
                                        value={selectedSpace}
                                        onChange={(e) => setSelectedSpace(e.target.value)}
                                        className="w-full px-4 py-2 border border-gray-300 dark:border-gray-700 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent bg-white dark:bg-gray-800 text-gray-900 dark:text-white"
                                    >
                                        <option value="">Select Category</option>
                                        {spaces.map(space => (
                                            <option key={space.path} value={space.path}>{space.path}</option>
                                        ))}
                                    </select>
                            </div>
                        </div>

                        <div>
                            <label htmlFor="content" className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                                Content (Markdown) *
                            </label>
                            <div className="h-[600px]" data-color-mode="auto">
                                <MDEditor
                                    value={formData.content}
                                    onChange={(val: string | undefined) => setFormData({ ...formData, content: val || '' })}
                                    height={600}
                                    preview="live"
                                />
                            </div>
                        </div>

                        <div className="flex gap-4 pt-4">
                            <button
                                type="button"
                                onClick={() => handleSave(false)}
                                disabled={isSubmitting}
                                className="flex-1 px-6 py-3 bg-gray-500 text-white rounded-lg hover:bg-gray-600 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors font-medium"
                            >
                                {isSubmitting ? 'Saving...' : 'Save Draft'}
                            </button>
                            <button
                                type="button"
                                onClick={() => handleSave(true)}
                                disabled={isSubmitting}
                                className="flex-1 px-6 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors font-medium"
                            >
                                {isSubmitting ? 'Publishing...' : 'Publish Post'}
                            </button>
                            <button
                                type="button"
                                onClick={() => router.back()}
                                className="px-6 py-3 bg-gray-200 dark:bg-gray-700 text-gray-900 dark:text-white rounded-lg hover:bg-gray-300 dark:hover:bg-gray-600 transition-colors font-medium"
                            >
                                Cancel
                            </button>
                        </div>
                    </form>
                </div>
            </main>
        </div>
    );
}
