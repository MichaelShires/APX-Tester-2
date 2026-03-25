FROM --platform=linux/amd64 ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install base dependencies + CSmith + LLVM 19
RUN apt-get update && apt-get install -y \
    wget gnupg software-properties-common \
    csmith libcsmith-dev \
    build-essential \
    && wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc \
    && echo "deb http://apt.llvm.org/noble/ llvm-toolchain-noble-19 main" > /etc/apt/sources.list.d/llvm.list \
    && apt-get update && apt-get install -y clang-19 \
    && ln -sf /usr/bin/clang-19 /usr/bin/clang \
    && rm -rf /var/lib/apt/lists/*

# Copy Intel SDE
COPY sde-external-10.8.0-2026-03-15-lin /opt/sde

ENV PATH="/opt/sde:${PATH}"
ENV CSMITH_PATH="/usr/include/csmith"

WORKDIR /work
