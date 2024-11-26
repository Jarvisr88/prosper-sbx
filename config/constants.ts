export const APP_CONFIG = {
  api: {
    baseUrl: process.env.NEXT_PUBLIC_API_URL || "http://localhost:3003",
    timeout: 30000,
    retryCount: 3,
  },
  auth: {
    sessionMaxAge: 24 * 60 * 60, // 24 hours
    refreshTokenMaxAge: 30 * 24 * 60 * 60, // 30 days
  },
  security: {
    rateLimit: {
      windowMs: 15 * 60 * 1000, // 15 minutes
      max: 100, // limit each IP to 100 requests per windowMs
    },
  },
};
