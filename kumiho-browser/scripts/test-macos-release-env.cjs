const assert = require('node:assert/strict');

const {
  validateReleaseEnvironment,
} = require('./macos/validate_release_env.cjs');

const completeSigningEnvironment = {
  REQUIRE_MACOS_SIGNING: '1',
  APPLE_CERTIFICATE_BASE64: 'certificate',
  APPLE_CERTIFICATE_PASSWORD: 'certificate-password',
  APPLE_ID: 'developer@example.com',
  APPLE_APP_PASSWORD: 'app-password',
  APPLE_TEAM_ID: 'TEAMID1234',
};

assert.doesNotThrow(() => validateReleaseEnvironment({}));
assert.doesNotThrow(() =>
  validateReleaseEnvironment(completeSigningEnvironment),
);

assert.throws(
  () => validateReleaseEnvironment({ REQUIRE_MACOS_SIGNING: '1' }),
  /APPLE_CERTIFICATE_BASE64, APPLE_CERTIFICATE_PASSWORD, APPLE_ID, APPLE_APP_PASSWORD, APPLE_TEAM_ID/,
);

assert.throws(
  () =>
    validateReleaseEnvironment({
      APPLE_CERTIFICATE_BASE64: 'certificate',
    }),
  /APPLE_CERTIFICATE_PASSWORD, APPLE_ID, APPLE_APP_PASSWORD, APPLE_TEAM_ID/,
);

assert.throws(
  () => validateReleaseEnvironment({ REQUIRE_MACOS_SIGNING: 'sometimes' }),
  /REQUIRE_MACOS_SIGNING must be 0 or 1/,
);

console.log('macOS release environment checks passed');
