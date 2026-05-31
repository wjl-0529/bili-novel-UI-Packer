ARG NODE_IMAGE=node:20-alpine
ARG DART_IMAGE=dart:stable

FROM ${NODE_IMAGE} AS web-build
ARG NPM_REGISTRY=https://registry.npmjs.org
WORKDIR /src
COPY package*.json ./
RUN npm config set registry ${NPM_REGISTRY} && npm install
COPY tsconfig*.json vite.config.ts ./
COPY web ./web
RUN npm run build

FROM ${DART_IMAGE} AS dart-build
WORKDIR /src
COPY pubspec.yaml ./
RUN dart pub get
COPY bin ./bin
COPY lib ./lib
RUN mkdir -p /build && dart compile exe bin/server.dart -o /build/bili-novel-packer-server

FROM ${DART_IMAGE} AS runtime
WORKDIR /app
COPY --from=dart-build /build/bili-novel-packer-server /app/server
COPY --from=web-build /src/web/dist /app/web
ENV HOST=0.0.0.0
ENV PORT=8080
ENV DATA_DIR=/data
ENV WEB_ROOT=/app/web
EXPOSE 8080
CMD ["/app/server"]
