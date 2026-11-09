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
    if candidate != path and candidate.name != "RemoteConnectionController.swift":
        assert "RemoteDeviceKey.create(" not in candidate.read_text(), candidate
assert '[.privateKeyUsage, .userPresence]' in source
assert '"hardware_secure_enclave"' in source
controller = (root / "iPhone/RemoteConnectionController.swift").read_text()
assert controller.count("RemoteDeviceKey.create(") == 1
assert controller.index("func enroll()") < controller.index("RemoteDeviceKey.create(") < controller.index("func pair(")
assert "saved.phase = .enrollmentUnknown; try saved.save()" in controller
print("PASS: explicit-enrollment device-key structural guardrails (not compilation or hardware verification)")
