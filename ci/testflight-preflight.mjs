import { createPrivateKey, sign } from 'node:crypto';

const required = ['APPLE_TEAM_ID', 'ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_KEY_P8'];
const missing = required.filter(name => !process.env[name]?.trim());
if (missing.length) {
  console.error(`TestFlight blocked: missing repository secrets: ${missing.join(', ')}`);
  process.exit(1);
}
const b64 = value => Buffer.from(JSON.stringify(value)).toString('base64url');
try {
  const now = Math.floor(Date.now() / 1000);
  const header = b64({ alg: 'ES256', kid: process.env.ASC_KEY_ID, typ: 'JWT' });
  const claims = b64({ iss: process.env.ASC_ISSUER_ID, iat: now, exp: now + 120, aud: 'appstoreconnect-v1' });
  const input = `${header}.${claims}`;
  const key = createPrivateKey(process.env.ASC_KEY_P8);
  const signature = sign('sha256', Buffer.from(input), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
  const response = await fetch('https://api.appstoreconnect.apple.com/v1/apps?filter%5BbundleId%5D=ae.barq.football&limit=1', {
    headers: { Authorization: `Bearer ${input}.${signature}` }, signal: AbortSignal.timeout(30000), redirect: 'error'
  });
  if (!response.ok) {
    console.error(`TestFlight blocked: App Store Connect returned HTTP ${response.status}. Check API key permissions and account agreements.`);
    process.exit(1);
  }
  const body = await response.json();
  if (!body.data?.length) {
    console.error('TestFlight blocked: no accessible app record for ae.barq.football. Create or grant access to the FOTIQ app record.');
    process.exit(1);
  }
  console.log('App Store Connect authentication and FOTIQ app access verified. Signing and upload still require a successful archive.');
} catch {
  console.error('TestFlight blocked: key parsing or secure App Store Connect connection failed. Secret values are not logged.');
  process.exit(1);
}
