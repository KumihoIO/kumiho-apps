import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  reactStrictMode: true,
  // This repo contains multiple lockfiles; set an explicit tracing root
  // so Next.js doesn't have to guess the workspace root.
  outputFileTracingRoot: process.cwd(),
};

export default nextConfig;
