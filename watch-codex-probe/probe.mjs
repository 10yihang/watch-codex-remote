// Offline-only protocol codec. No transport, filesystem, login, or persistent keys.
import { createHash, createPublicKey, generateKeyPairSync, sign, timingSafeEqual, verify } from 'node:crypto';

export const ORIGIN = 'https://chatgpt.com';
export const RELAY_PATH = '/backend-api/codex/remote/control/client';
export const SESSION_SCOPE = 'remote_control_controller_websocket';
export const SIGNING_DOMAIN = 'codex-device-key-sign-payload/v1';
const SPKI_PREFIX = Buffer.from('3059301306072a8648ce3d020106082a8648ce3d030107034200', 'hex');
const bytes = (value) => Buffer.from(JSON.stringify(value));
export const sha256url = (value) => createHash('sha256').update(value).digest('base64url');
const assert = (condition, message) => { if (!condition) throw new Error(message); };
function text(value, label) {
  assert(typeof value === 'string' && value.trim().length > 0, `${label} must be nonempty`);
  return value;
}
function base64url(value, minimum, exact = false) {
  assert(typeof value === 'string' && /^[A-Za-z0-9_-]+$/.test(value), 'invalid base64url');
  const decoded = Buffer.from(value, 'base64url');
  assert(decoded.toString('base64url') === value, 'noncanonical base64url');
  assert(exact ? decoded.length === minimum : decoded.length >= minimum, 'invalid decoded length');
  return decoded;
}
function future(value, now) {
  assert(Number.isSafeInteger(value) && value > now, 'expired or invalid challenge');
}
function envelope(payload) { return bytes({ domain: SIGNING_DOMAIN, payload }); }
function validateRecord(record) {
  text(record.accountUserId, 'accountUserId');
  text(record.clientId, 'clientId');
  text(record.keyId, 'keyId');
  assert(record.algorithm === 'ecdsa_p256_sha256', 'unsupported signing algorithm');
}
function sessionEpoch(value) {
  const parts = typeof value === 'string'
    && value.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/);
  assert(parts, 'session expiry must be RFC3339');
  const [, year, month, day, hour, minute, second] = parts.map(Number);
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  // Leap-second timestamps are deliberately not accepted by this bounded probe.
  assert(month >= 1 && month <= 12 && day >= 1 && day <= days[month - 1]
    && hour <= 23 && minute <= 59 && second <= 59, 'invalid calendar timestamp');
  return Math.floor(Date.parse(value) / 1000);
}

export function x963ToSpki(point) {
  assert(Buffer.isBuffer(point) && point.length === 65 && point[0] === 4, 'expected uncompressed P-256 public key');
  const der = Buffer.concat([SPKI_PREFIX, point]);
  createPublicKey({ key: der, format: 'der', type: 'spki' });
  return der;
}

export function deviceIdentityHash(record) {
  return sha256url(bytes({
    algorithm: text(record.algorithm, 'algorithm'),
    keyId: text(record.keyId, 'keyId'),
    protectionClass: text(record.protectionClass, 'protectionClass'),
    publicKeySpkiDerBase64: text(record.publicKeySpkiDerBase64, 'public key'),
  }));
}

export function enrollmentPayload(record, challenge, { refresh = false, now } = {}) {
  validateRecord(record);
  assert(Number.isSafeInteger(now), 'explicit current epoch required');
  base64url(challenge.nonce, 32);
  future(challenge.challenge_expires_at, now);
  const path = `${RELAY_PATH}/${refresh ? 'refresh' : 'enroll'}/finish`;
  assert(challenge.purpose === 'remote_control_client_enrollment'
    && challenge.audience === challenge.purpose
    && challenge.account_user_id === record.accountUserId
    && challenge.client_id === record.clientId
    && challenge.target_origin === ORIGIN && challenge.target_path === path,
  'enrollment challenge target or identity mismatch');
  const hash = deviceIdentityHash(record);
  assert((!refresh && challenge.device_identity_hash == null) || challenge.device_identity_hash === hash,
    'device identity hash missing or mismatched');
  return envelope({
    accountUserId: challenge.account_user_id,
    audience: challenge.audience,
    challengeExpiresAt: challenge.challenge_expires_at,
    challengeId: text(challenge.challenge_id, 'challengeId'),
    clientId: challenge.client_id,
    deviceIdentitySha256Base64url: hash,
    nonce: challenge.nonce,
    targetOrigin: challenge.target_origin,
    targetPath: challenge.target_path,
    type: 'remoteControlClientEnrollment',
  });
}

export function connectionPayload(record, session, challenge, now) {
  validateRecord(record);
  assert(Number.isSafeInteger(now), 'explicit current epoch required');
  const expiration = sessionEpoch(session.expires_at);
  future(expiration, now);
  assert(session.account_user_id === record.accountUserId && session.client_id === record.clientId,
    'session identity mismatch');
  assert(JSON.stringify(session.scopes) === JSON.stringify([SESSION_SCOPE]), 'session scope mismatch');
  assert(typeof session.remote_control_token === 'string' && session.remote_control_token.length > 0
    && !/\s/.test(session.remote_control_token), 'malformed session token');
  base64url(challenge.nonce, 32);
  const digest = base64url(challenge.tokenSha256Base64url, 32, true);
  const expected = createHash('sha256').update(session.remote_control_token).digest();
  assert(timingSafeEqual(digest, expected), 'session token digest mismatch');
  assert(challenge.accountUserId === record.accountUserId && challenge.clientId === record.clientId
    && challenge.tokenExpiresAt === expiration, 'connection identity or expiry mismatch');
  assert(challenge.purpose === 'remote_control_client_websocket'
    && challenge.audience === challenge.purpose && challenge.targetOrigin === ORIGIN
    && challenge.targetPath === RELAY_PATH
    && JSON.stringify(challenge.scopes) === JSON.stringify([SESSION_SCOPE]),
  'connection target or scope mismatch');
  return envelope({
    accountUserId: challenge.accountUserId, audience: challenge.audience,
    clientId: challenge.clientId, nonce: challenge.nonce, scopes: challenge.scopes,
    sessionId: text(challenge.sessionId, 'sessionId'), targetOrigin: challenge.targetOrigin,
    targetPath: challenge.targetPath, tokenExpiresAt: challenge.tokenExpiresAt,
    tokenSha256Base64url: challenge.tokenSha256Base64url, type: 'remoteControlClientConnection',
  });
}

// Deliberately unusable as a production enrolled identity: memory-only test key,
// honestly labelled offline_test_only, with no persistence or registration path.
export function ephemeralTestSigner() {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  return {
    publicKey,
    publicKeySpkiDerBase64: publicKey.export({ format: 'der', type: 'spki' }).toString('base64'),
    sign: (payload) => sign('sha256', payload, { key: privateKey, dsaEncoding: 'der' }),
  };
}

export function websocketProof(record, payload, signature) {
  assert(record.algorithm === 'ecdsa_p256_sha256', 'unsupported signing algorithm');
  return {
    type: 'device_key_proof', keyId: record.keyId,
    signatureDerBase64: signature.toString('base64'),
    signedPayloadBase64: payload.toString('base64'), algorithm: record.algorithm,
  };
}

// Cryptographic check only, not a substitute for server authentication or binding.
export function verifySignature(publicKey, proof) {
  return proof.type === 'device_key_proof' && proof.algorithm === 'ecdsa_p256_sha256'
    && verify('sha256', Buffer.from(proof.signedPayloadBase64, 'base64'),
      { key: publicKey, dsaEncoding: 'der' }, Buffer.from(proof.signatureDerBase64, 'base64'));
}

// Constructors only. They never dispatch a command or relax host permissions.
export function rpc(id, method, params = {}) {
  assert(Number.isSafeInteger(id) && id >= 1, 'positive request ID required');
  let body;
  switch (method) {
    case 'initialize': body = { clientInfo: { name: 'watch_codex_offline_probe', title: null, version: '0.1.0' }, capabilities: null }; break;
    case 'thread/list':
      assert(params.cursor == null || typeof params.cursor === 'string', 'invalid cursor');
      body = { limit: 20, cursor: params.cursor ?? null, currentAccountOnly: true }; break;
    case 'thread/read': body = { threadId: text(params.threadId, 'threadId'), includeTurns: false }; break;
    case 'thread/resume': body = { threadId: text(params.threadId, 'threadId'), excludeTurns: true }; break;
    case 'turn/start': body = { threadId: text(params.threadId, 'threadId'), input: [{ type: 'text', text: text(params.text, 'text'), text_elements: [] }] }; break;
    case 'turn/interrupt': body = { threadId: text(params.threadId, 'threadId'), turnId: text(params.turnId, 'turnId') }; break;
    default: throw new Error('unsupported method; this probe never creates or forks a thread');
  }
  return { id, method, params: body };
}

export function clientEnvelope({ clientId, envId, streamId, sequence }, message) {
  assert(Number.isSafeInteger(sequence) && sequence >= 1, 'positive sequence required');
  const result = { type: 'client_message', client_id: text(clientId, 'clientId'), seq_id: sequence,
    stream_id: text(streamId, 'streamId'), env_id: text(envId, 'envId'), skip_history: false, message };
  assert(bytes(result).length <= 100 * 1024, 'offline probe does not implement chunking');
  return result;
}

export function demo() {
  const signer = ephemeralTestSigner();
  const record = { accountUserId: 'offline-account', clientId: 'offline-client', keyId: 'offline-ephemeral-key',
    algorithm: 'ecdsa_p256_sha256', protectionClass: 'offline_test_only', publicKeySpkiDerBase64: signer.publicKeySpkiDerBase64 };
  const session = { account_user_id: record.accountUserId, client_id: record.clientId,
    expires_at: '2033-05-18T03:33:20Z', remote_control_token: 'FAKE_OFFLINE_SESSION_NOT_A_CREDENTIAL', scopes: [SESSION_SCOPE] };
  const challenge = { accountUserId: record.accountUserId, clientId: record.clientId,
    purpose: 'remote_control_client_websocket', audience: 'remote_control_client_websocket',
    nonce: Buffer.alloc(32).toString('base64url'), scopes: [SESSION_SCOPE], sessionId: 'offline-session',
    targetOrigin: ORIGIN, targetPath: RELAY_PATH, tokenExpiresAt: 2000000000,
    tokenSha256Base64url: sha256url(session.remote_control_token) };
  const payload = connectionPayload(record, session, challenge, 1000000000);
  const proof = websocketProof(record, payload, signer.sign(payload));
  const state = { clientId: record.clientId, envId: 'offline-existing-host', streamId: 'offline-stream', sequence: 1 };
  const frames = [rpc(1, 'initialize'), { method: 'initialized' }, rpc(2, 'thread/list'),
    rpc(3, 'thread/read', { threadId: 'offline-existing-thread' }),
    rpc(4, 'thread/resume', { threadId: 'offline-existing-thread' }),
    rpc(5, 'turn/start', { threadId: 'offline-existing-thread', text: 'Offline example only; never sent.' }),
    rpc(6, 'turn/interrupt', { threadId: 'offline-existing-thread', turnId: 'offline-existing-turn' })]
    .map((message, index) => clientEnvelope({ ...state, sequence: index + 1 }, message));
  return { mode: 'OFFLINE_ONLY', signatureVerifiedLocally: verifySignature(signer.publicKey, proof),
    privateKeyPersisted: false, networkCalls: 0, authenticated: false, liveHostTested: false,
    websocketProof: proof, encodedFrames: frames };
}
