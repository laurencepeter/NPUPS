# Stage 1: Build Flutter Web
#FROM ghcr.io/cirruslabs/flutter:3.32.2 AS build
#WORKDIR /app
#COPY pubspec.yaml ./
#RUN flutter pub get
#COPY . .
#RUN flutter build web --release

# Stage 2: Serve with nginx
#FROM nginx:alpine
#COPY --from=build /app/build/web /usr/share/nginx/html
#COPY nginx.conf /etc/nginx/conf.d/default.conf
#EXPOSE 80
#CMD ["nginx", "-g", "daemon off;"]


# Stage 1: Build Flutter Web
FROM ghcr.io/cirruslabs/flutter:3.32.2 AS build

# Create app directory
WORKDIR /app

# Copy pubspec and get dependencies
COPY pubspec.* ./
RUN flutter pub get

# Copy full project and build web. Supabase credentials are baked into
# lib/config/supabase_config.dart. No API_BASE_URL is baked in: the bundle
# always talks to its own origin and nginx forwards /api/* to the backend.
COPY . .
# This image is built ON the Coolify host (docker-compose.prod.yml `build: .`).
# dart2js is memory/CPU-heavy and at the default optimization (O4) its
# whole-program inlining peaked high enough to OOM-kill the constrained build
# host mid-compile (deploy exit 255). O2 keeps tree-shaking + minification but
# drops the most memory-hungry global passes, cutting peak RAM and build time.
# If the host still gets killed mid-compile, lower this to O1 (larger/slower
# output) or give the host more RAM/swap.
RUN flutter build web --release --dart2js-optimization=O2

# Stage 2: Serve with nginx
FROM nginx:alpine

# Remove default nginx content
RUN rm -rf /usr/share/nginx/html/*

# Copy Flutter build
COPY --from=build /app/build/web /usr/share/nginx/html

# nginx config template: Flutter routing + cache-control + same-origin /api
# proxy. The base image's entrypoint runs envsubst over files in
# /etc/nginx/templates at startup, rendering this to conf.d/default.conf.
COPY nginx.conf /etc/nginx/templates/default.conf.template

# Where nginx forwards /api/* requests. Override at `docker run` time
# (-e API_UPSTREAM=http://your-api-host:8080) for non-compose deployments.
# Must have NO trailing slash and NO /api suffix.
ENV API_UPSTREAM=http://api:8080

# Restrict envsubst to API_UPSTREAM so nginx's own $uri/$host/$scheme
# variables in the template are left intact.
ENV NGINX_ENVSUBST_FILTER=API_UPSTREAM

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
