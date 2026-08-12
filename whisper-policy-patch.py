#!/usr/bin/python3

import ast
from pathlib import Path
import sys
import textwrap


DOWNLOAD_REPLACEMENT = textwrap.dedent(
    r'''
    def _env_enabled(name: str) -> bool:
        return os.getenv(name, "").strip().lower() in {
            "1",
            "true",
            "yes",
            "on",
        }


    def _sha256_file(path: str) -> str:
        digest = hashlib.sha256()
        with open(path, "rb") as source:
            while True:
                chunk = source.read(1024 * 1024)
                if not chunk:
                    break
                digest.update(chunk)
        return digest.hexdigest()


    def _return_model_file(path: str, in_memory: bool) -> Union[bytes, str]:
        if not in_memory:
            return path
        with open(path, "rb") as source:
            return source.read()


    def _download(url: str, root: str, in_memory: bool) -> Union[bytes, str]:
        expected_sha256 = url.split("/")[-2]
        download_target = os.path.join(root, os.path.basename(url))
        allow_download = _env_enabled("WHISPER_ALLOW_DOWNLOAD")

        if os.path.exists(download_target) and not os.path.isfile(download_target):
            raise RuntimeError(
                f"{download_target} exists and is not a regular file"
            )

        if os.path.isfile(download_target):
            actual_sha256 = _sha256_file(download_target)
            if actual_sha256 == expected_sha256:
                return _return_model_file(download_target, in_memory)

            if not allow_download:
                raise RuntimeError(
                    f"Whisper model checksum mismatch: {download_target}. "
                    "Automatic model downloads are disabled. Replace the file "
                    "with the official model or explicitly enable "
                    "WHISPER_ALLOW_DOWNLOAD."
                )

        elif not allow_download:
            raise RuntimeError(
                f"Whisper model file is missing: {download_target}. "
                "Automatic model downloads are disabled. Place the official "
                "model in WHISPER_MODEL_DIR or explicitly enable "
                "WHISPER_ALLOW_DOWNLOAD."
            )

        try:
            os.makedirs(root, exist_ok=True)
        except OSError as exc:
            raise RuntimeError(
                f"Cannot prepare Whisper model directory {root}: {exc}"
            ) from exc

        lock_target = f"{download_target}.lock"
        try:
            lock_file = open(lock_target, "a+b")
        except OSError as exc:
            raise RuntimeError(
                f"Whisper model directory is not writable: {root}: {exc}"
            ) from exc

        with lock_file:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)

            if os.path.exists(download_target) and not os.path.isfile(
                download_target
            ):
                raise RuntimeError(
                    f"{download_target} exists and is not a regular file"
                )

            if os.path.isfile(download_target):
                actual_sha256 = _sha256_file(download_target)
                if actual_sha256 == expected_sha256:
                    return _return_model_file(download_target, in_memory)

                warnings.warn(
                    f"{download_target} exists, but its SHA256 checksum does "
                    "not match; downloading a replacement"
                )

            file_descriptor, partial_target = tempfile.mkstemp(
                dir=root,
                prefix=f".{os.path.basename(download_target)}.",
                suffix=".part",
            )

            try:
                with os.fdopen(file_descriptor, "wb") as output:
                    with urllib.request.urlopen(url) as source:
                        content_length = source.info().get("Content-Length")
                        total = (
                            int(content_length)
                            if content_length is not None
                            else None
                        )

                        with tqdm(
                            total=total,
                            ncols=80,
                            unit="iB",
                            unit_scale=True,
                            unit_divisor=1024,
                        ) as loop:
                            while True:
                                buffer = source.read(8192)
                                if not buffer:
                                    break
                                output.write(buffer)
                                loop.update(len(buffer))

                actual_sha256 = _sha256_file(partial_target)
                if actual_sha256 != expected_sha256:
                    raise RuntimeError(
                        "Whisper model download completed, but its SHA256 "
                        "checksum does not match the official value."
                    )

                os.replace(partial_target, download_target)

            finally:
                if os.path.exists(partial_target):
                    os.remove(partial_target)

        return _return_model_file(download_target, in_memory)
    '''
).lstrip()


MODEL_DIR_REPLACEMENT = textwrap.indent(
    textwrap.dedent(
        r'''
        if download_root is None:
            fallback_cache = (
                os.getenv("XDG_CACHE_HOME")
                or os.path.join(os.path.expanduser("~"), ".cache")
            )
            download_root = (
                os.getenv("WHISPER_MODEL_DIR")
                or os.path.join(fallback_cache, "whisper")
            )
        '''
    ).lstrip(),
    "    ",
)


IMPORTS = "import fcntl\nimport tempfile\nimport urllib.request\n"


def fail(message: str) -> None:
    raise RuntimeError(message)


def find_function(module: ast.Module, name: str) -> ast.FunctionDef:
    matches = [
        node
        for node in module.body
        if isinstance(node, ast.FunctionDef) and node.name == name
    ]
    if len(matches) != 1:
        fail(f"Expected exactly one function named {name}")
    return matches[0]


def is_download_root_test(node: ast.If) -> bool:
    test = node.test
    if not isinstance(test, ast.Compare):
        return False
    if not isinstance(test.left, ast.Name):
        return False
    if test.left.id != "download_root":
        return False
    if len(test.ops) != 1 or not isinstance(test.ops[0], ast.Is):
        return False
    if len(test.comparators) != 1:
        return False
    comparator = test.comparators[0]
    return isinstance(comparator, ast.Constant) and comparator.value is None


def main() -> None:
    if len(sys.argv) != 2:
        fail("Usage: whisper-policy-patch.py PATH_TO_WHISPER_INIT")

    path = Path(sys.argv[1])
    source = path.read_text(encoding="utf-8")

    required_source_tokens = (
        "def _download(",
        "def load_model(",
        "hashlib.sha256",
        "download_root",
        "urllib.request.urlopen",
    )
    for token in required_source_tokens:
        if token not in source:
            fail(f"Unexpected Whisper source; missing token: {token}")

    module = ast.parse(source)
    download_function = find_function(module, "_download")
    load_model_function = find_function(module, "load_model")

    model_dir_nodes = [
        node
        for node in load_model_function.body
        if isinstance(node, ast.If) and is_download_root_test(node)
    ]
    if len(model_dir_nodes) != 1:
        fail(
            "Expected exactly one download_root default block inside load_model"
        )

    model_dir_node = model_dir_nodes[0]
    lines = source.splitlines(keepends=True)

    replacements = [
        (
            download_function.lineno - 1,
            download_function.end_lineno,
            DOWNLOAD_REPLACEMENT.splitlines(keepends=True),
        ),
        (
            model_dir_node.lineno - 1,
            model_dir_node.end_lineno,
            MODEL_DIR_REPLACEMENT.splitlines(keepends=True),
        ),
    ]

    for start, end, replacement in sorted(
        replacements,
        key=lambda item: item[0],
        reverse=True,
    ):
        lines[start:end] = replacement

    lines[0:0] = [IMPORTS]
    patched = "".join(lines)
    ast.parse(patched)

    required_patched_tokens = (
        "WHISPER_ALLOW_DOWNLOAD",
        "WHISPER_MODEL_DIR",
        "fcntl.flock",
        "os.replace",
        "_sha256_file",
    )
    for token in required_patched_tokens:
        if token not in patched:
            fail(f"Patched Whisper source is missing token: {token}")

    path.write_text(patched, encoding="utf-8")


if __name__ == "__main__":
    main()
