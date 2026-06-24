import Link from 'next/link';
import { BlogPost, kumihoApi } from '@/lib/kumiho-api';
import { useState } from 'react';
import { User } from 'firebase/auth';
import ReactMarkdown from 'react-markdown';

interface BlogPostCardProps {
    post: BlogPost;
    currentUser?: User | null;
    token?: string | null;
    onDelete?: () => void;
    contentDisplay?: string;
}

export default function BlogPostCard({ post, currentUser, token, onDelete, contentDisplay = 'excerpt' }: BlogPostCardProps) {
    const formattedDate = new Date(post.date).toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'long',
        day: 'numeric',
    });

    const [isDeleting, setIsDeleting] = useState(false);

    // Show admin buttons if user is logged in.
    // Ideally we check if user is author or admin.
    // For now, if logged in, we show buttons.
    const isAuthor = !!currentUser && !currentUser.isAnonymous;

    console.log(`[BlogPostCard] slug=${post.slug} author=${post.author} currentUser=${currentUser?.email} isAuthor=${isAuthor}`);

    const handleDelete = async () => {
        if (!confirm('Are you sure you want to delete this post?')) return;

        setIsDeleting(true);
        try {
            // We need to pass the space path for deletion if possible,
            // but deletePost in API might need updating or we rely on slug.
            // Actually our deletePost takes slug and spacePath.
            // We can extract spacePath from kref or just pass the current context if known.
            // But here we don't know the exact space path easily without parsing kref.

            // Let's parse kref to get space path: "Project/Space/item.kind"
            // We need "/Project/Space"
            const krefPath = post.kref.split('://')[1] || post.kref; // remove scheme if present
            const parts = krefPath.split('/');
            // parts: [Project, Space..., item.kind]
            const spacePath = '/' + parts.slice(0, -1).join('/');

            await kumihoApi.deletePost(post.slug, spacePath, token || undefined);
            if (onDelete) onDelete();
        } catch (e) {
            alert('Failed to delete post');
            console.error(e);
            setIsDeleting(false);
        }
    };

    return (
        <article className="bg-white dark:bg-gray-900 rounded-lg shadow-md overflow-hidden hover:shadow-lg transition-shadow border border-gray-100 dark:border-gray-800">
            <div className="p-6">
                <div className="flex items-center justify-between mb-4">
                    <div className="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400">
                        <span>{formattedDate}</span>
                        <span>•</span>
                        <span>{post.author}</span>
                    </div>
                    {post.published ? (
                        <span className="px-2 py-1 text-xs font-medium bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200 rounded-full">
                            Published
                        </span>
                    ) : (
                        <span className="px-2 py-1 text-xs font-medium bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200 rounded-full">
                            Draft
                        </span>
                    )}
                </div>

                <Link href={`/posts/${post.slug}`}>
                    <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-3 hover:text-blue-600 dark:hover:text-blue-400 transition-colors">
                        {post.title}
                    </h2>
                </Link>

                {contentDisplay !== 'title' && (
                    <div className={`text-gray-600 dark:text-gray-300 mb-4 ${contentDisplay === 'excerpt' ? 'line-clamp-3' : 'prose dark:prose-invert max-w-none'}`}>
                        {contentDisplay === 'full' ? (
                            <ReactMarkdown>{post.content || ''}</ReactMarkdown>
                        ) : (
                            (post.content || '').replace(/[#*`]/g, '')
                        )}
                    </div>
                )}

                <div className="flex items-center justify-between mt-4">
                    <div className="flex gap-2">
                        {post.tags.map((tag) => (
                            <span
                                key={tag}
                                className="px-2 py-1 text-xs font-medium bg-gray-100 text-gray-600 dark:bg-gray-800 dark:text-gray-300 rounded"
                            >
                                {tag}
                            </span>
                        ))}
                    </div>

                    <div className="flex items-center gap-3">
                        <Link
                            href={`/posts/${post.slug}`}
                            className="text-blue-600 dark:text-blue-400 hover:underline text-sm font-medium"
                        >
                            Read more →
                        </Link>

                        {isAuthor && (
                            <>
                                <Link
                                    href={`/admin/edit/${post.slug}`}
                                    className="text-gray-600 dark:text-gray-400 hover:text-blue-600 dark:hover:text-blue-400 text-sm font-medium"
                                >
                                    Modify
                                </Link>
                                <button
                                    onClick={handleDelete}
                                    disabled={isDeleting}
                                    className="text-red-600 dark:text-red-400 hover:text-red-800 dark:hover:text-red-300 text-sm font-medium disabled:opacity-50"
                                >
                                    {isDeleting ? 'Deleting...' : 'Delete'}
                                </button>
                            </>
                        )}
                    </div>
                </div>
            </div>
        </article>
    );
}
