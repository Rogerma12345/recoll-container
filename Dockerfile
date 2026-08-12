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

FROM debian:trixie-slim AS whisper-build

ARG DEBIAN_FRONTEND=noninteractive
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1

COPY whisper-requirements.txt /tmp/whisper-requirements.txt
COPY whisper-policy-patch.py /tmp/whisper-policy-patch.py

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        python3 \
        python3-pip \
        python3-setuptools \
        python3-wheel \
    && python3 -m pip install \
        --break-system-packages \
        --no-cache-dir \
        --no-deps \
        --no-build-isolation \
        --require-hashes \
        --target /out \
        -r /tmp/whisper-requirements.txt \
    && python3 /tmp/whisper-policy-patch.py \
        /out/whisper/__init__.py \
    && rm -rf /out/bin \
    && find /out -type d -name '__pycache__' -prune -exec rm -rf '{}' + \
    && rm -rf /var/lib/apt/lists/*

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
        python3-filelock \
        python3-more-itertools \
        python3-numba \
        python3-numpy \
        python3-tiktoken \
        python3-torch \
        python3-tqdm \
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
        aspell-en \
        ffmpeg \
        xsltproc \
    && apt-get check \
    && rm -rf /var/lib/apt/lists/*

COPY --from=recoll-build /out/usr/ /usr/
COPY --from=webui-fetch /src/recoll-webui /opt/recoll-webui
COPY --from=whisper-build /out/ /opt/openai-whisper/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY whisper-cli /usr/local/bin/whisper
COPY whisper-selftest.py /usr/local/libexec/recoll-container/whisper-selftest.py

ENV RECOLL_CONFDIR=/recoll/config \
    RECOLL_TMPDIR=/recoll/tmp \
    TMPDIR=/recoll/tmp \
    HOME=/recoll/tmp \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH=/opt/openai-whisper \
    WHISPER_MODEL_DIR=/recoll/models/whisper \
    WHISPER_ALLOW_DOWNLOAD=0

RUN ldconfig \
    && chmod 0755 \
        /usr/local/bin/entrypoint.sh \
        /usr/local/bin/whisper \
        /usr/local/libexec/recoll-container/whisper-selftest.py \
    && mkdir -p \
        /documents/source \
        /recoll/config \
        /recoll/index \
        /recoll/cache \
        /recoll/state \
        /recoll/tmp \
        /recoll/models/whisper \
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
    && command -v ffmpeg >/dev/null \
    && command -v whisper >/dev/null \
    && test "$(dpkg-query -W -f='${Status}' aspell-en)" = "install ok installed" \
    && printf 'hello\nworld\n' \
        | aspell --lang=en --encoding=utf-8 \
            create master /tmp/aspell-en-test.rws \
    && test -s /tmp/aspell-en-test.rws \
    && rm -f /tmp/aspell-en-test.rws \
    && python3 -c 'from recoll import recoll, rclextract; import bottle, waitress, pyexiv2, py7zr, mutagen, lxml, chardet' \
    && python3 -c 'import torch; assert torch.version.cuda is None' \
    && python3 -c 'import filelock, more_itertools, numba, numpy, tiktoken, tqdm, whisper; assert whisper.__version__ == "20250625"' \
    && test -x /usr/share/recoll/filters/rclpdf.py \
    && test -x /usr/share/recoll/filters/rclimg.py \
    && test -x /usr/share/recoll/filters/rclimgp.py \
    && test -x /usr/share/recoll/filters/rclaudio.py \
    && grep -Fq 'import whisper' /usr/share/recoll/filters/rclaudio.py \
    && grep -Fq 'whisper.load_model' /usr/share/recoll/filters/rclaudio.py \
    && grep -Fq 'from filelock import FileLock' /usr/share/recoll/filters/rclaudio.py \
    && whisper --help >/dev/null \
    && /usr/local/libexec/recoll-container/whisper-selftest.py \
    && test -z "$(find /recoll/models/whisper -mindepth 1 -maxdepth 1 -print -quit)" \
    && python3 -c 'compile(open("/opt/recoll-webui/webui-standalone.py", encoding="utf-8").read(), "webui-standalone.py", "exec"); compile(open("/opt/recoll-webui/webui.py", encoding="utf-8").read(), "webui.py", "exec")'

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
