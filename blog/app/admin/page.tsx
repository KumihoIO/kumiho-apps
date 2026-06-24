'use client';

import Header from '@/components/Header';
import Link from 'next/link';
import { useAuth } from '@/context/AuthContext';
import { useRouter } from 'next/navigation';
import { useEffect } from 'react';

export default function AdminPage() {
    const { loading, isAuthenticated } = useAuth();
    const router = useRouter();

    useEffect(() => {
        if (!loading && !isAuthenticated) {
            router.push('/');
        }
    }, [isAuthenticated, loading, router]);

    if (loading) {
        return (
            <div className="min-h-screen bg-gray-50 dark:bg-gray-950 flex items-center justify-center">
                <p className="text-gray-500">Loading...</p>
            </div>
        );
    }
    return (
        <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
            <Header />

            <main className="container mx-auto px-4 py-12">
                <div className="max-w-4xl mx-auto">
                    <h1 className="text-4xl font-bold text-gray-900 dark:text-white mb-8">
                        Admin Dashboard
                    </h1>

                    <div className="grid gap-6 md:grid-cols-2">
                        <Link
                            href="/admin/new"
                            className="block p-8 bg-white dark:bg-gray-900 rounded-lg shadow-lg hover:shadow-xl transition-shadow border-2 border-transparent hover:border-blue-500"
                        >
                            <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-2">
                                Create New Post
                            </h2>
                            <p className="text-gray-600 dark:text-gray-400">
                                Write and publish a new blog post
                            </p>
                        </Link>

                        <Link
                            href="/admin/categories"
                            className="block p-8 bg-white dark:bg-gray-900 rounded-lg shadow-lg hover:shadow-xl transition-shadow border-2 border-transparent hover:border-blue-500"
                        >
                            <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-2">
                                Manage Categories
                            </h2>
                            <p className="text-gray-600 dark:text-gray-400">
                                Organize posts into categories
                            </p>
                        </Link>

                        <Link
                            href="/admin/settings"
                            className="block p-8 bg-white dark:bg-gray-900 rounded-lg shadow-lg hover:shadow-xl transition-shadow border-2 border-transparent hover:border-blue-500"
                        >
                            <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-2">
                                Settings
                            </h2>
                            <p className="text-gray-600 dark:text-gray-400">
                                Configure project and item kinds
                            </p>
                        </Link>

                        <Link
                            href="/"
                            className="block p-8 bg-white dark:bg-gray-900 rounded-lg shadow-lg hover:shadow-xl transition-shadow border-2 border-transparent hover:border-blue-500"
                        >
                            <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-2">
                                View All Posts
                            </h2>
                            <p className="text-gray-600 dark:text-gray-400">
                                Browse and manage existing posts
                            </p>
                        </Link>
                    </div>

                    <div className="mt-12 bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg p-6">
                        <h3 className="text-lg font-semibold text-blue-900 dark:text-blue-100 mb-2">
                            About This Demo
                        </h3>
                        <p className="text-blue-800 dark:text-blue-200 mb-4">
                            This blog application demonstrates the Kumiho SaaS API with a hierarchical data structure:
                            <br />
                            <code className="bg-blue-100 dark:bg-blue-900 px-2 py-1 rounded mt-2 inline-block">
                                Project: MyBlog -&gt; Space: posts -&gt; Sub-space: tech-news/Kumiho
                            </code>
                        </p>
                        <div className="text-sm text-blue-700 dark:text-blue-300 space-y-1">
                            <div>└─ Item: [Blog Post Slug]</div>
                            <div className="ml-4">└─ Revision: r1</div>
                            <div className="ml-8">└─ Metadata: Title, Author, Date, Content</div>
                        </div>
                    </div>
                </div>
            </main>
        </div>
    );
}

