"""Tiny storage layer so the same ingest code writes to S3 or a local folder."""
from __future__ import annotations

import json
import shutil
from pathlib import Path


class LocalStorage:
    def __init__(self, root: str):
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)

    def put_file(self, local: Path, key: str) -> None:
        dest = self.root / key
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(local, dest)

    def read_json(self, key: str) -> dict | None:
        path = self.root / key
        return json.loads(path.read_text()) if path.exists() else None

    def write_json(self, key: str, obj: dict) -> None:
        path = self.root / key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(obj, indent=2))


class S3Storage:
    def __init__(self, uri: str):
        import boto3  # imported here so local dev doesn't need AWS set up

        bucket_and_prefix = uri.removeprefix("s3://")
        self.bucket, _, prefix = bucket_and_prefix.partition("/")
        self.prefix = prefix.strip("/")
        self.s3 = boto3.client("s3")

    def _key(self, key: str) -> str:
        return f"{self.prefix}/{key}" if self.prefix else key

    def put_file(self, local: Path, key: str) -> None:
        self.s3.upload_file(str(local), self.bucket, self._key(key))

    def read_json(self, key: str) -> dict | None:
        try:
            body = self.s3.get_object(Bucket=self.bucket, Key=self._key(key))["Body"].read()
        except self.s3.exceptions.NoSuchKey:
            return None
        return json.loads(body)

    def write_json(self, key: str, obj: dict) -> None:
        self.s3.put_object(Bucket=self.bucket, Key=self._key(key), Body=json.dumps(obj, indent=2).encode(), ContentType="application/json")


def open_storage(dest: str):
    if dest.startswith("s3://"):
        return S3Storage(dest)
    if dest.startswith("local:"):
        return LocalStorage(dest.removeprefix("local:"))
    raise ValueError("dest must start with s3:// or local:")
