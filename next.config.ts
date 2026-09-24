import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  experimental: {
    // Allow photo uploads through Server Actions (default is 1 MB): a food photo (≤ 8 MB)
    // or up to 5 transaction photos (≤ 5 MB each; clients compress first).
    serverActions: {
      bodySizeLimit: "26mb",
    },
  },
};

export default nextConfig;
