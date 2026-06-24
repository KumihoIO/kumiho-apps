'use client';

import Link from 'next/link';
import { useState } from 'react';
import { useAuth } from '@/context/AuthContext';
import { kumihoApi, BlogPost } from '@/lib/kumiho-api';
import { useRouter } from 'next/navigation';

interface PostActionsProps {
    post: BlogPost;
}

export default function PostActions({ post }: PostActionsProps) {
    const { user, isAuthenticated } = useAuth();
    const [isDeleting, setIsDeleting] = useState(false);
    const router = useRouter();

    // Show admin buttons if user is logged in.
    const isAuthor = !!user && isAuthenticated;

    if (!isAuthor) return null;

    const handleDelete = async () => {
        if (!confirm('Are you sure you want to delete this post?')) return;

        setIsDeleting(true);
        try {
            // Parse kref to get space path: "Project/Space/item.kind"
            // We need "/Project/Space"
            const krefPath = post.kref.split('://')[1] || post.kref;
            const parts = krefPath.split('/');
            const spacePath = '/' + parts.slice(0, -1).join('/');

            await kumihoApi.deletePost(post.slug, spacePath);
            router.push('/');
            router.refresh();
        } catch (e) {
            alert('Failed to delete post');
            console.error(e);
            setIsDeleting(false);
        }
    };

    return (
        <div className="flex items-center gap-3 mt-6 border-t border-gray-200 dark:border-gray-800 pt-6">
            <Link
                href={`/admin/edit/${post.slug}`}
                className="px-4 py-2 bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300 rounded-lg hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors text-sm font-medium"
            >
                Modify Post
            </Link>
            <button
                onClick={handleDelete}
                disabled={isDeleting}
                className="px-4 py-2 bg-red-50 text-red-600 dark:bg-red-900/20 dark:text-red-400 rounded-lg hover:bg-red-100 dark:hover:bg-red-900/40 transition-colors text-sm font-medium disabled:opacity-50"
            >
                {isDeleting ? 'Deleting...' : 'Delete Post'}
            </button>
        </div>
    );
}
