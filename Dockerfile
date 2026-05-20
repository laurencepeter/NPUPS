# Stage 1: Build Flutter Web
#FROM ghcr.io/cirruslabs/flutter:stable AS build
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
FROM ghcr.io/cirruslabs/flutter:stable AS build

# API_BASE_URL is OPTIONAL. Left empty, the web app talks to its own origin
# at runtime and reaches the backend through the nginx /api proxy below — no
# rebuild needed per environment. Only set it (via
# `docker build --build-arg API_BASE_URL=https://api.example.com .`) to point
# the bundle at a backend on a different origin.
ARG API_BASE_URL=""

# Create app directory
WORKDIR /app

# Copy pubspec and get dependencies
COPY pubspec.* ./
RUN flutter pub get

# Copy full project and build web
COPY . .
RUN flutter build web --release --dart-define=API_BASE_URL=${API_BASE_URL}

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
