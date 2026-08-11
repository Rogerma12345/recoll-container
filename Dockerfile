FROM debian:trixie-slim AS webui-fetch

ARG RECOLL_WEBUI_REF=127f849ae4bb4a690908ffef62cfb2d43784862d

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
    && git clone https://framagit.org/medoc92/recollwebui.git /src/recoll-webui \
    && git -C /src/recoll-webui checkout "${RECOLL_WEBUI_REF}" \
    && rm -rf /src/recoll-webui/.git \
    && rm -rf /var/lib/apt/lists/*


FROM debian:trixie-slim

ARG DEBIAN_FRONTEND=noninteractive
ARG RECOLL_EXPECTED_VERSION=1.44.1

ENV RECOLL_CONFDIR=/recoll/config \
    ROLE=indexer \
    RECOLL_INDEX_RUN_ON_START=true \
    RECOLL_INDEX_INTERVAL_SECONDS=21600 \
    PYTHONDONTWRITEBYTECODE=1 \
    TMPDIR=/recoll/tmp

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
    && curl -fsSL \
        https://www.lesbonscomptes.com/pages/lesbonscomptes.gpg \
        -o /usr/share/keyrings/lesbonscomptes.gpg \
    && arch="$(dpkg --print-architecture)" \
    && case "${arch}" in \
         amd64) \
           curl -fsSL \
             https://www.recoll.org/pages/recoll-trixie.sources \
             -o /etc/apt/sources.list.d/recoll.sources \
           ;; \
         arm64) \
           curl -fsSL \
             https://www.recoll.org/pages/recoll-rtrixie.sources \
             -o /etc/apt/sources.list.d/recoll.sources \
           ;; \
         *) \
           echo "Unsupported architecture: ${arch}" >&2; \
           exit 1 \
           ;; \
       esac \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        recoll \
        python3-recoll \
        python3-waitress \
        tesseract-ocr-all \
        poppler-utils \
        antiword \
        unrtf \
        libimage-exiftool-perl \
        python3-lxml \
        python3-mutagen \
        python3-py7zr \
        libwpd-tools \
        djvulibre-bin \
        pff-tools \
        ghostscript \
        catdvi \
        untex \
        groff \
        aspell \
    && installed_version="$(dpkg-query -W -f='${Version}' recoll)" \
    && case "${installed_version}" in \
         "${RECOLL_EXPECTED_VERSION}"*) ;; \
         *) \
           echo "Unexpected Recoll version: ${installed_version}" >&2; \
           exit 1 \
           ;; \
       esac \
    && rm -rf /var/lib/apt/lists/*

COPY --from=webui-fetch /src/recoll-webui /opt/recoll-webui
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/entrypoint.sh \
    && mkdir -p \
        /documents/source \
        /recoll/config \
        /recoll/index \
        /recoll/cache \
        /recoll/tmp

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
