"""Structural guardrails only; never invokes Keychain or generates a credential."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
path = root / "iPhone/RemoteDeviceKey.swift"
source = path.read_text()
assert all(f"static func {name}(" in source for name in ("create", "load", "sign", "remove"))
assert source.count("SecureEnclave.P256.Signing.PrivateKey(") == 2
assert "kSecAttrAccessibleWhenUnlockedThisDeviceOnly" in source
assert "kSecAttrSynchronizable as String: false" in source
assert "publicKey.derRepresentation == der" in source
assert "stored.identity == expected" in source
assert not any(value in source for value in ("print(", "Logger(", ".pemRepresentation", ".rawRepresentation"))
for candidate in [*root.glob("iPhone/*.swift"), *root.glob("Shared/*.swift")]:
    if candidate != path:
        assert "RemoteDeviceKey.create(" not in candidate.read_text(), candidate
print("PASS: dormant device-key structural guardrails (not compilation or hardware verification)")
