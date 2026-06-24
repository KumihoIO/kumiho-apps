import Header from '@/components/Header';
import PostActions from '@/components/PostActions';
import { kumihoApi } from '@/lib/kumiho-api';
import { notFound } from 'next/navigation';
import ReactMarkdown from 'react-markdown';
import Link from 'next/link';

interface PageProps {
    params: Promise<{ slug: string }>;
}

export default async function PostPage({ params }: PageProps) {
    const { slug } = await params;

    let post = null;
    let error = null;

    try {
        post = await kumihoApi.getPost(slug);
    } catch (e) {
        error = e instanceof Error ? e.message : 'Failed to load post';
        console.error('Error loading post:', e);
    }

    if (!post && !error) {
        notFound();
    }

    const formattedDate = post ? new Date(post.date).toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'long',
        day: 'numeric',
    }) : '';

    return (
        <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
            <Header />

            <main className="container mx-auto px-4 py-12">
                <div className="max-w-3xl mx-auto">
                    <Link
                        href="/"
                        className="inline-flex items-center text-blue-600 dark:text-blue-400 hover:underline mb-8"
                    >
                        ← Back to all posts
                    </Link>

                    {error && (
                        <div className="bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg p-4">
                            <p className="text-red-800 dark:text-red-200">
                                <strong>Error:</strong> {error}
                            </p>
                        </div>
                    )}

                    {post && (
                        <article className="bg-white dark:bg-gray-900 rounded-lg shadow-lg p-8">
                            <header className="mb-8 border-b border-gray-200 dark:border-gray-800 pb-6">
                                <h1 className="text-4xl font-bold text-gray-900 dark:text-white mb-4">
                                    {post.title}
                                </h1>

                                <div className="flex items-center gap-4 text-sm text-gray-600 dark:text-gray-400 mb-4">
                                    <span>By <strong>{post.author}</strong></span>
                                    <span>•</span>
                                    <time dateTime={post.date}>{formattedDate}</time>
                                    <span>•</span>
                                    <span>Revision: {post.revision}</span>
                                    {post.published && (
                                        <>
                                            <span>•</span>
                                            <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200">
                                                Published
                                            </span>
                                        </>
                                    )}
                                </div>

                                {post.tags.length > 0 && (
                                    <div className="flex flex-wrap gap-2">
                                        {post.tags.map((tag) => (
                                            <span
                                                key={tag}
                                                className="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200"
                                            >
                                                {tag}
                                            </span>
                                        ))}
                                    </div>
                                )}
                            </header>

                            <div className="prose prose-lg dark:prose-invert max-w-none">
                                <ReactMarkdown>{post.content || ''}</ReactMarkdown>
                            </div>

                            <PostActions post={post} />

                            <footer className="mt-8 pt-6 border-t border-gray-200 dark:border-gray-800">
                                <p className="text-sm text-gray-600 dark:text-gray-400">
                                    KREF: <code className="text-xs bg-gray-100 dark:bg-gray-800 px-2 py-1 rounded">{post.kref}</code>
                                </p>
                            </footer>
                        </article>
                    )}
                </div>
            </main>
        </div>
    );
}
