# Node 22, NOT 20. @supabase/supabase-js v2 (>=2.45) requires a global
# WebSocket at createClient() time; Node 20 has none, so the client throws on
# init and the api crash-loops at boot ("Node.js 20 detected without native
# WebSocket support"). Node 22 ships native WebSocket. Do not downgrade.
FROM node:22-alpine

WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund

COPY index.js ./

EXPOSE 8080
CMD ["node", "index.js"]
