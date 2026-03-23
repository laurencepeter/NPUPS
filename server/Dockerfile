FROM node:20-alpine

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci --omit=dev

COPY src/ src/

# Non-root user for security
RUN addgroup -g 1001 -S npups && \
    adduser -S npups -u 1001 -G npups
USER npups

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost:8080/health || exit 1

CMD ["node", "src/index.js"]
