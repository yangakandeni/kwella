import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kwella_core/kwella_core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Kwella Driver – Profile & Vehicle Setup Screen
//
// Short one-time form collecting the driver's display name and vehicle
// details (CATA sticker, make, model, color, license plate), submitted via
// the existing /identity/upsert and /identity/vehicle endpoints. This is the
// only place a driver's name and vehicle color/plate reach DynamoDB — without
// it, the rider's tripMatchConfirmed event has nothing to display.
// ─────────────────────────────────────────────────────────────────────────────

class DriverProfileSetupScreen extends ConsumerStatefulWidget {
  const DriverProfileSetupScreen({super.key});

  @override
  ConsumerState<DriverProfileSetupScreen> createState() =>
      _DriverProfileSetupScreenState();
}

class _DriverProfileSetupScreenState
    extends ConsumerState<DriverProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _cataStickerController = TextEditingController();
  final _makeController = TextEditingController();
  final _modelController = TextEditingController();
  final _colorController = TextEditingController();
  final _licensePlateController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _cataStickerController.dispose();
    _makeController.dispose();
    _modelController.dispose();
    _colorController.dispose();
    _licensePlateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final authState = ref.read(kwellaAuthNotifierProvider);
    final userId = authState.userId;
    if (userId == null) {
      setState(() => _errorMessage = 'You must be signed in to continue.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final tokenVault = TokenVault();
    final accessToken = await tokenVault.readAccessToken();
    final idToken = await tokenVault.readIdToken();
    final phoneNumber = idToken != null
        ? (_decodeJwtPayload(idToken)?['phone_number'] as String?)
        : null;
    if (phoneNumber == null) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Could not read your phone number from your session.';
      });
      return;
    }

    final dio = Dio(
      BaseOptions(baseUrl: KwellaEnvironment.current.httpApiEndpoint),
    );
    dio.interceptors.add(
      AwsErrorInterceptor(
        tokenVault: tokenVault,
        onRefreshNeeded: () =>
            ref.read(kwellaAuthNotifierProvider.notifier).refreshSession(),
      ),
    );

    final authHeader = {
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
    };

    try {
      await dio.post<void>(
        'identity/upsert',
        data: {
          'user_id': userId,
          'role': 'DRIVER',
          'phone': phoneNumber,
          'name': _nameController.text.trim(),
          'assigned_cata_sticker': _cataStickerController.text.trim(),
        },
        options: Options(headers: authHeader),
      );

      await dio.post<void>(
        'identity/vehicle',
        data: {
          'cata_sticker': _cataStickerController.text.trim(),
          'make': _makeController.text.trim(),
          'model': _modelController.text.trim(),
          'color': _colorController.text.trim(),
          'license_plate': _licensePlateController.text.trim(),
          'owner_id': 'USR#$userId',
        },
        options: Options(headers: authHeader),
      );

      if (mounted) {
        Navigator.pop(context);
      }
    } on DioException catch (e) {
      setState(() {
        _errorMessage = e.message ?? 'Unable to save profile. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Your Details',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFamily: 'Outfit',
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              _buildField(
                controller: _nameController,
                label: 'Full Name',
                fieldKey: 'name_field',
              ),
              _buildField(
                controller: _cataStickerController,
                label: 'CATA Sticker ID',
                fieldKey: 'cata_sticker_field',
              ),
              _buildField(
                controller: _makeController,
                label: 'Vehicle Make',
                fieldKey: 'make_field',
              ),
              _buildField(
                controller: _modelController,
                label: 'Vehicle Model',
                fieldKey: 'model_field',
              ),
              _buildField(
                controller: _colorController,
                label: 'Vehicle Color',
                fieldKey: 'color_field',
              ),
              _buildField(
                controller: _licensePlateController,
                label: 'License Plate',
                fieldKey: 'license_plate_field',
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Color(0xFFFF5370),
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  key: const Key('submit_profile_setup_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDFFF00),
                    foregroundColor: const Color(0xFF1A1A00),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Color(0xFF1A1A00),
                          ),
                        )
                      : const Text(
                          'Save',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Outfit',
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Decodes the base64url payload segment of a JWT without signature
  /// verification — safe here since the token was already validated by
  /// Cognito during sign-in.
  Map<String, dynamic>? _decodeJwtPayload(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length < 2) return null;
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      switch (payload.length % 4) {
        case 2:
          payload += '==';
          break;
        case 3:
          payload += '=';
          break;
      }
      return jsonDecode(utf8.decode(base64Decode(payload)))
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String fieldKey,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        key: Key(fieldKey),
        controller: controller,
        validator: (value) =>
            (value == null || value.trim().isEmpty) ? '$label is required' : null,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFFA0A0A0)),
          filled: true,
          fillColor: const Color(0xFF1E1E1E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2C2C2C)),
          ),
        ),
      ),
    );
  }
}
