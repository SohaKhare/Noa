# Noa web. Build from the repo root (pnpm workspace):
#   docker build -f web/Dockerfile -t noa-web .
# NEXT_PUBLIC_* values are baked in at build time.
FROM node:24-slim AS build
RUN corepack enable
WORKDIR /repo
ENV NEXT_TELEMETRY_DISABLED=1 COREPACK_ENABLE_DOWNLOAD_PROMPT=0 NEXT_OUTPUT=standalone
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY packages packages
COPY web/package.json web/
RUN pnpm install --frozen-lockfile --filter "@noa/web..."
COPY web web
ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL
RUN pnpm --filter @noa/web build

FROM node:24-slim
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PORT=3000 HOSTNAME=0.0.0.0
COPY --from=build --chown=node:node /repo/web/.next/standalone ./
COPY --from=build --chown=node:node /repo/web/.next/static ./web/.next/static
USER node
EXPOSE 3000
CMD ["node", "web/server.js"]
