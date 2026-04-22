# ---------- Stage 1: builder ----------
FROM node:20-alpine AS builder

WORKDIR /build

# Install dependencies (including dev deps if you have a build step)
COPY package*.json ./
RUN npm ci

COPY . .

# If you have a build step (e.g. webpack, tsc), run it here:
# RUN npm run build

# Prune dev dependencies for the runtime stage
RUN npm prune --omit=dev

# ---------- Stage 2: runtime ----------
FROM node:20-alpine AS runtime

# wget is already in alpine-base for healthchecks; if not, install curl
RUN apk add --no-cache curl

WORKDIR /app

# node:alpine ships a "node" user (uid 1000) — use it
COPY --from=builder --chown=node:node /build/node_modules ./node_modules
COPY --from=builder --chown=node:node /build/app.js ./app.js
COPY --from=builder --chown=node:node /build/views ./views
COPY --from=builder --chown=node:node /build/package*.json ./

USER node

ENV NODE_ENV=production

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:3000/ || exit 1

CMD ["node", "app.js"]