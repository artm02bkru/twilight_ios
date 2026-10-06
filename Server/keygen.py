"""Создать пару ключей подписи лицензий (Ed25519).

Запуск:  python keygen.py
  PUBLIC  — вставить в игру: TwilightNight/Core/License.swift → LicenseConfig.publicKeyBase64
  PRIVATE — только на сервер, в переменную окружения LICENSE_PRIVATE_KEY.
            Никому не показывать и не коммитить в git.
"""
import base64

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

key = Ed25519PrivateKey.generate()
private = key.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw,
                            serialization.NoEncryption())
public = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
print("PUBLIC  (в игру):  ", base64.b64encode(public).decode())
print("PRIVATE (на сервер):", base64.b64encode(private).decode())
