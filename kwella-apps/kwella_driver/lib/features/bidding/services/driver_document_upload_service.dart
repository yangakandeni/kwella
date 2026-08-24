import 'dart:io';

import 'package:dio/dio.dart';
import 'package:kwella_core/kwella_core.dart';

/// A short-lived presigned S3 PUT URL for a single driver onboarding document.
class PresignedUpload {
  const PresignedUpload({required this.uploadUrl, required this.s3Key});

  final String uploadUrl;
  final String s3Key;
}

/// Requests presigned upload URLs from the identity service and uploads
/// driver onboarding documents (license, PrDP, etc.) directly to S3.
class DriverDocumentUploadService {
  DriverDocumentUploadService({
    KwellaEnvironment environment = KwellaEnvironment.current,
    required TokenVault tokenVault,
    required Future<bool> Function() onRefreshNeeded,
  }) : _tokenVault = tokenVault,
       _authDio = Dio(BaseOptions(baseUrl: environment.httpApiEndpoint))
         ..interceptors.add(
           AwsErrorInterceptor(
             tokenVault: tokenVault,
             onRefreshNeeded: onRefreshNeeded,
           ),
         );

  final TokenVault _tokenVault;
  final Dio _authDio;

  /// Requests a presigned PUT URL for the given [userId]/[docType] pair.
  Future<PresignedUpload> requestPresignedUploadUrl({
    required String userId,
    required String docType,
    String contentType = 'image/jpeg',
  }) async {
    final accessToken = await _tokenVault.readAccessToken();
    final response = await _authDio.post<Map<String, dynamic>>(
      'identity/documents/presign',
      data: {
        'user_id': userId,
        'doc_type': docType,
        'content_type': contentType,
      },
      options: Options(
        headers: {
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
      ),
    );
    final data = response.data!;
    return PresignedUpload(
      uploadUrl: data['upload_url'] as String,
      s3Key: data['s3_key'] as String,
    );
  }

  /// Uploads [file] directly to S3 via the presigned [uploadUrl]. No auth
  /// header is sent — the presigned URL carries its own authorization.
  Future<void> uploadFile({
    required String uploadUrl,
    required File file,
    required String contentType,
  }) async {
    final bytes = await file.readAsBytes();
    await Dio().put<void>(
      uploadUrl,
      data: bytes,
      options: Options(headers: {'Content-Type': contentType}),
    );
  }
}
