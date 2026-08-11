FROM debian:trixie-slim AS webui-fetch

ARG RECOLL_WEBUI_REF=127f849ae4bb4a690908ffef62cfb2d43784862d

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
    && git clone \
        https://framagit.org/medoc92/recollwebui.git \
        /src/recoll-webui \
    && git -C /src/recoll-webui checkout "${RECOLL_WEBUI_REF}" \
    && rm -rf /src/recoll-webui/.git \
    && rm -rf /var/lib/apt/lists/*


FROM debian:trixie-slim AS recoll-build

ARG DEBIAN_FRONTEND=noninteractive
ARG RECOLL_VERSION=1.44.1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        g++ \
        bison \
        meson \
        ninja-build \
        pkgconf \
        libxapian-dev \
        libxslt1-dev \
        zlib1g-dev \
        libmagic-dev \
        libjsoncpp-dev \
        libssl-dev \
        libaspell-dev \
        libchm-dev \
        python3-all \
        python3-all-dev \
        python3-setuptools \
    && cd /tmp \
    && curl -fsSLO \
        "https://www.recoll.org/recoll-${RECOLL_VERSION}.tar.gz" \
    && curl -fsSLO \
        "https://www.recoll.org/recoll-${RECOLL_VERSION}.tar.gz.sha256" \
    && read -r expected_hash _ \
        < "recoll-${RECOLL_VERSION}.tar.gz.sha256" \
    && printf '%s  %s\n' \
        "${expected_hash}" \
        "recoll-${RECOLL_VERSION}.tar.gz" \
        | sha256sum -c - \
    && tar -xzf "recoll-${RECOLL_VERSION}.tar.gz" \
    && cd "recoll-${RECOLL_VERSION}" \
    && meson setup \
        --buildtype=release \
        -Dprefix=/usr \
        -Dqtgui=false \
        -Drecollq=true \
        -Dx11mon=false \
        build \
    && ninja -C build \
    && DESTDIR=/out meson install -C build


FROM debian:trixie-slim

ARG DEBIAN_FRONTEND=noninteractive

ENV RECOLL_CONFDIR=/recoll/config \
    ROLE=indexer \
    RECOLL_INDEX_RUN_ON_START=true \
    RECOLL_INDEX_INTERVAL_SECONDS=21600 \
    PYTHONDONTWRITEBYTECODE=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        tzdata \
        python3 \
        python3-bottle \
        python3-waitress \
        libxapian30 \
        libxslt1.1 \
        libxml2 \
        zlib1g \
        libmagic1t64 \
        libjsoncpp26 \
        libssl3t64 \
        libaspell15 \
        libchm1 \
        libgcc-s1 \
        libstdc++6 \
        tesseract-ocr-all \
        poppler-utils \
        antiword \
        wv \
        unrtf \
        libimage-exiftool-perl \
        python3-lxml \
        python3-mutagen \
        python3-py7zr \
        python3-chardet \
        libwpd-tools \
        libwps-tools \
        djvulibre-bin \
        pff-tools \
        ghostscript \
        catdvi \
        untex \
        groff \
        aspell \
        xsltproc \
    && rm -rf /var/lib/apt/lists/*

COPY --from=recoll-build /out/usr/ /usr/
COPY --from=webui-fetch /src/recoll-webui /opt/recoll-webui
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN ldconfig \
    && chmod 0755 /usr/local/bin/entrypoint.sh \
    && mkdir -p \
        /documents/source \
        /recoll/config \
        /recoll/index \
        /recoll/cache \
        /recoll/tmp \
    && command -v recollindex >/dev/null \
    && command -v recollq >/dev/null \
    && command -v tesseract >/dev/null \
    && command -v pdftotext >/dev/null \
    && command -v antiword >/dev/null \
    && command -v unrtf >/dev/null \
    && python3 -c 'from recoll import recoll' \
    && test -f /usr/share/recoll/filters/rclpdf.py \
    && test -f /usr/share/recoll/filters/rclimgp.py \
    && tesseract --list-langs 2>/dev/null \
        | grep -qx 'eng' \
    && tesseract --list-langs 2>/dev/null \
        | grep -qx 'chi_sim' \
    && tesseract --list-langs 2>/dev/null \
        | grep -qx 'chi_tra'

ENV TMPDIR=/recoll/tmp

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
