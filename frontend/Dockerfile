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

# Install curl for HEALTHCHECK
RUN apk add --no-cache curl

WORKDIR /app

# Create non-root user (alpine syntax)
# Using UID 1001 because the base image's 'node' user already occupies UID 1000
RUN addgroup -g 1001 -S appuser && \
    adduser -u 1001 -S -G appuser -s /bin/sh appuser

# Copy built artifacts from the builder stage, owned by appuser
COPY --from=builder --chown=appuser:appuser /build/node_modules ./node_modules
COPY --from=builder --chown=appuser:appuser /build/app.js ./app.js
COPY --from=builder --chown=appuser:appuser /build/views ./views
COPY --from=builder --chown=appuser:appuser /build/package*.json ./

USER appuser

ENV NODE_ENV=production

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:3000/ || exit 1

CMD ["node", "app.js"]