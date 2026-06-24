'use client';

import Link from 'next/link';
import { useState } from 'react';
import { useAuth } from '@/context/AuthContext';
import { signOut } from 'firebase/auth';
import { auth } from '@/lib/firebase';
import LoginModal from './LoginModal';

export default function Header() {
    const { user, loading, isAuthenticated } = useAuth();
    const [isLoginOpen, setIsLoginOpen] = useState(false);

    const handleLogout = async () => {
        try {
            await signOut(auth);
        } catch (error) {
            console.error('Failed to logout', error);
        }
    };

    return (
        <header className="border-b border-gray-200 dark:border-gray-800">
            <div className="container mx-auto px-4 py-6">
                <div className="flex items-center justify-between">
                    <Link href="/" className="text-2xl font-bold text-gray-900 dark:text-white hover:text-blue-600 dark:hover:text-blue-400 transition-colors">
                        MyBlog
                    </Link>
                    <nav className="flex gap-6 items-center">
                        <Link href="/" className="text-gray-600 dark:text-gray-300 hover:text-gray-900 dark:hover:text-white transition-colors">
                            Home
                        </Link>

                        {!loading && isAuthenticated && (
                            <Link href="/admin" className="text-gray-600 dark:text-gray-300 hover:text-gray-900 dark:hover:text-white transition-colors">
                                Admin
                            </Link>
                        )}

                        {!loading && (
                            isAuthenticated ? (
                                <button
                                    onClick={handleLogout}
                                    className="text-gray-600 dark:text-gray-300 hover:text-gray-900 dark:hover:text-white transition-colors"
                                >
                                    Logout
                                </button>
                            ) : (
                                <button
                                    onClick={() => setIsLoginOpen(true)}
                                    className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors text-sm"
                                >
                                    Login
                                </button>
                            )
                        )}
                    </nav>
                </div>
                <p className="mt-2 text-sm text-gray-500 dark:text-gray-400">
                    Powered by <span className="font-semibold text-blue-600 dark:text-blue-400">Kumiho SaaS API</span>
                </p>
            </div>
            <LoginModal isOpen={isLoginOpen} onClose={() => setIsLoginOpen(false)} />
        </header>
    );
}
