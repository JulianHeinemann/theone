# Build-Kontext ist das Repo-Wurzelverzeichnis (siehe railway.toml)
FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY server/package.json server/package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY server/src ./src
COPY server/public ./public
COPY restwert ./web
USER node
EXPOSE 3000
CMD ["node", "src/index.js"]
