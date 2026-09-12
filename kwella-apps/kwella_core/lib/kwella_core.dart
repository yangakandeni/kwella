/// Kwella core library – design tokens, auth, networking, and shared models.
library;

// ── Config ────────────────────────────────────────────────────────────────
export 'src/config/environment.dart';

// ── Auth ──────────────────────────────────────────────────────────────────
export 'src/kwella_core_base.dart';
export 'src/auth/auth_placeholder.dart';
export 'src/auth/auth_state.dart';
export 'src/auth/token_vault.dart';
export 'src/auth/auth_notifier.dart';

// ── Network ───────────────────────────────────────────────────────────────
export 'src/network/network_placeholder.dart';
export 'src/network/websocket_gateway.dart';
export 'src/network/aws_error_interceptor.dart';
export 'src/network/bidding_events.dart';
export 'src/network/event_multiplexer.dart';

// ── Fare ──────────────────────────────────────────────────────────────────
export 'src/fare/kwella_fare_estimator.dart';

// ── Location ──────────────────────────────────────────────────────────────
export 'src/location/directions_service.dart';

// ── Models ────────────────────────────────────────────────────────────────
export 'src/models/models_placeholder.dart';
export 'src/models/driver_bid.dart';

// ── Theme ─────────────────────────────────────────────────────────────────
export 'src/theme/kwella_colors.dart';
export 'src/theme/kwella_theme.dart';

