/// Production environment configuration for the Kwella platform.
///
/// These values are sourced from `.env.production` after the Phase 2 Terraform
/// apply that provisioned the af-south-1 AWS stack. They are embedded here as
/// compile-time constants rather than a runtime dotenv file so that:
///
/// * The Flutter engine can tree-shake unused constants.
/// * There is a single authoritative source of truth in the core package.
/// * Consumer packages (rider app, driver app) never need to hard-code endpoints.
///
/// **Security note**: Only non-secret public identifiers are stored here.
/// The Cognito public client (`clientId`) has no client secret by design.
/// Access tokens and refresh tokens are persisted in the [TokenVault] using
/// `flutter_secure_storage` and are never stored in plain text.
library;

// ── Cognito ────────────────────────────────────────────────────────────────

/// The af-south-1 Cognito User Pool identifier.
///
/// Used by the Cognito SDK and for constructing the JWKS endpoint when
/// performing token verification on the client side.
const String kCognitoUserPoolId = 'af-south-1_nanvvqqZO';

/// The public Cognito app-client identifier.
///
/// This value is safe to embed in client-side code. Public app-clients in
/// Cognito do not have a client secret, so exposure carries no security risk.
const String kCognitoClientId = '6enltlvcl8569tt1r49rnfr354';

/// The standard Cognito regional JSON endpoint used for `InitiateAuth` and
/// `REFRESH_TOKEN_AUTH` POST requests.
///
/// Format: `https://cognito-idp.<region>.amazonaws.com/`
const String kCognitoEndpoint = 'https://cognito-idp.af-south-1.amazonaws.com/';

// ── API Gateway ────────────────────────────────────────────────────────────

/// The AWS API Gateway v2 WebSocket stage URL for the Kwella production
/// bidding engine.
///
/// Connect by appending `?Authorization=<accessToken>` as a query parameter
/// so the `$connect` route authorizer can validate the Cognito JWT.
const String kWebSocketEndpointUrl =
    'wss://oronlku519.execute-api.af-south-1.amazonaws.com/production';

/// The base URL for the Kwella HTTP REST API (AWS API Gateway v2 HTTP stage).
///
/// Append resource paths (e.g. `/rides`, `/bids`) when constructing Dio
/// request paths.
const String kHttpApiEndpoint =
    'https://dbmi2nczz8.execute-api.af-south-1.amazonaws.com/';

// ── Environment snapshot ───────────────────────────────────────────────────

/// A convenience class that groups all production environment tokens.
///
/// Prefer using the top-level `k*` constants directly in application code.
/// Use [KwellaEnvironment] when you need to pass the full configuration as a
/// single injectable object — for example in tests that override specific
/// values.
///
/// ### Overriding in tests
/// ```dart
/// final testEnv = KwellaEnvironment(
///   cognitoUserPoolId: 'us-east-1_testPool',
///   cognitoClientId: 'testClientId',
///   cognitoEndpoint: 'https://cognito-idp.us-east-1.amazonaws.com/',
///   webSocketEndpointUrl: 'wss://mock.execute-api.test.com/staging',
///   httpApiEndpoint: 'https://mock.execute-api.test.com/',
/// );
/// ```
class KwellaEnvironment {
  /// The Cognito User Pool ID.
  final String cognitoUserPoolId;

  /// The public Cognito app-client ID.
  final String cognitoClientId;

  /// The Cognito regional JSON endpoint for auth flows.
  final String cognitoEndpoint;

  /// The API Gateway v2 WebSocket stage URL.
  final String webSocketEndpointUrl;

  /// The API Gateway v2 HTTP base URL.
  final String httpApiEndpoint;

  const KwellaEnvironment({
    this.cognitoUserPoolId = kCognitoUserPoolId,
    this.cognitoClientId = kCognitoClientId,
    this.cognitoEndpoint = kCognitoEndpoint,
    this.webSocketEndpointUrl = kWebSocketEndpointUrl,
    this.httpApiEndpoint = kHttpApiEndpoint,
  });

  /// The default singleton backed by production constants.
  static const KwellaEnvironment production = KwellaEnvironment();
}
