class AuthState {
  final bool isAuthenticated;
  final String enteredPin;
  final bool isLoading;
  final String? errorMessage;
  final int failedAttempts;
  final bool isLockedOut;
  final int lockoutRemainingSeconds;
  final String? token;

  const AuthState({
    this.isAuthenticated = false,
    this.enteredPin = '',
    this.isLoading = false,
    this.errorMessage,
    this.failedAttempts = 0,
    this.isLockedOut = false,
    this.lockoutRemainingSeconds = 0,
    this.token,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    String? enteredPin,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    int? failedAttempts,
    bool? isLockedOut,
    int? lockoutRemainingSeconds,
    String? token,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      enteredPin: enteredPin ?? this.enteredPin,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      failedAttempts: failedAttempts ?? this.failedAttempts,
      isLockedOut: isLockedOut ?? this.isLockedOut,
      lockoutRemainingSeconds: lockoutRemainingSeconds ?? this.lockoutRemainingSeconds,
      token: token ?? this.token,
    );
  }
}
