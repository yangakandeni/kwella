/// Represents the different authentication states of the application.
enum KwellaAuthStatus {
  unauthenticated,
  authenticating,
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

  const KwellaAuthState({
    required this.status,
    this.error,
    this.userId,
    this.email,
    this.role,
  });

  /// Factory for the initial unauthenticated state.
  const KwellaAuthState.initial()
      : status = KwellaAuthStatus.unauthenticated,
        error = null,
        userId = null,
        email = null,
        role = null;

  /// Creates a copy of this state but with the given fields replaced with the new values.
  KwellaAuthState copyWith({
    KwellaAuthStatus? status,
    String? error,
    String? userId,
    String? email,
    String? role,
    bool clearError = false,
    bool clearUser = false,
  }) {
    return KwellaAuthState(
      status: status ?? this.status,
      error: clearError ? null : (error ?? this.error),
      userId: clearUser ? null : (userId ?? this.userId),
      email: clearUser ? null : (email ?? this.email),
      role: clearUser ? null : (role ?? this.role),
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
          role == other.role;

  @override
  int get hashCode => Object.hash(status, error, userId, email, role);

  @override
  String toString() {
    return 'KwellaAuthState(status: $status, error: $error, userId: $userId, email: $email, role: $role)';
  }
}
