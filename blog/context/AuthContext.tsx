'use client';

import React, { createContext, useContext, useEffect, useState } from 'react';
import { User, onIdTokenChanged, getIdToken } from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { configureKumiho } from '@/lib/kumiho-api';

interface BootstrapData {
    tenant_id: string;
    project_names: string[];
    anonymous_allowed: boolean;
}

interface AuthContextType {
    user: User | null;
    token: string | null;
    loading: boolean;
    isAuthenticated: boolean;
    isAnonymous: boolean;
    bootstrapData: BootstrapData | null;
}

const AuthContext = createContext<AuthContextType>({
    user: null,
    token: null,
    loading: true,
    isAuthenticated: false,
    isAnonymous: true,
    bootstrapData: null,
});

export const AuthProvider = ({ children }: { children: React.ReactNode }) => {
    const [user, setUser] = useState<User | null>(null);
    const [token, setToken] = useState<string | null>(null);
    const [loading, setLoading] = useState(true);
    const [isAuthenticated, setIsAuthenticated] = useState(false);
    const [isAnonymous, setIsAnonymous] = useState(true);
    const [bootstrapData, setBootstrapData] = useState<BootstrapData | null>(null);

    useEffect(() => {
        const init = async () => {
            try {
                // 1. Bootstrap Session
                const response = await fetch('/api/auth/session/bootstrap');
                if (response.ok) {
                    const data: BootstrapData = await response.json();
                    setBootstrapData(data);
                    configureKumiho(data.tenant_id, data.project_names);
                } else {
                    console.error('Bootstrap failed:', response.statusText);
                }
            } catch (e) {
                console.error('Bootstrap error:', e);
            }

            // 2. Initialize Firebase Auth
            const unsubscribe = onIdTokenChanged(auth, async (user) => {
                if (user) {
                    // User is signed in (either anonymous or real)
                    try {
                        const token = await getIdToken(user);

                        // We don't need to verify against backend for existence anymore
                        // because we support anonymous users.
                        // Just set the user and token.
                        setUser(user);
                        setToken(token);
                        const anonymous = !!user.isAnonymous;
                        setIsAnonymous(anonymous);
                        setIsAuthenticated(!anonymous);

                    } catch (e) {
                        console.error('Failed to get token:', e);
                        // Don't sign out here, just let it retry or stay in current state
                    }
                } else {
                    // No user - sign in anonymously
                    setUser(null);
                    setToken(null);
                    setIsAuthenticated(false);
                    setIsAnonymous(true);
                    try {
                        // Import dynamically to avoid SSR issues if any
                        const { signInAnonymously } = await import('firebase/auth');
                        await signInAnonymously(auth);
                        // The onIdTokenChanged will fire again with the new anonymous user
                    } catch (e) {
                        console.error('Anonymous sign-in failed:', e);
                    }
                }
                setLoading(false);
            });

            return () => unsubscribe();
        };

        init();
    }, []);

    return (
        <AuthContext.Provider value={{ user, token, loading, isAuthenticated, isAnonymous, bootstrapData }}>
            {children}
        </AuthContext.Provider>
    );
};

export const useAuth = () => useContext(AuthContext);
