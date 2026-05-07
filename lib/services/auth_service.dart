import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

import '../core/config/supabase_keys.dart';
import '../models/user_profile_model.dart';
import '../models/withdrawal_account_model.dart';

class AuthService {
  AuthService(this._client);

  // Super admins — full control center access.
  static const Set<String> _bootstrapSuperAdminEmails = {
    'iagrillojn@hotmail.com',
    'isgrillo.perfectstoneglobal@gmail.com',
  };

  // Regular admins — admin dashboard access only (no super-admin privileges).
  static const Set<String> _bootstrapAdminEmails = {
    'iagrillojn@hotmail.com',
    'isgrillo.perfectstoneglobal@gmail.com',
    'israelgrillo2018@gmail.com',
  };
  static const String _defaultMobileAuthRedirect =
      'avinexescrow://auth-callback';

  final SupabaseClient _client;
  String? _pendingUserNotice;

  bool _isLoopbackHost(String host) {
    final normalized = host.trim().toLowerCase();
    return normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1' ||
        normalized == '[::1]';
  }

  bool _isUnsafeLocalRedirect(Uri uri) {
    if (!uri.hasAuthority) return false;
    return _isLoopbackHost(uri.host);
  }

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  void queueUserNotice(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    _pendingUserNotice = trimmed;
  }

  String? consumeUserNotice() {
    final notice = _pendingUserNotice;
    _pendingUserNotice = null;
    return notice;
  }

  UserProfileModel? _profileFromResponse(dynamic response) {
    if (response is Map) {
      return UserProfileModel.fromMap(Map<String, dynamic>.from(response));
    }
    if (response is List && response.isNotEmpty && response.first is Map) {
      return UserProfileModel.fromMap(
        Map<String, dynamic>.from(response.first as Map),
      );
    }
    return null;
  }

  String? _extractSessionUuidFromAccessToken(String accessToken) {
    try {
      final parts = accessToken.split('.');
      if (parts.length < 2) return null;
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final json = jsonDecode(payload);
      if (json is Map<String, dynamic>) {
        final value = '${json['session_id'] ?? ''}'.trim();
        if (RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
        ).hasMatch(value)) {
          return value;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    print('Supabase URL: \'${SupabaseKeys.url}\'');
    print('Supabase Anon Key: \'${SupabaseKeys.anonKey}\'');
    final response = await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    final session = response.session;
    if (session != null) {
      final sessionUuid = _extractSessionUuidFromAccessToken(session.accessToken);
      await _client.rpc('set_active_session', params: {
        'p_user_id': session.user.id,
        'p_session_uuid': sessionUuid,
      });
    }
    return response;
  }

  Future<bool> hasTransactionPin() async {
    await requireActiveSession();
    final result = await _client.rpc('has_transaction_pin');
    return result == true;
  }

  Future<void> setTransactionPin({required String pin}) async {
    await requireActiveSession();
    final normalizedPin = pin.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(normalizedPin)) {
      throw StateError('PIN must be exactly 4 digits.');
    }
    await _client.rpc('set_transaction_pin', params: {
      'p_pin': normalizedPin,
    });
  }

  Future<void> verifySecurityPin({required String pin}) async {
    await requireActiveSession();
    final normalizedPin = pin.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(normalizedPin)) {
      throw StateError('Enter your 4-digit security PIN.');
    }

    dynamic result;
    try {
      result = await _client.rpc('verify_transaction_pin', params: {
        'p_pin': normalizedPin,
      });
    } on PostgrestException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('temporarily locked')) {
        throw StateError(
          'Too many incorrect PIN attempts. Try again in 30 minutes.',
        );
      }
      rethrow;
    }

    if (result != true) {
      throw StateError('Incorrect PIN. Please try again.');
    }
  }

  /// Checks if the current session is still valid (single session enforcement)
  Future<bool> isCurrentSessionActive() async {
    final session = _client.auth.currentSession;
    debugPrint('DEBUG: isCurrentSessionActive session = [32m$session[0m');
    if (session == null) return false;
    final sessionUuid = _extractSessionUuidFromAccessToken(session.accessToken);
    if (sessionUuid == null) return false;
    final result = await _client.rpc('is_session_active', params: {
      'p_user_id': session.user.id,
      'p_session_uuid': sessionUuid,
    });
    debugPrint('DEBUG: is_session_active RPC result = [32m$result[0m');
    return result == true;
  }

  Uri? _resolvedRedirectUri({String? flow}) {
    final queryParameters = <String, String>{};
    if (flow != null && flow.trim().isNotEmpty) {
      queryParameters['auth_flow'] = flow.trim();
    }

    final configuredRedirect = SupabaseKeys.authRedirectUrl.trim();
    if (configuredRedirect.isNotEmpty) {
      final configuredUri = Uri.parse(configuredRedirect);
      if (_isUnsafeLocalRedirect(configuredUri)) {
        if (!kIsWeb) {
          final mobileUri = Uri.parse(_defaultMobileAuthRedirect);
          return mobileUri.replace(
            queryParameters: {
              ...mobileUri.queryParameters,
              ...queryParameters,
            },
            fragment: '',
          );
        }
        return null;
      }

      return configuredUri.replace(
        queryParameters: {
          ...configuredUri.queryParameters,
          ...queryParameters,
        },
        fragment: '',
      );
    }

    if (!kIsWeb) {
      final mobileUri = Uri.parse(_defaultMobileAuthRedirect);
      return mobileUri.replace(
        queryParameters: {
          ...mobileUri.queryParameters,
          ...queryParameters,
        },
        fragment: '',
      );
    }

    final host = Uri.base.host.toLowerCase();
    final isLocalHost = _isLoopbackHost(host);
    if (isLocalHost) {
      return null;
    }

    return Uri.base.replace(
      queryParameters: queryParameters,
      fragment: '',
    );
  }

  String? _emailRedirectUrl({String? flow}) {
    return _resolvedRedirectUri(flow: flow)?.toString();
  }

  Future<AuthResponse> signUp({
    required String fullName,
    required String email,
    required String password,
  }) {
    return _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': fullName.trim()},
      emailRedirectTo: _emailRedirectUrl(flow: 'email_verification'),
    );
  }

  Future<void> resendVerificationEmail({required String email}) {
    return _client.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
      emailRedirectTo: _emailRedirectUrl(flow: 'email_verification'),
    );
  }

  Future<void> sendPasswordResetEmail({required String email}) {
    return _client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: _emailRedirectUrl(flow: 'password_reset'),
    );
  }

  Future<void> ensureProfile() async {
    final user = currentUser;
    if (user == null) return;

    try {
      await _client.from('profiles').upsert({
        'id': user.id,
        'email': user.email,
        'full_name':
            user.userMetadata?['full_name'] ??
            user.email?.split('@').first ??
            'Avinex User',
      });
    } catch (_) {
      // The SQL setup file creates this automatically; ignore if it is not ready yet.
    }
  }

  Future<Session> requireActiveSession() async {
    final currentSession = _client.auth.currentSession;

    if (currentSession == null) {
      throw StateError(
        'Your session has expired. Please sign in again to continue.',
      );
    }

    final expiresAt = currentSession.expiresAt;
    final nowInSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final shouldRefresh =
        expiresAt != null && expiresAt <= nowInSeconds + 90;

    if (!shouldRefresh) {
      return currentSession;
    }

    try {
      final refreshed = await _client.auth.refreshSession();
      final session = refreshed.session ?? _client.auth.currentSession;

      if (session != null) {
        return session;
      }
    } catch (_) {
      final fallbackSession = _client.auth.currentSession;
      if (fallbackSession != null) {
        return fallbackSession;
      }
    }

    throw StateError(
      'Your session has expired. Please sign in again to continue.',
    );
  }

  Future<UserProfileModel?> getCurrentProfile() async {
    final session = await requireActiveSession();

    final syncedProfile = await syncProfileVerificationStatus();
    if (syncedProfile != null) {
      return syncedProfile;
    }

    final row = await _client
        .from('profiles')
        .select()
        .eq('id', session.user.id)
        .maybeSingle();
    if (row == null) return null;

    return UserProfileModel.fromMap(row);
  }

  Future<UserProfileModel?> syncProfileVerificationStatus() async {
    final session = await requireActiveSession();

    try {
      final response = await _client.rpc('mark_profile_verified_if_eligible');
      return _profileFromResponse(response);
    } on PostgrestException {
      return _fallbackProfileVerificationSync(session);
    }
  }

  Future<UserProfileModel?> _fallbackProfileVerificationSync(
    Session session,
  ) async {
    final currentUser = session.user;
    final emailConfirmedAt = currentUser.toJson()['email_confirmed_at'] as String?;

    await ensureProfile();

    final row = await _client
        .from('profiles')
        .select()
        .eq('id', currentUser.id)
        .maybeSingle();

    if (row == null) {
      return null;
    }

    final profile = UserProfileModel.fromMap(row);
    if (emailConfirmedAt == null || profile.verificationStatus == 'suspended') {
      return profile;
    }

    if (profile.isVerified) {
      return profile;
    }

    final updatedRow = await _client
        .from('profiles')
        .update({
          'verification_status': 'verified',
          'verified_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', currentUser.id)
        .select()
        .maybeSingle();

    if (updatedRow is Map<String, dynamic>) {
      return UserProfileModel.fromMap(updatedRow);
    }

    return profile;
  }

  Future<UserProfileModel> updateProfileDetails({
    required String fullName,
    required String phone,
  }) async {
    final session = await requireActiveSession();
    final user = session.user;

    final metadata = Map<String, dynamic>.from(user.userMetadata ?? {});
    metadata['full_name'] = fullName.trim();
    metadata['phone'] = phone.trim();

    await _client.auth.updateUser(UserAttributes(data: metadata));

    await _client.from('profiles').upsert({
      'id': user.id,
      'email': user.email,
      'full_name': fullName.trim(),
      'phone': phone.trim(),
    });

    final updated = await getCurrentProfile();
    if (updated != null) {
      return updated;
    }

    return UserProfileModel(
      id: user.id,
      email: user.email ?? '',
      fullName: fullName.trim(),
      phone: phone.trim(),
      verificationStatus: 'pending',
    );
  }

  Future<void> updatePassword({required String newPassword}) async {
    await requireActiveSession();
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<Map<String, dynamic>> getUserMetadata() async {
    final session = await requireActiveSession();
    return Map<String, dynamic>.from(session.user.userMetadata ?? {});
  }

  Future<Map<String, dynamic>> updateUserMetadata(
    Map<String, dynamic> metadata,
  ) async {
    await requireActiveSession();
    final response = await _client.auth.updateUser(
      UserAttributes(data: metadata),
    );
    return Map<String, dynamic>.from(
      response.user?.userMetadata ?? _client.auth.currentUser?.userMetadata ?? metadata,
    );
  }

  Future<void> ensureVerifiedAccount({
    String action = 'carry out transactions',
  }) async {
    final session = await requireActiveSession();
    final user = session.user;
    final profile = await getCurrentProfile();
    final emailConfirmedAt = user.toJson()['email_confirmed_at'] as String?;

    if (emailConfirmedAt == null || !(profile?.isVerified ?? false)) {
      throw StateError(
        'Your account must be verified before you can $action.',
      );
    }
  }

  Future<Map<String, dynamic>> lookupVerifiedCounterparty({
    required String email,
  }) async {
    final session = await requireActiveSession();
    final user = session.user;

    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      throw StateError(
        'Enter the seller email attached to a verified Avinex account.',
      );
    }

    if (normalizedEmail == (user.email ?? '').trim().toLowerCase()) {
      throw StateError(
        'Buyer and seller must be two different verified accounts.',
      );
    }

    print('[DEBUG] Supabase RPC lookup_verified_profile for: $normalizedEmail');
    try {
      final response = await _client.rpc(
        'lookup_verified_profile',
        params: {'target_email': normalizedEmail},
      );
      print('[DEBUG] Supabase RPC response: $response');
      if (response is List && response.isNotEmpty) {
        return Map<String, dynamic>.from(response.first as Map);
      }
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      throw StateError(
        'The seller must already have a separate verified Avinex account before any payment can be created.',
      );
    } catch (e, stack) {
      print('[ERROR] Supabase RPC error: $e');
      print('[ERROR] Stack trace: $stack');
      rethrow;
    }
  }

  Future<WithdrawalAccountModel?> getSavedWithdrawalAccount() async {
    final session = await requireActiveSession();
    final raw = session.user.userMetadata?['withdrawal_account'];

    if (raw is Map) {
      return WithdrawalAccountModel.fromMap(Map<String, dynamic>.from(raw));
    }

    return null;
  }

  Future<WithdrawalAccountModel> saveWithdrawalAccount(
    WithdrawalAccountModel account,
  ) async {
    final session = await requireActiveSession();
    final metadata = Map<String, dynamic>.from(session.user.userMetadata ?? {});
    metadata['withdrawal_account'] = account.toMap();

    final response = await _client.auth.updateUser(
      UserAttributes(data: metadata),
    );
    final updatedUser = response.user ?? _client.auth.currentUser;
    final raw = updatedUser?.userMetadata?['withdrawal_account'];

    if (raw is Map) {
      return WithdrawalAccountModel.fromMap(Map<String, dynamic>.from(raw));
    }

    return account;
  }

  Future<void> clearWithdrawalAccount() async {
    final session = await requireActiveSession();
    final metadata = Map<String, dynamic>.from(session.user.userMetadata ?? {});
    metadata.remove('withdrawal_account');
    await _client.auth.updateUser(UserAttributes(data: metadata));
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  @visibleForTesting
  bool isAdminRoleValue(Object? value) => _isAdminRoleValue(value);

  @visibleForTesting
  bool containsAdminClaim(Map<String, dynamic> map) => _containsAdminClaim(map);

  bool _isBootstrapAdminEmail([String? email]) {
    final normalized = (email ?? currentUser?.email ?? '').trim().toLowerCase();
    return normalized.isNotEmpty && _bootstrapAdminEmails.contains(normalized);
  }

  bool _isBootstrapSuperAdminEmail([String? email]) {
    final normalized = (email ?? currentUser?.email ?? '').trim().toLowerCase();
    return normalized.isNotEmpty && _bootstrapSuperAdminEmails.contains(normalized);
  }

  bool _isAdminRoleValue(Object? value) {
    if (value == null) return false;

    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value > 0;
    }

    if (value is String) {
      final normalized = value.trim().toLowerCase();
      const adminRoleTokens = {
        'admin',
        'super_admin',
        'superadmin',
        'ops_admin',
        'opsadmin',
        'operations_admin',
        'support_admin',
        'supportadmin',
        'risk_admin',
        'riskadmin',
      };
      return adminRoleTokens.contains(normalized);
    }

    if (value is Iterable) {
      return value.any(_isAdminRoleValue);
    }

    if (value is Map) {
      return value.values.any(_isAdminRoleValue);
    }

    return false;
  }

  bool _containsAdminClaim(Map<String, dynamic> map) {
    const roleKeys = [
      'role',
      'user_role',
      'profile_role',
      'account_role',
      'roles',
      'permissions',
      'is_admin',
      'admin',
      'isAdmin',
    ];

    for (final key in roleKeys) {
      if (map.containsKey(key) && _isAdminRoleValue(map[key])) {
        return true;
      }
    }

    return false;
  }

  Future<bool> hasAdminAccess() async {
    await requireActiveSession();

    if (_isBootstrapAdminEmail()) {
      return true;
    }

    try {
      final response = await _client.functions.invoke('check-admin-role');
      final data = response.data;
      final allowed = response.status == 200 && data is Map && data['ok'] == true;
      return allowed || _isBootstrapAdminEmail();
    } catch (_) {
      return _isBootstrapAdminEmail();
    }
  }

  Future<bool> hasSuperAdminAccess() async {
    await requireActiveSession();

    if (_isBootstrapSuperAdminEmail()) {
      return true;
    }

    try {
      final response = await _client.functions.invoke(
        'check-admin-role',
        body: {'required_role': 'super_admin'},
      );
      final data = response.data;
      final allowed = response.status == 200 && data is Map && data['ok'] == true;
      return allowed || _isBootstrapSuperAdminEmail();
    } catch (_) {
      return _isBootstrapSuperAdminEmail();
    }
  }
}
