FROM node:24.16.0-alpine@sha256:21f403ab171f2dc89bad4dd69d7721bfd15f084ccb46cdd225f31f2bc59b5c9a AS runtime
RUN apk add --no-cache jemalloc python3 py3-pip uv
ENV LD_PRELOAD=/usr/lib/libjemalloc.so.2
WORKDIR /app
RUN chown node:node /app

FROM runtime AS build
COPY --chown=node:node . .
USER node
RUN touch .env && mkdir -p client/public/images logs uploads skill data && chmod 1777 data
RUN npm ci --no-audit --fund=false
ARG NODE_MAX_OLD_SPACE_SIZE=4096
RUN NODE_OPTIONS="--max-old-space-size=${NODE_MAX_OLD_SPACE_SIZE}" npm run frontend

# Promote the completed build snapshot directly. Re-copying /app makes BuildKit rescan
# millions of node_modules entries and can stall portable builds on Docker-in-WSL.
FROM build AS release
ARG BUILD_COMMIT
ARG BUILD_DATE
ENV NODE_ENV=production HOST=0.0.0.0 BUILD_COMMIT=${BUILD_COMMIT} BUILD_BRANCH=0cherry BUILD_DATE=${BUILD_DATE}
LABEL org.opencontainers.image.revision=${BUILD_COMMIT}
USER node
EXPOSE 3080
CMD ["node", "api/server/index.js"]
