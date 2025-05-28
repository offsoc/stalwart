# Stalwart Dockerfile
# Credits: https://github.com/33KK

FROM --platform=$BUILDPLATFORM docker.io/lukemathwalker/cargo-chef:latest-rust-slim-bookworm AS chef
WORKDIR /build

FROM --platform=$BUILDPLATFORM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path /recipe.json

FROM --platform=$BUILDPLATFORM chef AS builder
ARG TARGETPLATFORM
RUN case "${TARGETPLATFORM}" in \
    "linux/arm64") echo "aarch64-unknown-linux-gnu" > /target.txt && echo "-C linker=aarch64-linux-gnu-gcc" > /flags.txt ;; \
    "linux/amd64") echo "x86_64-unknown-linux-gnu" > /target.txt && echo "-C linker=x86_64-linux-gnu-gcc" > /flags.txt ;; \
    *) exit 1 ;; \
    esac
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -yq build-essential libclang-16-dev \
    g++-aarch64-linux-gnu binutils-aarch64-linux-gnu \
    g++-x86-64-linux-gnu binutils-x86-64-linux-gnu

# --- Start FoundationDB Client Installation ---
# Ensure wget is available
RUN apt-get install -yq wget

# Initialize a flag file to indicate if FoundationDB client was successfully installed
RUN touch /fdb_client_installed.flag

# Attempt to download and install FoundationDB client based on target platform
RUN case "${TARGETPLATFORM}" in \
    "linux/amd64") \
        echo "Attempting to install FoundationDB client for linux/amd64..." && \
        if wget -q https://github.com/apple/foundationdb/releases/download/7.3.67/foundationdb-clients_7.3.67-1_amd64.deb && \
           dpkg -i foundationdb-clients_7.3.67-1_amd64.deb; then \
            echo "FoundationDB client (amd64) installed successfully." && \
            rm foundationdb-clients_7.3.67-1_amd64.deb \
        else \
            echo "FoundationDB client (amd64) installation failed or is incompatible; skipping." && \
            rm -f foundationdb-clients_7.3.67-1_amd64.deb && \
            rm /fdb_client_installed.flag \
        fi \
        ;; \
    "linux/arm64") \
        echo "Attempting to install FoundationDB client for linux/arm64..." && \
        if wget -q https://github.com/apple/foundationdb/releases/download/7.3.67/foundationdb-clients_7.3.67-1_aarch64.deb && \
           dpkg -i foundationdb-clients_7.3.67-1_aarch64.deb; then \
            echo "FoundationDB client (aarch64) installed successfully." && \
            rm foundationdb-clients_7.3.67-1_aarch64.deb \
        else \
            echo "FoundationDB client (aarch64) installation failed or is incompatible; skipping." && \
            rm -f foundationdb-clients_7.3.67-1_aarch64.deb && \
            rm /fdb_client_installed.flag \
        fi \
        ;; \
    *) \
        echo "No FoundationDB client package available for ${TARGETPLATFORM}; skipping installation." && \
        rm /fdb_client_installed.flag \
        ;; \
    esac
# --- End FoundationDB Client Installation ---

RUN rustup target add "$(cat /target.txt)"
COPY --from=planner /recipe.json /recipe.json
RUN RUSTFLAGS="$(cat /flags.txt)" cargo chef cook --target "$(cat /target.txt)" --release --no-default-features --features "sqlite postgres mysql rocks elastic s3 redis azure nats enterprise" --recipe-path /recipe.json
COPY . .
RUN RUSTFLAGS="$(cat /flags.txt)" cargo build --target "$(cat /target.txt)" --release -p stalwart --no-default-features --features "sqlite postgres mysql rocks elastic s3 redis azure nats enterprise"
RUN RUSTFLAGS="$(cat /flags.txt)" cargo build --target "$(cat /target.txt)" --release -p stalwart-cli

# --- Start Conditional stalwart-enterprise Compilation ---
# Only compile stalwart-enterprise if FoundationDB client was successfully installed
RUN if [ -f /fdb_client_installed.flag ]; then \
    echo "FoundationDB client installed, compiling stalwart-enterprise..."; \
    RUSTFLAGS="$(cat /flags.txt)" cargo build --target "$(cat /target.txt)" --release -p stalwart-enterprise --no-default-features --features "sqlite foundationdb postgres mysql rocks elastic s3 redis azure nats zenoh kafka enterprise"; \
else \
    echo "FoundationDB client not installed; skipping stalwart-enterprise compilation."; \
fi
# --- End Conditional stalwart-enterprise Compilation ---

RUN mv "/build/target/$(cat /target.txt)/release" "/output"

FROM docker.io/debian:bookworm-slim
WORKDIR /opt/stalwart
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -yq ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* # Clean up apt cache for smaller image size

# Conditionally copy stalwart-enterprise based on whether it was compiled
COPY --from=builder /output/stalwart /usr/local/bin
COPY --from=builder /output/stalwart-cli /usr/local/bin
RUN if [ -f /output/stalwart-enterprise ]; then \
    echo "Copying stalwart-enterprise..."; \
    mv /output/stalwart-enterprise /usr/local/bin/stalwart-enterprise; \
else \
    echo "stalwart-enterprise not found; skipping copy."; \
fi

COPY ./resources/docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod -R 755 /usr/local/bin
CMD ["/usr/local/bin/stalwart"]
VOLUME [ "/opt/stalwart" ]
EXPOSE	443 25 110 587 465 143 993 995 4190 8080
ENTRYPOINT ["/bin/sh", "/usr/local/bin/entrypoint.sh"]
