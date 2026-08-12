#!/usr/bin/python3

import hashlib
import io
import os
from pathlib import Path
import tempfile
import urllib.request

import filelock
import more_itertools
import numba
import numpy
import tiktoken
import torch
import tqdm
import whisper
from whisper.tokenizer import LANGUAGES, get_tokenizer


EXPECTED_WHISPER_VERSION = "20250625"


def fail(message: str) -> None:
    raise RuntimeError(message)


def test_runtime_dependencies() -> None:
    if whisper.__version__ != EXPECTED_WHISPER_VERSION:
        fail(f"Unexpected Whisper version: {whisper.__version__}")

    if torch.version.cuda is not None:
        fail("full-cpu must use a CPU-only PyTorch build")

    for language in ("en", "zh", "ja"):
        if language not in LANGUAGES:
            fail(f"Whisper language is unavailable: {language}")

    get_tokenizer(
        multilingual=True,
        language="zh",
        task="transcribe",
    )

    dependencies = (
        filelock,
        more_itertools,
        numba,
        numpy,
        tiktoken,
        tqdm,
    )
    if any(module is None for module in dependencies):
        fail("Whisper runtime dependency check failed")


def test_no_network_when_model_is_missing() -> None:
    with tempfile.TemporaryDirectory() as model_dir:
        os.environ["WHISPER_MODEL_DIR"] = model_dir
        os.environ["WHISPER_ALLOW_DOWNLOAD"] = "0"

        original_urlopen = urllib.request.urlopen

        def reject_network(*args, **kwargs):
            raise AssertionError(
                "Whisper attempted network access while downloads were disabled"
            )

        urllib.request.urlopen = reject_network
        whisper.urllib.request.urlopen = reject_network

        try:
            try:
                whisper.load_model(
                    "tiny",
                    device="cpu",
                )
            except RuntimeError as exc:
                message = str(exc)
                if "Automatic model downloads are disabled" not in message:
                    raise
                expected_path = os.path.join(model_dir, "tiny.pt")
                if expected_path not in message:
                    fail(
                        "Missing-model error does not contain the expected path"
                    )
            else:
                fail("Missing model did not stop model loading")
        finally:
            urllib.request.urlopen = original_urlopen
            whisper.urllib.request.urlopen = original_urlopen


def test_local_checksum_policy() -> None:
    payload = b"recoll-container-whisper-selftest"
    expected_sha256 = hashlib.sha256(payload).hexdigest()

    with tempfile.TemporaryDirectory() as model_dir:
        model_path = Path(model_dir) / "selftest.pt"
        model_path.write_bytes(payload)

        model_url = (
            "https://example.invalid/models/"
            f"{expected_sha256}/selftest.pt"
        )

        os.environ["WHISPER_ALLOW_DOWNLOAD"] = "0"

        returned = whisper._download(
            model_url,
            model_dir,
            False,
        )

        if Path(returned) != model_path:
            fail("Valid local model path was not returned")

        model_path.write_bytes(b"invalid")

        try:
            whisper._download(
                model_url,
                model_dir,
                False,
            )
        except RuntimeError as exc:
            if "checksum mismatch" not in str(exc):
                raise
        else:
            fail("Invalid local model checksum was accepted")


def test_allowed_download_policy() -> None:
    payload = b"recoll-container-whisper-download-selftest"
    expected_sha256 = hashlib.sha256(payload).hexdigest()
    model_url = (
        "https://example.invalid/models/"
        f"{expected_sha256}/download-test.pt"
    )

    class Response(io.BytesIO):
        def info(self):
            return {"Content-Length": str(len(payload))}

    with tempfile.TemporaryDirectory() as model_dir:
        os.environ["WHISPER_ALLOW_DOWNLOAD"] = "1"

        original_urlopen = urllib.request.urlopen

        def provide_model(*args, **kwargs):
            return Response(payload)

        urllib.request.urlopen = provide_model
        whisper.urllib.request.urlopen = provide_model

        try:
            returned = whisper._download(
                model_url,
                model_dir,
                False,
            )
        finally:
            urllib.request.urlopen = original_urlopen
            whisper.urllib.request.urlopen = original_urlopen

        model_path = Path(model_dir) / "download-test.pt"
        if Path(returned) != model_path:
            fail("Downloaded model path was not returned")
        if model_path.read_bytes() != payload:
            fail("Downloaded model content does not match")
        if list(Path(model_dir).glob("*.part")):
            fail("Partial model file remained after a successful download")


def main() -> None:
    test_runtime_dependencies()
    test_no_network_when_model_is_missing()
    test_local_checksum_policy()
    test_allowed_download_policy()
    print("Whisper CPU self-test passed")


if __name__ == "__main__":
    main()
