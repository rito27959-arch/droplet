# Public HTTPS is terminated by Railway. The directory binds to Railway's PORT.
FROM dart:stable-sdk AS build
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get
COPY lib ./lib
RUN dart compile exe lib/server.dart -o /app/server

FROM debian:bookworm-slim
WORKDIR /app
COPY --from=build /app/server /app/server
EXPOSE 8080
CMD ["/app/server", "--host", "0.0.0.0"]
