# Noa web. Build from the repo root (pnpm workspace):
#   docker build -f web/Dockerfile -t noa-web .
# NEXT_PUBLIC_* values are baked in at build time.
FROM node:24-slim AS build
RUN corepack enable
WORKDIR /repo
ENV NEXT_TELEMETRY_DISABLED=1 COREPACK_ENABLE_DOWNLOAD_PROMPT=0
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY packages packages
COPY web/package.json web/
RUN pnpm install --frozen-lockfile --filter "@noa/web..."
COPY web web
ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL
# Use webpack for reliable standalone tracing in the CI container build.
RUN pnpm --filter @noa/web build --webpack \
  && node -e 'const fs=require("node:fs");const {config}=JSON.parse(fs.readFileSync("web/.next/required-server-files.json","utf8"));console.log("Standalone config",{output:config.output,root:config.outputFileTracingRoot,distDir:config.distDir});console.log("Build files",fs.readdirSync("web/.next"));' \
  && test -f web/.next/standalone/web/server.js

FROM node:24-slim
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PORT=3000 HOSTNAME=0.0.0.0
COPY --from=build --chown=node:node /repo/web/.next/standalone ./
COPY --from=build --chown=node:node /repo/web/.next/static ./web/.next/static
COPY --from=build --chown=node:node /repo/web/public ./web/public
USER node
EXPOSE 3000
CMD ["node", "web/server.js"]
