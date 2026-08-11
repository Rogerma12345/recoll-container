FROM debian:trixie-slim AS webui-fetch

ARG RECOLL_WEBUI_REF=127f849ae4bb4a690908ffef62cfb2d43784862d

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
    && git clone \
        https://framagit.org/medoc92/recollwebui.git \
        /src/recoll-webui \
    && git -C /src/recoll-webui checkout --detach "${RECOLL_WEBUI_REF}" \
    && test "$(git -C /src/recoll-webui rev-parse HEAD)" = "${RECOLL_WEBUI_REF}" \
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
        -Dlibdir=lib \
        -Drecollq=true \
        -Dx11mon=false \
        build \
    && ninja -C build \
    && DESTDIR=/out meson install -C build

FROM debian:trixie-slim

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        tzdata \
        util-linux \
        python3 \
        python3-bottle \
        python3-waitress \
        python3-py3exiv2 \
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
    && apt-get check \
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
        /recoll/state \
        /recoll/tmp \
    && sh -n /usr/local/bin/entrypoint.sh \
    && recollindex -h 2>&1 | grep -Fq 'Recoll version: Recoll 1.44.1' \
    && command -v recollq >/dev/null \
    && tesseract --version >/dev/null \
    && tesseract --list-langs >/dev/null \
    && test "$(dpkg-query -W -f='${Status}' tesseract-ocr-all)" = "install ok installed" \
    && command -v pdftotext >/dev/null \
    && command -v antiword >/dev/null \
    && command -v unrtf >/dev/null \
    && command -v setpriv >/dev/null \
    && python3 -c 'from recoll import recoll, rclextract; import bottle, waitress, pyexiv2, py7zr, mutagen, lxml, chardet' \
    && test -x /usr/share/recoll/filters/rclpdf.py \
    && test -x /usr/share/recoll/filters/rclimg.py \
    && test -x /usr/share/recoll/filters/rclimgp.py \
    && python3 -c 'compile(open("/opt/recoll-webui/webui-standalone.py", encoding="utf-8").read(), "webui-standalone.py", "exec"); compile(open("/opt/recoll-webui/webui.py", encoding="utf-8").read(), "webui.py", "exec")'

ENV RECOLL_CONFDIR=/recoll/config \
    RECOLL_TMPDIR=/recoll/tmp \
    TMPDIR=/recoll/tmp \
    HOME=/recoll/tmp \
    PYTHONDONTWRITEBYTECODE=1

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
