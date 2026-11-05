import test from 'node:test';
import assert from 'node:assert/strict';
import { createPublicKey, verify } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { ORIGIN, RELAY_PATH, SESSION_SCOPE, sha256url, deviceIdentityHash, enrollmentPayload,
  connectionPayload, x963ToSpki, ephemeralTestSigner, websocketProof, verifySignature, rpc, clientEnvelope, demo } from './probe.mjs';

const NOW = 1900000000;
const NONCE = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const record = { accountUserId: 'account-user', algorithm: 'ecdsa_p256_sha256', clientId: 'client-id',
  keyId: 'rcodex_osn_key-id', protectionClass: 'os_protected_nonextractable', publicKeySpkiDerBase64: 'public-key' };
const enrollment = { account_user_id: record.accountUserId, audience: 'remote_control_client_enrollment',
  challenge_expires_at: 2000000000, challenge_id: 'challenge-id', client_id: record.clientId,
  nonce: NONCE, purpose: 'remote_control_client_enrollment', target_origin: ORIGIN, target_path: `${RELAY_PATH}/enroll/finish` };
const session = { account_user_id: record.accountUserId, client_id: record.clientId, expires_at: '2033-05-18T03:33:20Z',
  remote_control_token: 'FAKE_OFFLINE_SESSION_NOT_A_CREDENTIAL', scopes: [SESSION_SCOPE] };
const challenge = { accountUserId: record.accountUserId, audience: 'remote_control_client_websocket', clientId: record.clientId,
  nonce: NONCE, purpose: 'remote_control_client_websocket', scopes: [SESSION_SCOPE], sessionId: 'session-id',
  targetOrigin: ORIGIN, targetPath: RELAY_PATH, tokenExpiresAt: 2000000000, tokenSha256Base64url: sha256url(session.remote_control_token) };
const state = { clientId: 'client-id', envId: 'existing-env', streamId: 'stream-id', sequence: 1 };

test('identity hash matches rcodex golden field order', () => {
  assert.equal(deviceIdentityHash(record), 'Vq0Okx8un5zFrEAPEVFV4cTunCI8P0dD-8Ik6CmmBpI');
});

test('enrollment payload matches the pinned upstream golden bytes', () => {
  const source = readFileSync(new URL('./upstream/tests/protocol_contract.rs', import.meta.url), 'utf8');
  const expected = source.match(/let expected = r#"(\{"domain".*?remoteControlClientEnrollment.*?\})"#/)[1]
    .replace('__HASH__', 'Vq0Okx8un5zFrEAPEVFV4cTunCI8P0dD-8Ik6CmmBpI');
  assert.equal(enrollmentPayload(record, enrollment, { now: NOW }).toString(), expected);
});

test('connection payload matches the pinned upstream golden bytes', () => {
  const source = readFileSync(new URL('./upstream/tests/protocol_contract.rs', import.meta.url), 'utf8');
  const expected = source.match(/let expected = r#"(\{"domain".*?remoteControlClientConnection.*?\})"#/)[1]
    .replace(`"tokenSha256Base64url":"${NONCE}"`, `"tokenSha256Base64url":"${challenge.tokenSha256Base64url}"`);
  assert.equal(connectionPayload(record, session, challenge, NOW).toString(), expected);
});

test('refresh requires matching server identity hash and a refresh target', () => {
  const refresh = { ...enrollment, target_path: `${RELAY_PATH}/refresh/finish` };
  assert.throws(() => enrollmentPayload(record, refresh, { now: NOW, refresh: true }), /identity hash/);
  assert.throws(() => enrollmentPayload(record, { ...refresh, device_identity_hash: 'wrong' }, { now: NOW, refresh: true }));
  assert.ok(enrollmentPayload(record, { ...refresh, device_identity_hash: deviceIdentityHash(record) }, { now: NOW, refresh: true }));
});

test('enrollment rejects wrong account, client, purpose, audience and destination', () => {
  for (const field of ['account_user_id', 'client_id', 'purpose', 'audience', 'target_origin', 'target_path']) {
    assert.throws(() => enrollmentPayload(record, { ...enrollment, [field]: 'wrong' }, { now: NOW }), undefined, field);
  }
});

test('missing local identity and ambiguous dates fail closed', () => {
  for (const field of ['accountUserId', 'clientId', 'keyId', 'algorithm']) {
    assert.throws(() => connectionPayload({ ...record, [field]: undefined }, session, challenge, NOW));
    assert.throws(() => enrollmentPayload({ ...record, [field]: undefined }, enrollment, { now: NOW }));
  }
  assert.throws(() => connectionPayload(record, { ...session, expires_at: 'May 18 2033 03:33:20' }, challenge, NOW), /RFC3339/);
});

test('signing rejects expired challenges and sessions at the boundary', () => {
  assert.throws(() => enrollmentPayload(record, { ...enrollment, challenge_expires_at: NOW }, { now: NOW }), /expired/);
  assert.throws(() => connectionPayload(record, session, challenge, 2000000000), /expired/);
  assert.throws(() => connectionPayload(record, { ...session, expires_at: 'bad-date' }, challenge, NOW));
});

test('expiry parser rejects normalized invalid dates and matches chrono fractional seconds', () => {
  for (const expires_at of ['2033-02-31T03:33:20Z', '2033-05-18T24:00:00Z', '2033-05-18T03:33:60Z']) {
    assert.throws(() => connectionPayload(record, { ...session, expires_at }, challenge, NOW));
  }
  assert.deepEqual(connectionPayload(record, { ...session, expires_at: '2033-05-18T03:33:20.123Z' }, challenge, NOW),
    connectionPayload(record, session, challenge, NOW));
});

test('nonce and digest validation rejects padding, short and noncanonical bytes', () => {
  for (const nonce of ['', 'AA', NONCE + '=', NONCE.slice(0, -1) + 'B']) {
    assert.throws(() => connectionPayload(record, session, { ...challenge, nonce }, NOW));
  }
  for (const digest of ['', NONCE + '=', 'AAAA']) {
    assert.throws(() => connectionPayload(record, session, { ...challenge, tokenSha256Base64url: digest }, NOW));
  }
});

test('connection binds signature to exact session, account, client, scope and relay', () => {
  for (const field of ['accountUserId', 'clientId', 'audience', 'purpose', 'targetOrigin', 'targetPath']) {
    assert.throws(() => connectionPayload(record, session, { ...challenge, [field]: 'wrong' }, NOW), undefined, field);
  }
  assert.throws(() => connectionPayload(record, session, { ...challenge, tokenExpiresAt: 2000000001 }, NOW));
  assert.throws(() => connectionPayload(record, session, { ...challenge, scopes: [SESSION_SCOPE, 'extra'] }, NOW));
  assert.throws(() => connectionPayload(record, session, { ...challenge, tokenSha256Base64url: NONCE }, NOW), /digest mismatch/);
  for (const changed of [{ account_user_id: 'wrong' }, { client_id: 'wrong' }, { scopes: [] }, { remote_control_token: 'has whitespace' }]) {
    assert.throws(() => connectionPayload(record, { ...session, ...changed }, challenge, NOW));
  }
});

test('ephemeral P-256 key exports expected SPKI and DER signature verifies', () => {
  const signer = ephemeralTestSigner();
  const exported = Buffer.from(signer.publicKeySpkiDerBase64, 'base64');
  const jwk = signer.publicKey.export({ format: 'jwk' });
  const point = Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x, 'base64url'), Buffer.from(jwk.y, 'base64url')]);
  assert.deepEqual(x963ToSpki(point), exported);
  assert.equal(exported.length, 91);
  const payload = connectionPayload(record, session, challenge, NOW);
  const signature = signer.sign(payload);
  assert.equal(signature[0], 0x30);
  const publicKey = createPublicKey({ key: exported, format: 'der', type: 'spki' });
  assert.ok(verify('sha256', payload, { key: publicKey, dsaEncoding: 'der' }, signature));
  assert.equal(verify('sha256', Buffer.concat([payload, Buffer.from('tampered')]), publicKey, signature), false);
});

test('SPKI conversion rejects compressed or malformed public keys', () => {
  assert.throws(() => x963ToSpki(Buffer.alloc(33)));
  assert.throws(() => x963ToSpki(Buffer.alloc(65)));
});

test('WebSocket proof uses standard base64 and rejects tampered signatures', () => {
  const signer = ephemeralTestSigner();
  const payload = connectionPayload(record, session, challenge, NOW);
  const proof = websocketProof(record, payload, signer.sign(payload));
  assert.equal(verifySignature(signer.publicKey, proof), true);
  assert.deepEqual(Object.keys(proof), ['type', 'keyId', 'signatureDerBase64', 'signedPayloadBase64', 'algorithm']);
  assert.deepEqual(Buffer.from(proof.signedPayloadBase64, 'base64'), payload);
  const damaged = Buffer.from(proof.signatureDerBase64, 'base64'); damaged[damaged.length - 1] ^= 1;
  assert.equal(verifySignature(signer.publicKey, { ...proof, signatureDerBase64: damaged.toString('base64') }), false);
  assert.equal(verifySignature(signer.publicKey, { ...proof, algorithm: 'wrong' }), false);
});

test('initialize and initialized use the App Server shapes', () => {
  assert.deepEqual(rpc(1, 'initialize'), { id: 1, method: 'initialize', params: {
    clientInfo: { name: 'watch_codex_offline_probe', title: null, version: '0.1.0' }, capabilities: null } });
  assert.deepEqual(demo().encodedFrames[1].message, { method: 'initialized' });
});

test('thread list preserves opaque cursor and scopes local discovery', () => {
  assert.deepEqual(rpc(2, 'thread/list', { cursor: 'opaque cursor' }).params,
    { limit: 20, cursor: 'opaque cursor', currentAccountOnly: true });
});

test('read and resume target existing thread without overriding permissions', () => {
  assert.deepEqual(rpc(3, 'thread/read', { threadId: 'existing-thread' }).params,
    { threadId: 'existing-thread', includeTurns: false });
  assert.deepEqual(rpc(4, 'thread/resume', { threadId: 'existing-thread', approvalPolicy: 'never' }).params,
    { threadId: 'existing-thread', excludeTurns: true });
});

test('turn start preserves text_elements and interrupt requires exact turn', () => {
  assert.deepEqual(rpc(5, 'turn/start', { threadId: 'existing-thread', text: '你好 👋' }).params,
    { threadId: 'existing-thread', input: [{ type: 'text', text: '你好 👋', text_elements: [] }] });
  assert.deepEqual(rpc(6, 'turn/interrupt', { threadId: 'existing-thread', turnId: 'existing-turn' }).params,
    { threadId: 'existing-thread', turnId: 'existing-turn' });
  assert.throws(() => rpc(6, 'turn/interrupt', { threadId: 'existing-thread' }));
});

test('probe cannot construct thread creation, forks, unknown methods or invalid IDs', () => {
  for (const method of ['thread/start', 'thread/fork', 'anything']) assert.throws(() => rpc(1, method));
  assert.throws(() => rpc(0, 'thread/list'));
  assert.throws(() => rpc(1, 'thread/read', { threadId: '' }));
});

test('relay v3 envelope preserves route, stream and sequence', () => {
  const request = rpc(1, 'thread/read', { threadId: 'existing-thread' });
  assert.deepEqual(clientEnvelope(state, request), { type: 'client_message', client_id: 'client-id', seq_id: 1,
    stream_id: 'stream-id', env_id: 'existing-env', skip_history: false, message: request });
  assert.throws(() => clientEnvelope({ ...state, sequence: 0 }, request));
  assert.throws(() => clientEnvelope(state, { text: 'x'.repeat(100 * 1024) }), /chunking/);
});

test('demo explicitly reports offline-only and never claims real authorization', () => {
  const report = demo();
  assert.equal(report.mode, 'OFFLINE_ONLY');
  assert.equal(report.signatureVerifiedLocally, true);
  assert.equal(report.privateKeyPersisted, false);
  assert.equal(report.networkCalls, 0);
  assert.equal(report.authenticated, false);
  assert.equal(report.liveHostTested, false);
  assert.deepEqual(report.encodedFrames.map(frame => frame.seq_id), [1, 2, 3, 4, 5, 6, 7]);
});
