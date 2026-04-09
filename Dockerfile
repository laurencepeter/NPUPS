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

# API_BASE_URL is injected at build time so Flutter can embed it as a
# compile-time constant via --dart-define.
# Pass via: docker build --build-arg API_BASE_URL=http://YOUR_SERVER:3000 .
ARG API_BASE_URL=http://localhost:3000

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

# Custom nginx config: Flutter routing + cache-control headers
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
