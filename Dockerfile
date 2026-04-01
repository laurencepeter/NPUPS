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

# Create app directory
WORKDIR /app

# Copy pubspec and get dependencies
COPY pubspec.* ./
RUN flutter pub get

# Copy full project and build web
COPY . .
RUN flutter build web --release

# Stage 2: Serve with nginx
FROM nginx:alpine

# Remove default nginx content
RUN rm -rf /usr/share/nginx/html/*

# Copy Flutter build and nginx config
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Run as non-root user
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid
USER nginx

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
