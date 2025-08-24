# ------------------------------
# Build Arguments
# ------------------------------
ARG GO_VERSION="1.25"
ARG ALPINE_VERSION="3.22"
ARG DART_SASS_VERSION="1.79.3"

# ------------------------------
# Base tools for cross-compilation
# ------------------------------
FROM --platform=$BUILDPLATFORM tonistiigi/xx:1.5.0 AS xx

# ------------------------------
# Builder image
# ------------------------------
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS gobuild

# ------------------------------
# Runtime image
# ------------------------------
FROM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS gorun

# ------------------------------
# Build Hugo from your branch
# ------------------------------
FROM gobuild AS build

RUN apk add clang lld git

# Set up cross-compilation helpers
COPY --from=xx / /

ARG TARGETPLATFORM
RUN xx-apk add musl-dev gcc g++

# Hugo build tags: standard, extended, extended,withdeploy
ARG HUGO_BUILD_TAGS="extended"
ENV CGO_ENABLED=1
ENV GOPROXY=https://proxy.golang.org
ENV GOCACHE=/root/.cache/go-build
ENV GOMODCACHE=/go/pkg/mod

# Clone your custom Hugo repo branch
WORKDIR /go/src/github.com/vishal194071/hugo_official
ARG HUGO_REPO="https://github.com/vishal194071/hugo_official.git"
ARG HUGO_BRANCH="my_local_master_hugo"
RUN git clone --depth 1 --branch ${HUGO_BRANCH} ${HUGO_REPO} .

# Build Hugo
RUN --mount=target=. \
    --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build,id=go-build-$TARGETPLATFORM <<EOT
    set -ex
    xx-go build -tags "$HUGO_BUILD_TAGS" -ldflags "-s -w -X github.com/gohugoio/hugo/common/hugo.vendorInfo=docker" -o /usr/bin/hugo
    xx-verify /usr/bin/hugo
EOT

# ------------------------------
# Dart Sass stage
# ------------------------------
FROM alpine:${ALPINE_VERSION} AS dart-sass
ARG TARGETARCH
ARG DART_SASS_VERSION
ARG DART_ARCH=${TARGETARCH/amd64/x64}
WORKDIR /out
ADD https://github.com/sass/dart-sass/releases/download/${DART_SASS_VERSION}/dart-sass-${DART_SASS_VERSION}-linux-${DART_ARCH}.tar.gz .
RUN tar -xf dart-sass-${DART_SASS_VERSION}-linux-${DART_ARCH}.tar.gz

# ------------------------------
# Final runtime image
# ------------------------------
FROM gorun AS final

COPY --from=build /usr/bin/hugo /usr/bin/hugo

# libc6-compat is required for extended libraries
RUN apk add --no-cache libc6-compat git runuser nodejs npm

# Setup Hugo user and cache
RUN mkdir -p /var/hugo/bin /cache && \
    addgroup -Sg 1000 hugo && \
    adduser -Sg hugo -u 1000 -h /var/hugo hugo && \
    chown -R hugo: /var/hugo /cache && \
    runuser -u hugo -- git config --global --add safe.directory /project && \
    runuser -u hugo -- git config --global core.quotepath false

USER hugo:hugo
VOLUME /project
WORKDIR /project
ENV HUGO_CACHEDIR=/cache
ENV PATH="/var/hugo/bin:$PATH"

COPY scripts/docker/entrypoint.sh /entrypoint.sh
COPY --from=dart-sass /out/dart-sass /var/hugo/bin

# Update PATH to include Dart Sass
ENV PATH="/var/hugo/bin/dart-sass:$PATH"

# Expose Hugo server port
EXPOSE 1313

ENTRYPOINT ["/entrypoint.sh"]
CMD ["--help"]
