module.exports = {
  apps: [
    {
      name: "kords-lab",
      script: ".output/server/index.mjs",
      cwd: "/www/wwwroot/github/up-kords",
      instances: 1,
      exec_mode: "cluster",
      env: {
        NODE_ENV: "production",
        PORT: 4500, // ← Match your Nginx upstream port
        HOST: "::1", // ← IPv6 localhost (matches your Nginx config)
        NITRO_PORT: 4500,
        NITRO_HOST: "::1",
      },
    },
  ],
};
