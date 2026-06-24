'use client';

import { useState, useEffect } from 'react';
import Header from '@/components/Header';
import { kumihoApi, Space } from '@/lib/kumiho-api';

export default function CategoriesPage() {
    const [spaces, setSpaces] = useState<Space[]>([]);
    const [projectName, setProjectName] = useState<string>('');
    const [isLoading, setIsLoading] = useState(true);
    const [newCategoryName, setNewCategoryName] = useState('');
    const [parentCategory, setParentCategory] = useState('');
    const [isCreating, setIsCreating] = useState(false);
    const [message, setMessage] = useState<{ type: 'success' | 'error', text: string } | null>(null);

    useEffect(() => {
        const savedProject = localStorage.getItem('kumiho_blog_project');
        if (savedProject) {
            setProjectName(savedProject);
            loadSpaces(savedProject);
        } else {
            setIsLoading(false);
            setMessage({ type: 'error', text: 'Please select a project in Settings first.' });
        }
    }, []);

    const loadSpaces = async (project: string) => {
        try {
            // Fetch all spaces recursively? Or just flat list for now?
            // The API listSpaces takes a parent path.
            // For MVP, let's fetch top level and maybe one level deep if we can, 
            // but for flat list selection we might need a recursive fetch or just let user type path.
            // Let's stick to listing spaces under the project root for now,
            // and maybe if we select a parent, we list its children?
            // Actually, let's just list all spaces under project root for simplicity of the UI
            // and assume flat structure for MVP or just 1 level deep.
            // Wait, user wants nested.
            // Let's fetch root spaces first.
            // Fetch all spaces recursively
            const rootSpaces = await kumihoApi.listSpaces(`/${project}`, true);
            setSpaces(rootSpaces);
            setIsLoading(false);
        } catch (err) {
            console.error('Failed to load spaces:', err);
            setMessage({ type: 'error', text: 'Failed to load categories' });
            setIsLoading(false);
        }
    };

    const handleCreate = async (e: React.FormEvent) => {
        e.preventDefault();
        setIsCreating(true);
        setMessage(null);

        try {
            const parentPath = parentCategory ? parentCategory : `/${projectName}`;
            await kumihoApi.createSpace(newCategoryName, parentPath);
            setMessage({ type: 'success', text: 'Category created successfully' });
            setNewCategoryName('');
            loadSpaces(projectName); // Reload list
        } catch (err) {
            console.error('Failed to create category:', err);
            setMessage({ type: 'error', text: 'Failed to create category' });
        } finally {
            setIsCreating(false);
        }
    };

    if (!projectName) {
        return (
            <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
                <Header />
                <main className="container mx-auto px-4 py-12">
                    <div className="text-center">
                        <h1 className="text-2xl font-bold text-gray-900 dark:text-white mb-4">
                            Configuration Required
                        </h1>
                        <p className="text-gray-600 dark:text-gray-400 mb-8">
                            Please configure the active project in Settings first.
                        </p>
                        <a href="/admin/settings" className="px-6 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700">
                            Go to Settings
                        </a>
                    </div>
                </main>
            </div>
        );
    }

    return (
        <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
            <Header />

            <main className="container mx-auto px-4 py-12">
                <div className="max-w-4xl mx-auto">
                    <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-8">
                        Manage Categories
                    </h1>

                    <div className="grid gap-8 md:grid-cols-2">
                        {/* Create New Category */}
                        <div className="bg-white dark:bg-gray-900 rounded-lg shadow-lg p-6">
                            <h2 className="text-xl font-bold text-gray-900 dark:text-white mb-6">
                                Add New Category
                            </h2>

                            {message && (
                                <div className={`p-3 mb-4 rounded text-sm ${message.type === 'success'
                                    ? 'bg-green-50 text-green-800'
                                    : 'bg-red-50 text-red-800'
                                    }`}>
                                    {message.text}
                                </div>
                            )}

                            <form onSubmit={handleCreate} className="space-y-4">
                                <div>
                                    <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                                        Name
                                    </label>
                                    <input
                                        type="text"
                                        required
                                        value={newCategoryName}
                                        onChange={(e) => setNewCategoryName(e.target.value)}
                                        className="w-full px-4 py-2 border border-gray-300 dark:border-gray-700 rounded-lg focus:ring-2 focus:ring-blue-500 bg-white dark:bg-gray-800"
                                        placeholder="e.g. Tech News"
                                    />
                                </div>

                                <div>
                                    <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                                        Parent Category
                                    </label>
                                    <select
                                        value={parentCategory}
                                        onChange={(e) => setParentCategory(e.target.value)}
                                        className="w-full px-4 py-2 border border-gray-300 dark:border-gray-700 rounded-lg focus:ring-2 focus:ring-blue-500 bg-white dark:bg-gray-800"
                                    >
                                        <option value="">None (Root Level)</option>
                                        {spaces.map(space => (
                                            <option key={space.path} value={space.path}>
                                                {space.name}
                                            </option>
                                        ))}
                                    </select>
                                </div>

                                <button
                                    type="submit"
                                    disabled={isCreating || !newCategoryName}
                                    className="w-full px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:bg-gray-400"
                                >
                                    {isCreating ? 'Creating...' : 'Create Category'}
                                </button>
                            </form>
                        </div>

                        {/* List Categories */}
                        <div className="bg-white dark:bg-gray-900 rounded-lg shadow-lg p-6">
                            <h2 className="text-xl font-bold text-gray-900 dark:text-white mb-6">
                                Existing Categories
                            </h2>

                            {isLoading ? (
                                <p className="text-gray-500">Loading...</p>
                            ) : spaces.length === 0 ? (
                                <p className="text-gray-500">No categories found.</p>
                            ) : (
                                <ul className="space-y-2">
                                    {spaces.map(space => (
                                        <li key={space.path} className="p-3 bg-gray-50 dark:bg-gray-800 rounded border border-gray-200 dark:border-gray-700 flex justify-between items-center">
                                            <span className="font-medium text-gray-900 dark:text-white">
                                                {space.name}
                                            </span>
                                            <span className="text-xs text-gray-500 font-mono">
                                                {space.path}
                                            </span>
                                        </li>
                                    ))}
                                </ul>
                            )}
                        </div>
                    </div>
                </div>
            </main>
        </div>
    );
}
