/// Represents the different authentication states of the application.
enum KwellaAuthStatus {
  unauthenticated,
  authenticating,

  /// A Cognito CUSTOM_AUTH challenge (OTP) has been issued and is awaiting
  /// the code the user enters on the OTP screen.
  otpRequired,
  authenticated,
  failure,
}

/// Holds the authentication state of the user and current session status.
class KwellaAuthState {
  final KwellaAuthStatus status;
  final String? error;
  final String? userId;
  final String? email;
  final String? role;

  /// The opaque Cognito `Session` token returned by `InitiateAuth` for the
  /// `CUSTOM_AUTH` flow, required as input to `RespondToAuthChallenge`.
  final String? cognitoSession;

  /// The phone number entered on the phone-entry screen, carried forward so
  /// the OTP screen can display it and resend the code.
  final String? pendingPhoneNumber;

  const KwellaAuthState({
    required this.status,
    this.error,
    this.userId,
    this.email,
    this.role,
    this.cognitoSession,
    this.pendingPhoneNumber,
  });

  /// Factory for the initial unauthenticated state.
  const KwellaAuthState.initial()
      : status = KwellaAuthStatus.unauthenticated,
        error = null,
        userId = null,
        email = null,
        role = null,
        cognitoSession = null,
        pendingPhoneNumber = null;

  /// Creates a copy of this state but with the given fields replaced with the new values.
  KwellaAuthState copyWith({
    KwellaAuthStatus? status,
    String? error,
    String? userId,
    String? email,
    String? role,
    String? cognitoSession,
    String? pendingPhoneNumber,
    bool clearError = false,
    bool clearUser = false,
    bool clearChallenge = false,
  }) {
    return KwellaAuthState(
      status: status ?? this.status,
      error: clearError ? null : (error ?? this.error),
      userId: clearUser ? null : (userId ?? this.userId),
      email: clearUser ? null : (email ?? this.email),
      role: clearUser ? null : (role ?? this.role),
      cognitoSession:
          clearChallenge ? null : (cognitoSession ?? this.cognitoSession),
      pendingPhoneNumber: clearChallenge
          ? null
          : (pendingPhoneNumber ?? this.pendingPhoneNumber),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KwellaAuthState &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          error == other.error &&
          userId == other.userId &&
          email == other.email &&
          role == other.role &&
          cognitoSession == other.cognitoSession &&
          pendingPhoneNumber == other.pendingPhoneNumber;

  @override
  int get hashCode => Object.hash(
        status,
        error,
        userId,
        email,
        role,
        cognitoSession,
        pendingPhoneNumber,
      );

  @override
  String toString() {
    return 'KwellaAuthState(status: $status, error: $error, userId: $userId, email: $email, role: $role, cognitoSession: $cognitoSession, pendingPhoneNumber: $pendingPhoneNumber)';
  }
}
