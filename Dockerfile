# Build stage
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package.json
COPY packages/core/package.json packages/core/package.json
COPY packages/core/tsconfig.json packages/core/tsconfig.json
COPY packages/core/src packages/core/src
COPY packages/server/package.json packages/server/package.json
COPY packages/server/tsconfig.json packages/server/tsconfig.json
COPY packages/server/src packages/server/src
RUN npm install --production=false --workspaces=false --include-workspace-root --workspace=packages/core --workspace=packages/server
RUN cd packages/core && npx tsup src/index.ts --format cjs --dts --clean
RUN cd packages/server && npx tsup src/index.ts --format cjs --clean

# Run stage
FROM node:22-alpine
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
COPY package.json package.json
COPY --from=build /app/packages/core/dist /app/packages/core/dist
COPY --from=build /app/packages/core/package.json /app/packages/core/package.json
COPY --from=build /app/packages/server/dist /app/packages/server/dist
COPY --from=build /app/packages/server/package.json /app/packages/server/package.json
RUN npm install --production --workspaces=false --workspace=packages/core --workspace=packages/server
RUN chown -R app:app /app
USER app
WORKDIR /app/packages/server
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1
CMD ["node", "dist/index.js"]
