'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import Header from '@/components/Header';
import { kumihoApi, Project, Space } from '@/lib/kumiho-api';
import MDEditor from '@uiw/react-md-editor';
import { useAuth } from '@/context/AuthContext';

export default function NewPostPage() {
    const router = useRouter();
    const { user, token, loading, isAuthenticated } = useAuth();
    const [isSubmitting, setIsSubmitting] = useState(false);
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

    // Load project and spaces on mount
    useEffect(() => {
        const loadData = async () => {
            const savedProject = localStorage.getItem('kumiho_blog_project');
            if (!savedProject) {
                setError('Please configure a project in Settings first.');
                return;
            }
            setSelectedProject(savedProject);

            try {
                const fetchedSpaces = await kumihoApi.listSpaces(`/${savedProject}`, true);
                setSpaces(fetchedSpaces);
            } catch (err) {
                console.error('Failed to load spaces:', err);
                setError('Failed to load categories.');
            }
        };
        loadData();
    }, []);

    const handleSave = async (publish: boolean) => {
        setIsSubmitting(true);
        setError(null);

        try {
            const tags = formData.tags
                .split(',')
                .map(tag => tag.trim())
                .filter(tag => tag.length > 0);

            // Construct space path
            // selectedSpace now holds the full path (e.g. /MyBlog/posts/tech)
            const spacePath = selectedSpace || `/${selectedProject}`;

            await kumihoApi.createPost({
                title: formData.title,
                author: user?.email || '', // Backend handles this now, but we can send it
                content: formData.content,
                tags,
                space_path: spacePath,
            }, publish, token || undefined);

            router.push('/');
        } catch (err) {
            setError(err instanceof Error ? err.message : 'Failed to create post');
            setIsSubmitting(false);
        }
    };

    const handleSubmit = (e: React.FormEvent) => {
        e.preventDefault();
        handleSave(false); // Default to draft on enter? Or prevent default submit?
    };

    return (
        <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
            <Header />

            <main className="container mx-auto px-4 py-12">
                <div className="max-w-6xl mx-auto">
                    <h1 className="text-4xl font-bold text-gray-900 dark:text-white mb-8">
                        Create New Post
                    </h1>

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
                                    <p className="mt-1 text-xs text-gray-500 dark:text-gray-400">
                                        Path: {selectedProject ? `/${selectedProject}` : ''}{selectedSpace ? `/${selectedSpace}` : ''}
                                    </p>
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
                                onClick={() => router.push('/')}
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
