# Noa landing. Build from the repo root (pnpm workspace):
#   docker build -f landing/Dockerfile -t noa-landing .
# NEXT_PUBLIC_* values are baked in at build time.
FROM node:24-slim AS build
RUN corepack enable
WORKDIR /repo
ENV NEXT_TELEMETRY_DISABLED=1 COREPACK_ENABLE_DOWNLOAD_PROMPT=0 NOA_DOCKER_BUILD=true
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY packages packages
COPY landing/package.json landing/
RUN pnpm install --frozen-lockfile --filter "@noa/landing..."
COPY landing landing
# Photos and video come from the CDN; public/ may be empty or absent in a checkout.
RUN mkdir -p landing/public
ARG NEXT_PUBLIC_APP_URL
ARG NEXT_PUBLIC_CDN_URL=https://cdn.saish.xyz
ENV NEXT_PUBLIC_APP_URL=$NEXT_PUBLIC_APP_URL NEXT_PUBLIC_CDN_URL=$NEXT_PUBLIC_CDN_URL
# Assert the standalone server exists before assembling the runtime image.
RUN pnpm --filter @noa/landing build \
  && test -f landing/.next/standalone/landing/server.js

FROM node:24-slim
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PORT=3001 HOSTNAME=0.0.0.0
COPY --from=build --chown=node:node /repo/landing/.next/standalone ./
COPY --from=build --chown=node:node /repo/landing/.next/static ./landing/.next/static
COPY --from=build --chown=node:node /repo/landing/public ./landing/public
USER node
EXPOSE 3001
CMD ["node", "landing/server.js"]
