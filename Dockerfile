# -------------------------
# 1️⃣ Builder base (nightly Rust)
# -------------------------
FROM --platform=$BUILDPLATFORM lukemathwalker/cargo-chef:latest-rust-slim-trixie AS chef
WORKDIR /build

# 切换到 nightly Rust
RUN rustup default nightly

# -------------------------
# 2️⃣ Planner
# -------------------------
FROM --platform=$BUILDPLATFORM chef AS planner
COPY . .
RUN cargo +nightly chef prepare --recipe-path /recipe.json

# -------------------------
# 3️⃣ Builder
# -------------------------
FROM --platform=$BUILDPLATFORM chef AS builder
ARG TARGETPLATFORM
ARG RUSTFLAGS
ARG CARGO_TARGET

# 选择目标架构和 linker
RUN case "${TARGETPLATFORM}" in \
    "linux/arm64") echo "aarch64-unknown-linux-gnu" > /target.txt && echo "-C linker=aarch64-linux-gnu-gcc" > /flags.txt ;; \
    "linux/amd64") echo "x86_64-unknown-linux-gnu" > /target.txt && echo "-C linker=x86_64-linux-gnu-gcc" > /flags.txt ;; \
    *) echo "Unsupported platform" && exit 1 ;; \
    esac

# 安装交叉编译工具链和依赖
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -yq --no-install-recommends \
    build-essential libclang-19-dev \
    g++-aarch64-linux-gnu binutils-aarch64-linux-gnu \
    g++-x86-64-linux-gnu binutils-x86-64-linux-gnu

# 安装 Rust target
RUN rustup target add "$(cat /target.txt)"

# cargo-chef cook (nightly)
COPY --from=planner /recipe.json /recipe.json
RUN RUSTFLAGS="$(cat /flags.txt)" cargo +nightly chef cook \
    --target "$(cat /target.txt)" \
    --release \
    --no-default-features \
    --features "sqlite postgres mysql rocks s3 redis azure nats enterprise" \
    --recipe-path /recipe.json

# -------------------------
# 4️⃣ Build main crates
# -------------------------
COPY . .

# 限制并行线程，降低内存消耗
RUN RUSTFLAGS="$(cat /flags.txt)" cargo +nightly build \
    --target "$(cat /target.txt)" \
    --release \
    -p stalwart \
    --no-default-features \
    --features "sqlite postgres mysql rocks s3 redis azure nats enterprise" \
    --jobs 1

RUN RUSTFLAGS="$(cat /flags.txt)" cargo +nightly build \
    --target "$(cat /target.txt)" \
    --release \
    -p stalwart-cli \
    --jobs 1

# 输出
RUN mv "/build/target/$(cat /target.txt)/release" "/output"

# -------------------------
# 5️⃣ Final runtime image
# -------------------------
FROM debian:trixie-slim
WORKDIR /opt/stalwart
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -yq --no-install-recommends ca-certificates

# 复制可执行文件
COPY --from=builder /output/stalwart /usr/local/bin
COPY --from=builder /output/stalwart-cli /usr/local/bin
COPY ./resources/docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod -R 755 /usr/local/bin

CMD ["/usr/local/bin/stalwart"]
VOLUME [ "/opt/stalwart" ]
EXPOSE 443 25 110 587 465 143 993 995 4190 8080
ENTRYPOINT ["/bin/sh", "/usr/local/bin/entrypoint.sh"]