'use client';

import { useState, useEffect } from 'react';
import Header from '@/components/Header';
import { kumihoApi, Project, getProjectName } from '@/lib/kumiho-api';
import { useAuth } from '@/context/AuthContext';
import { useRouter } from 'next/navigation';

export default function SettingsPage() {
    const { user, token, loading, isAuthenticated } = useAuth();
    const router = useRouter();
    // Use project name from env var or config
    const selectedProject = getProjectName();

    const [itemKind, setItemKind] = useState<string>('post');
    const [paginationCount, setPaginationCount] = useState<number>(10);
    const [displayType, setDisplayType] = useState<string>('title_only');
    const [displayCategoryFilters, setDisplayCategoryFilters] = useState<boolean>(true);

    const [isLoading, setIsLoading] = useState(true);
    const [isSaving, setIsSaving] = useState(false);
    const [message, setMessage] = useState<{ type: 'success' | 'error', text: string } | null>(null);

    useEffect(() => {
        if (!loading && !isAuthenticated) {
            router.push('/');
        }
    }, [isAuthenticated, loading, router]);

    useEffect(() => {
        if (isAuthenticated && user && selectedProject) {
            loadSettings(selectedProject);
        }
    }, [isAuthenticated, user, token, selectedProject]);

    const loadSettings = async (projectName: string) => {
        try {
            const settings = await kumihoApi.getSettings(projectName, token || undefined);
            setItemKind(settings.post_item_kind);
            setPaginationCount(settings.pagination_count);
            setDisplayType(settings.display_type);
            setDisplayCategoryFilters(settings.display_category_filters);
            setIsLoading(false);
        } catch (err) {
            console.error('Failed to load settings:', err);
            // Default values if failed or not found
            setItemKind('post');
            setPaginationCount(10);
            setDisplayType('title_only');
            setDisplayCategoryFilters(true);
            setIsLoading(false);
        }
    };

    const handleSave = async (e: React.FormEvent) => {
        e.preventDefault();
        setIsSaving(true);
        setMessage(null);

        try {
            await kumihoApi.saveSettings(
                selectedProject,
                {
                    post_item_kind: itemKind,
                    pagination_count: paginationCount,
                    display_type: displayType,
                    display_category_filters: displayCategoryFilters
                },
                token || undefined
            );
            setMessage({ type: 'success', text: 'Settings saved successfully' });
        } catch (err) {
            console.error('Failed to save settings:', err);
            setMessage({ type: 'error', text: 'Failed to save settings' });
        } finally {
            setIsSaving(false);
        }
    };

    return (
        <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
            <Header />

            <main className="container mx-auto px-4 py-12">
                <div className="max-w-2xl mx-auto">
                    <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-8">
                        Blog Settings
                    </h1>

                    {message && (
                        <div className={`p-4 mb-6 rounded-lg ${message.type === 'success'
                            ? 'bg-green-50 text-green-800 border border-green-200'
                            : 'bg-red-50 text-red-800 border border-red-200'
                            }`}>
                            {message.text}
                        </div>
                    )}

                    <form onSubmit={handleSave} className="bg-white dark:bg-gray-900 rounded-lg shadow-lg p-8 space-y-6">
                        <div>
                            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                                Active Project
                            </label>
                            <div className="w-full px-4 py-2 border border-gray-200 dark:border-gray-700 rounded-lg bg-gray-50 dark:bg-gray-800 text-gray-900 dark:text-white">
                                {selectedProject}
                            </div>
                            <p className="mt-1 text-sm text-gray-500">
                                The project where your blog posts will be stored (configured via environment variable).
                            </p>
                        </div>

                        <div>
                            <label htmlFor="itemKind" className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                                Post Item Kind
                            </label>
                            <input
                                type="text"
                                id="itemKind"
                                value={itemKind}
                                onChange={(e) => setItemKind(e.target.value)}
                                className="w-full px-4 py-2 border border-gray-300 dark:border-gray-700 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent bg-white dark:bg-gray-800 text-gray-900 dark:text-white"
                                placeholder="e.g. post, article"
                            />
                            <p className="mt-1 text-sm text-gray-500">
                                The Kumiho item kind used for blog posts (default: post).
                            </p>
                        </div>

                        <div>
                            <label htmlFor="paginationCount" className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                                Posts per Page
                            </label>
                            <input
                                type="number"
                                id="paginationCount"
                                value={paginationCount}
                                onChange={(e) => setPaginationCount(parseInt(e.target.value))}
                                min="1"
                                max="100"
                                className="w-full px-4 py-2 border border-gray-300 dark:border-gray-700 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent bg-white dark:bg-gray-800 text-gray-900 dark:text-white"
                            />
                            <p className="mt-1 text-sm text-gray-500">
                                Number of posts to display per page.
                            </p>
                        </div>

                        <div>
                            <label htmlFor="displayType" className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                                Display Type
                            </label>
                            <select
                                id="displayType"
                                value={displayType}
                                onChange={(e) => setDisplayType(e.target.value)}
                                className="w-full px-4 py-2 border border-gray-300 dark:border-gray-700 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent bg-white dark:bg-gray-800 text-gray-900 dark:text-white"
                            >
                                <option value="title_only">Title Only</option>
                                <option value="excerpt">Excerpt</option>
                                <option value="full">Full Post</option>
                            </select>
                            <p className="mt-1 text-sm text-gray-500">
                                How posts should be displayed in the list view.
                            </p>
                        </div>

                        <div className="flex items-center justify-between">
                            <div>
                                <label htmlFor="displayCategoryFilters" className="block text-sm font-medium text-gray-700 dark:text-gray-300">
                                    Display Category Filters
                                </label>
                                <p className="mt-1 text-sm text-gray-500">
                                    Show category filter buttons on the blog home page.
                                </p>
                            </div>
                            <div className="relative inline-block w-12 mr-2 align-middle select-none transition duration-200 ease-in">
                                <input
                                    type="checkbox"
                                    name="displayCategoryFilters"
                                    id="displayCategoryFilters"
                                    checked={displayCategoryFilters}
                                    onChange={(e) => setDisplayCategoryFilters(e.target.checked)}
                                    className="toggle-checkbox absolute block w-6 h-6 rounded-full bg-white border-4 appearance-none cursor-pointer"
                                    style={{ right: displayCategoryFilters ? '0' : 'auto', left: displayCategoryFilters ? 'auto' : '0', borderColor: displayCategoryFilters ? '#2563EB' : '#D1D5DB' }}
                                />
                                <label
                                    htmlFor="displayCategoryFilters"
                                    className={`toggle-label block overflow-hidden h-6 rounded-full cursor-pointer ${displayCategoryFilters ? 'bg-blue-600' : 'bg-gray-300'}`}
                                ></label>
                            </div>
                        </div>

                        <div className="pt-4">
                            <button
                                type="submit"
                                disabled={isSaving}
                                className="w-full px-6 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors font-medium"
                            >
                                {isSaving ? 'Saving...' : 'Save Settings'}
                            </button>
                        </div>
                    </form>
                </div>
            </main>
        </div>
    );
}
