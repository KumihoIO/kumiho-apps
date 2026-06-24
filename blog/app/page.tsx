'use client';

import { useState, useEffect } from 'react';
import Header from '@/components/Header';
import BlogPostCard from '@/components/BlogPostCard';
import { kumihoApi, BlogPost, Space } from '@/lib/kumiho-api';
import Link from 'next/link';
import { useAuth } from '@/context/AuthContext';
import { signOut } from 'firebase/auth';
import { auth } from '@/lib/firebase';

export default function Home() {
    const [posts, setPosts] = useState<BlogPost[]>([]);
    const [spaces, setSpaces] = useState<Space[]>([]);
    const [error, setError] = useState<string | null>(null);
    const [isLoading, setIsLoading] = useState(true);
    const [settings, setSettings] = useState<{
        project_name: string;
        post_item_kind: string;
        pagination_count: number;
        display_type: string;
        display_category_filters: boolean;
    } | null>(null);
    const [projectName, setProjectName] = useState<string>('');
    const [selectedCategory, setSelectedCategory] = useState<string>(''); // Path
    const [currentPage, setCurrentPage] = useState(1);

    // Use AuthContext instead of local state
    const { user, token, isAuthenticated } = useAuth();
    const effectiveUser = isAuthenticated ? user : null;

    // Load initial data (project, categories, settings)
    useEffect(() => {
        const init = async () => {
            try {
                const savedProject = localStorage.getItem('kumiho_blog_project') || 'MyBlog';
                setProjectName(savedProject);
                setSelectedCategory(`/${savedProject}`); // Default to project root

                // Load settings
                try {
                    const fetchedSettings = await kumihoApi.getSettings(savedProject, token || undefined);
                    setSettings(fetchedSettings);
                } catch (e) {
                    console.warn('Failed to load settings, using defaults', e);
                    // Use defaults if settings fail to load
                    setSettings({
                        project_name: savedProject,
                        post_item_kind: 'post',
                        pagination_count: 10,
                        display_type: 'excerpt',
                        display_category_filters: true
                    });
                }

                // Load categories (recursive)
                const fetchedSpaces = await kumihoApi.listSpaces(`/${savedProject}`, true);
                setSpaces(fetchedSpaces);

            } catch (e) {
                console.error('Initialization error:', e);
                // Only sign out on auth errors (401/403)
                if (e instanceof Error && (e.message.includes('401') || e.message.includes('403'))) {
                    if (auth.currentUser) {
                        console.warn('Auth error with active user, attempting sign out...');
                        signOut(auth).catch(err => console.error('Sign out failed', err));
                    }
                } else {
                    // For other errors (like 500), just show the error
                    setError(e instanceof Error ? e.message : 'Failed to initialize');
                }
            } finally {
                setIsLoading(false);
            }
        };
        init();
    }, [token]); // Add token dependency to reload if auth changes

    // Load posts when category changes
    useEffect(() => {
        const loadPosts = async () => {
            if (!selectedCategory) return;

            setIsLoading(true);
            try {
                // Pass token to see drafts if logged in
                const fetchedPosts = await kumihoApi.listPosts(selectedCategory, token || undefined);
                setPosts(fetchedPosts);
                setCurrentPage(1); // Reset to first page on category change
                setError(null);
            } catch (e) {
                setError(e instanceof Error ? e.message : 'Failed to load posts');
                console.error('Error loading posts:', e);
            } finally {
                setIsLoading(false);
            }
        };

        loadPosts();
    }, [selectedCategory, token]);

    return (
        <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
            <Header />

            <main className="container mx-auto px-4 py-12">
                <div className="flex flex-col md:flex-row gap-8">
                    {/* Sidebar */}
                    {/* Sidebar */}
                    {(!settings || settings.display_category_filters) && (
                        <aside className="w-full md:w-64 flex-shrink-0">
                            <div className="bg-white dark:bg-gray-900 rounded-lg shadow p-6 sticky top-24">
                                <h2 className="text-lg font-bold text-gray-900 dark:text-white mb-4">
                                    Categories
                                </h2>
                                <nav className="space-y-2">
                                    <button
                                        onClick={() => setSelectedCategory(`/${projectName}`)}
                                        className={`w-full text-left px-3 py-2 rounded-md text-sm transition-colors ${selectedCategory === `/${projectName}`
                                            ? 'bg-blue-50 text-blue-700 dark:bg-blue-900/20 dark:text-blue-300 font-medium'
                                            : 'text-gray-600 dark:text-gray-400 hover:bg-gray-50 dark:hover:bg-gray-800'
                                            }`}
                                    >
                                        All Posts
                                    </button>
                                    {spaces.map((space) => (
                                        <button
                                            key={space.path}
                                            onClick={() => setSelectedCategory(space.path)}
                                            className={`w-full text-left px-3 py-2 rounded-md text-sm transition-colors ${selectedCategory === space.path
                                                ? 'bg-blue-50 text-blue-700 dark:bg-blue-900/20 dark:text-blue-300 font-medium'
                                                : 'text-gray-600 dark:text-gray-400 hover:bg-gray-50 dark:hover:bg-gray-800'
                                                }`}
                                        >
                                            {space.name}
                                        </button>
                                    ))}
                                </nav>
                            </div>
                        </aside>
                    )}

                    {/* Main Content */}
                    <div className="flex-1">
                        <div className="flex items-center justify-between mb-8">
                            <div>
                                <h1 className="text-4xl font-bold text-gray-900 dark:text-white">
                                    {selectedCategory === `/${projectName}`
                                        ? 'Latest Posts'
                                        : spaces.find(s => s.path === selectedCategory)?.name || 'Posts'}
                                </h1>
                                {projectName && (
                                    <p className="text-sm text-gray-500 mt-1">
                                        Project: {projectName}
                                    </p>
                                )}
                            </div>
                            {/* Show New Post button only if logged in */}
                            {isAuthenticated && (
                                <Link
                                    href="/admin/new"
                                    className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
                                >
                                    New Post
                                </Link>
                            )}
                        </div>

                        {error && (
                            <div className="bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg p-4 mb-8">
                                <p className="text-red-800 dark:text-red-200">
                                    <strong>Error:</strong> {error}
                                </p>
                            </div>
                        )}

                        {isLoading && (
                            <div className="text-center py-12">
                                <p className="text-gray-500">Loading posts...</p>
                            </div>
                        )}

                        {!isLoading && !error && posts.length === 0 && (
                            <div className="text-center py-12">
                                <p className="text-gray-600 dark:text-gray-400 mb-4">
                                    No blog posts found in this category.
                                </p>
                                {isAuthenticated && (
                                    <Link
                                        href="/admin/new"
                                        className="inline-block px-6 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
                                    >
                                        Create First Post
                                    </Link>
                                )}
                            </div>
                        )}

                        {!isLoading && !error && posts.length > 0 && (
                            <>
                                <div className="grid gap-6">
                                    {posts
                                        .slice(
                                            (currentPage - 1) * (settings?.pagination_count || 10),
                                            currentPage * (settings?.pagination_count || 10)
                                        )
                                        .map((post) => (
                                            <BlogPostCard
                                                key={post.kref}
                                                post={post}
                                                currentUser={effectiveUser}
                                                token={token}
                                                contentDisplay={settings?.display_type || 'excerpt'}
                                                onDelete={() => {
                                                    // Refresh posts after delete
                                                    const loadPosts = async () => {
                                                        const fetchedPosts = await kumihoApi.listPosts(selectedCategory, token || undefined);
                                                        setPosts(fetchedPosts);
                                                    };
                                                    loadPosts();
                                                }}
                                            />
                                        ))}
                                </div>

                                {/* Pagination Controls */}
                                {posts.length > (settings?.pagination_count || 10) && (
                                    <div className="flex justify-center mt-8 gap-2">
                                        <button
                                            onClick={() => setCurrentPage(p => Math.max(1, p - 1))}
                                            disabled={currentPage === 1}
                                            className="px-4 py-2 border rounded-lg disabled:opacity-50 hover:bg-gray-50 dark:hover:bg-gray-800 text-gray-600 dark:text-gray-300"
                                        >
                                            Previous
                                        </button>
                                        <span className="px-4 py-2 text-gray-600 dark:text-gray-300">
                                            Page {currentPage} of {Math.ceil(posts.length / (settings?.pagination_count || 10))}
                                        </span>
                                        <button
                                            onClick={() => setCurrentPage(p => Math.min(Math.ceil(posts.length / (settings?.pagination_count || 10)), p + 1))}
                                            disabled={currentPage === Math.ceil(posts.length / (settings?.pagination_count || 10))}
                                            className="px-4 py-2 border rounded-lg disabled:opacity-50 hover:bg-gray-50 dark:hover:bg-gray-800 text-gray-600 dark:text-gray-300"
                                        >
                                            Next
                                        </button>
                                    </div>
                                )}
                            </>
                        )}
                    </div>
                </div>
            </main>

            <footer className="border-t border-gray-200 dark:border-gray-800 mt-12">
                <div className="container mx-auto px-4 py-6 text-center text-sm text-gray-600 dark:text-gray-400">
                    <p>
                        Demo application showcasing{' '}
                        <a
                            href="https://kumiho.io"
                            target="_blank"
                            rel="noopener noreferrer"
                            className="text-blue-600 dark:text-blue-400 hover:underline"
                        >
                            Kumiho SaaS API
                        </a>
                    </p>
                </div>
            </footer>
        </div>
    );
}
