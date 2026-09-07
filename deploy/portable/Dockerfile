FROM node:24.16.0-alpine@sha256:21f403ab171f2dc89bad4dd69d7721bfd15f084ccb46cdd225f31f2bc59b5c9a AS runtime
RUN apk add --no-cache jemalloc python3 py3-pip uv
ENV LD_PRELOAD=/usr/lib/libjemalloc.so.2
WORKDIR /app
RUN chown node:node /app

FROM runtime AS dependencies
COPY --chown=node:node package.json package-lock.json ./
COPY --chown=node:node api/package.json ./api/package.json
COPY --chown=node:node client/package.json ./client/package.json
COPY --chown=node:node packages/api/package.json ./packages/api/package.json
COPY --chown=node:node packages/client/package.json ./packages/client/package.json
COPY --chown=node:node packages/data-provider/package.json ./packages/data-provider/package.json
COPY --chown=node:node packages/data-schemas/package.json ./packages/data-schemas/package.json
USER node

FROM dependencies AS build
RUN npm ci --no-audit --fund=false
COPY --chown=node:node . .
RUN touch .env && mkdir -p client/public/images logs uploads skill data && chmod 1777 data
ARG NODE_MAX_OLD_SPACE_SIZE=4096
RUN NODE_OPTIONS="--max-old-space-size=${NODE_MAX_OLD_SPACE_SIZE}" npm run frontend

FROM dependencies AS release
RUN npm ci --omit=dev --no-audit --fund=false && npm cache clean --force
COPY --from=build --chown=node:node /app/api ./api
COPY --from=build --chown=node:node /app/config ./config
COPY --from=build --chown=node:node /app/skill ./skill
COPY --from=build --chown=node:node /app/packages/data-provider/dist ./packages/data-provider/dist
COPY --from=build --chown=node:node /app/packages/data-schemas/dist ./packages/data-schemas/dist
COPY --from=build --chown=node:node /app/packages/api/dist ./packages/api/dist
COPY --from=build --chown=node:node /app/client/dist ./client/dist
USER root
RUN touch .env && \
    mkdir -p client/public/images logs uploads skill data && \
    chown -R node:node .env client/public/images logs uploads skill data && \
    chmod 1777 data
ARG BUILD_COMMIT
ARG BUILD_DATE
ENV NODE_ENV=production HOST=0.0.0.0 BUILD_COMMIT=${BUILD_COMMIT} BUILD_BRANCH=0cherry BUILD_DATE=${BUILD_DATE}
LABEL org.opencontainers.image.revision=${BUILD_COMMIT}
USER node
EXPOSE 3080
CMD ["node", "api/server/index.js"]
