import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kwella_core/kwella_core.dart';

import 'package:kwella_driver/features/bidding/presentation/screens/driver_onboarding_screen.dart';
import 'package:kwella_driver/features/bidding/services/driver_document_upload_service.dart';

class _FakeImagePicker extends ImagePicker {
  _FakeImagePicker({this.pickedPath = '/tmp/fake_doc.jpg'});
  final String? pickedPath;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    final path = pickedPath;
    return path == null ? null : XFile(path);
  }
}

class _FakeUploadService extends DriverDocumentUploadService {
  _FakeUploadService({this.shouldFail = false})
      : super(tokenVault: TokenVault(), onRefreshNeeded: () async => false);

  final bool shouldFail;

  @override
  Future<PresignedUpload> requestPresignedUploadUrl({
    required String userId,
    required String docType,
    String contentType = 'image/jpeg',
  }) async {
    if (shouldFail) throw Exception('presign failed');
    return const PresignedUpload(
      uploadUrl: 'https://example.com/upload',
      s3Key: 'drivers/drv-test-1/VEHICLE_REGISTRATION/fake.jpg',
    );
  }

  @override
  Future<void> uploadFile({
    required String uploadUrl,
    required File file,
    required String contentType,
  }) async {
    if (shouldFail) throw Exception('upload failed');
  }
}

const _uploadButtonKey = Key('upload_button_VEHICLE_REGISTRATION');

Future<void> _authenticate(WidgetTester tester) async {
  final element = tester.element(find.byType(DriverOnboardingScreen));
  final container = ProviderScope.containerOf(element);
  container.read(kwellaAuthNotifierProvider.notifier).state =
      const KwellaAuthState(
    status: KwellaAuthStatus.authenticated,
    userId: 'drv-test-1',
  );
}

void main() {
  testWidgets(
      'tapping Upload on a pending doc flips its status to uploaded on success',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: DriverOnboardingScreen(
            uploadService: _FakeUploadService(),
            imagePicker: _FakeImagePicker(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await _authenticate(tester);

    expect(find.byKey(_uploadButtonKey), findsOneWidget);
    await tester.tap(find.byKey(_uploadButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(_uploadButtonKey), findsNothing);
    expect(find.text('Under Review'), findsWidgets);
  });

  testWidgets('a failed upload keeps the doc pending and shows a snackbar',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: DriverOnboardingScreen(
            uploadService: _FakeUploadService(shouldFail: true),
            imagePicker: _FakeImagePicker(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await _authenticate(tester);

    await tester.tap(find.byKey(_uploadButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(_uploadButtonKey), findsOneWidget);
    expect(find.textContaining('Upload failed'), findsOneWidget);
  });

  testWidgets('cancelling the image picker leaves the doc untouched',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: DriverOnboardingScreen(
            uploadService: _FakeUploadService(),
            imagePicker: _FakeImagePicker(pickedPath: null),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await _authenticate(tester);

    await tester.tap(find.byKey(_uploadButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(_uploadButtonKey), findsOneWidget);
  });
}
