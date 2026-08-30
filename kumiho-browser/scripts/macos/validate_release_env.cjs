const REQUIRED_SIGNING_VARIABLES = [
  'APPLE_CERTIFICATE_BASE64',
  'APPLE_CERTIFICATE_PASSWORD',
  'APPLE_ID',
  'APPLE_APP_PASSWORD',
  'APPLE_TEAM_ID',
];

function validateReleaseEnvironment(environment) {
  const requirement = environment.REQUIRE_MACOS_SIGNING || '0';
  if (requirement !== '0' && requirement !== '1') {
    throw new Error('REQUIRE_MACOS_SIGNING must be 0 or 1');
  }

  const hasSigningConfiguration = REQUIRED_SIGNING_VARIABLES.some(
    (name) => Boolean(environment[name]),
  );
  if (requirement === '0' && !hasSigningConfiguration) return;

  const missing = REQUIRED_SIGNING_VARIABLES.filter(
    (name) => !environment[name],
  );
  if (missing.length > 0) {
    throw new Error(
      `macOS signing configuration is incomplete; missing: ${missing.join(', ')}`,
    );
  }
}

if (require.main === module) {
  try {
    validateReleaseEnvironment(process.env);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

module.exports = {
  validateReleaseEnvironment,
};
