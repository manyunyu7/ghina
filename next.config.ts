import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  experimental: {
    // Allow food-photo uploads through Server Actions (default is 1 MB).
    serverActions: {
      bodySizeLimit: "8mb",
    },
  },
};

export default nextConfig;
