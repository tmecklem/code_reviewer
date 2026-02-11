# syntax = docker/dockerfile:1

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV MIX_HOME=/opt/mix
ENV HEX_HOME=/opt/hex

# Install system dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    # locale support
    locales \
    # dev tools
    bash-completion \
    build-essential \
    curl \
    ca-certificates \
    git \
    jq \
    vim \
    wget \
    # Elixir build dependencies (for mise)
    autoconf \
    libssl-dev \
    libncurses5-dev \
    && rm -rf /var/lib/apt/lists/*

# Install gh CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && \
    apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/*

# Configure UTF-8 locale
RUN locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Create mix/hex cache directories
RUN mkdir -p /opt/mix /opt/hex && \
    chmod -R 777 /opt/mix /opt/hex

WORKDIR /app

EXPOSE 4000
