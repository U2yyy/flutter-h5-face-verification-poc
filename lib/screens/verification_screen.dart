import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/aliyun_h5_liveness_method.dart';
import '../models/baidu_h5_liveness_method.dart';
import '../models/finauth_h5_liveness_method.dart';
import '../models/face_verification_result.dart';
import '../models/verification_metrics.dart';
import '../services/face_verification_provider.dart';
import '../services/aliyun/aliyun_face_verification_response_parser.dart';
import '../services/aliyun/aliyun_face_verification_service.dart';
import '../services/baidu/baidu_face_verification_service.dart';
import '../services/finauth/finauth_face_verification_service.dart';
import '../services/tencent/tencent_ekyc_bridge.dart';
import '../services/tencent/tencent_face_id_service.dart';
import '../services/tencent/tencent_h5_service.dart';
import '../utils/aliyun_metainfo_bootstrap.dart';
import '../utils/app_config.dart';
import '../utils/media_utils.dart';
import '../utils/permission_utils.dart';
import 'live_capture_screen.dart';
import 'h5_liveness_screen.dart';
import '../widgets/aliyun_metainfo_loader.dart';

enum VerificationFlow { pureApi, saasH5, saasNativeSdk }

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen>
    with TickerProviderStateMixin {
  final _picker = ImagePicker();
  final _metrics = MetricsRecorder.instance;

  late final List<FaceVerificationProvider> _providers = [
    TencentFaceIdService(),
    BaiduFaceVerificationService(),
    AliyunFaceVerificationService(),
    FinAuthFaceVerificationService(),
  ];

  FaceVerificationProvider? _selectedProvider;
  VerificationFlow _flow = VerificationFlow.pureApi;
  BaiduH5LivenessMethod _baiduH5Method = BaiduH5LivenessMethod.dazzlePupil;
  AliyunH5LivenessMethod _aliyunH5Method = AliyunH5LivenessMethod.defaultMethod;
  FinAuthH5LivenessMethod _finAuthH5Method = FinAuthH5LivenessMethod.flash;
  Uint8List? _referenceImageBytes;
  Uint8List? _liveVideoBytes;
  String? _sdkToken;
  String? _verificationUrl;
  bool _livenessComplete = false;
  bool? _ekycSdkAvailable;
  FaceVerificationResult? _result;
  bool _loading = false;
  bool _isVerifying = false;
  String? _statusMessage;
  String? _aliyunDebugStep;
  int _aliyunWaitSeconds = 0;
  Timer? _aliyunWaitTimer;
  Timer? _aliyunWatchdogTimer;
  static const _aliyunH5SessionWatchdog = Duration(seconds: 90);
  final _metaInfoLoaderKey = GlobalKey<AliyunMetaInfoLoaderState>();
  Completer<String>? _metaInfoCompleter;
  var _aliyunMetaInfoLoaderActive = false;
  var _aliyunMetaInfoGeneration = 0;

  late final TabController _baiduH5TabController;
  late final TabController _aliyunH5TabController;
  late final TabController _finAuthH5TabController;

  @override
  void initState() {
    super.initState();
    _baiduH5TabController = TabController(
      length: BaiduH5LivenessMethod.all.length,
      vsync: this,
    );
    _aliyunH5TabController = TabController(
      length: AliyunH5LivenessMethod.all.length,
      vsync: this,
    );
    _finAuthH5TabController = TabController(
      length: FinAuthH5LivenessMethod.all.length,
      vsync: this,
    );
    _selectedProvider = _providers.first;
    _loadEkycAvailability();
  }

  @override
  void dispose() {
    _aliyunWaitTimer?.cancel();
    _aliyunWatchdogTimer?.cancel();
    _baiduH5TabController.dispose();
    _aliyunH5TabController.dispose();
    _finAuthH5TabController.dispose();
    super.dispose();
  }

  Future<void> _loadEkycAvailability() async {
    final available = await TencentEkycBridge.isAvailable();
    if (!mounted) return;
    setState(() => _ekycSdkAvailable = available);
  }

  bool get _isBaiduSelected => _selectedProvider is BaiduFaceVerificationService;

  bool get _isAliyunSelected =>
      _selectedProvider is AliyunFaceVerificationService;

  bool get _isFinAuthSelected =>
      _selectedProvider is FinAuthFaceVerificationService;

  bool get _supportsNativeSdk =>
      !_isBaiduSelected && !_isAliyunSelected && !_isFinAuthSelected;

  bool get _supportsPureApi => !_isAliyunSelected && !_isFinAuthSelected;

  String get _h5RedirectUrl {
    if (_isBaiduSelected) return AppConfig.baiduFaceprintH5CallbackUrl;
    if (_isAliyunSelected) return AppConfig.aliyunCloudAuthReturnUrl;
    if (_isFinAuthSelected) return AppConfig.finauthH5ReturnUrl;
    return AppConfig.tencentFaceIdH5RedirectUrl;
  }

  H5CallbackStyle get _h5CallbackStyle {
    if (_isAliyunSelected) return H5CallbackStyle.aliyunResponse;
    if (_isFinAuthSelected) return H5CallbackStyle.finauthBizId;
    return H5CallbackStyle.tencentToken;
  }

  bool get _showCredentialsWarning {
    final provider = _selectedProvider;
    if (provider == null) return false;
    return !provider.isConfigured;
  }

  bool get _aliyunUsesFaceContrastPictureUrl =>
      _isAliyunSelected && AppConfig.aliyunUsesFaceContrastPictureUrl;

  bool get _h5SessionRequiresReference =>
      !_aliyunUsesFaceContrastPictureUrl;

  bool get _referenceStepComplete =>
      _referenceImageBytes != null ||
      (_flow == VerificationFlow.saasH5 && _aliyunUsesFaceContrastPictureUrl);

  int get _currentStep {
    if (_flow == VerificationFlow.saasH5) {
      if (!_referenceStepComplete) return 1;
      if (_sdkToken == null) return 2;
      if (!_livenessComplete) return 3;
      return 4;
    }
    if (_flow == VerificationFlow.saasNativeSdk) {
      if (_referenceImageBytes == null) return 1;
      if (_sdkToken == null) return 2;
      if (!_livenessComplete) return 3;
      return 4;
    }
    if (_referenceImageBytes == null) return 1;
    if (_liveVideoBytes == null) return 2;
    return 3;
  }

  void _resetH5SessionState() {
    _sdkToken = null;
    _verificationUrl = null;
    _livenessComplete = false;
  }

  void _onBaiduH5MethodChanged(BaiduH5LivenessMethod method) {
    if (_baiduH5Method == method) return;
    final index = BaiduH5LivenessMethod.all.indexOf(method);
    if (index >= 0 && _baiduH5TabController.index != index) {
      _baiduH5TabController.index = index;
    }
    setState(() {
      _baiduH5Method = method;
      _result = null;
      _resetH5SessionState();
    });
  }

  void _onAliyunH5MethodChanged(AliyunH5LivenessMethod method) {
    if (_aliyunH5Method == method) return;
    final index = AliyunH5LivenessMethod.all.indexOf(method);
    if (index >= 0 && _aliyunH5TabController.index != index) {
      _aliyunH5TabController.index = index;
    }
    setState(() {
      _aliyunH5Method = method;
      _result = null;
      _resetH5SessionState();
    });
  }

  void _onFinAuthH5MethodChanged(FinAuthH5LivenessMethod method) {
    if (_finAuthH5Method == method) return;
    final index = FinAuthH5LivenessMethod.all.indexOf(method);
    if (index >= 0 && _finAuthH5TabController.index != index) {
      _finAuthH5TabController.index = index;
    }
    setState(() {
      _finAuthH5Method = method;
      _result = null;
      _resetH5SessionState();
    });
  }

  Future<void> _pickReferenceImage() async {
    final granted = await PermissionUtils.ensureGalleryAccess();
    if (!mounted) return;
    if (!granted) {
      _showMessage(
        'Gallery permission denied. Enable it in Settings to pick a photo.',
        isError: true,
      );
      return;
    }

    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 4000,
      imageQuality: 90,
    );
    if (file == null) return;

    await _applyReferenceImage(await file.readAsBytes(), sourceLabel: 'Gallery');
  }

  Future<void> _captureReferenceSelfie() async {
    final granted = await PermissionUtils.ensureCamera();
    if (!mounted) return;
    if (!granted) {
      _showMessage(
        'Camera permission denied. Enable it in Settings to take a selfie.',
        isError: true,
      );
      return;
    }

    final file = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 4000,
      imageQuality: 90,
    );
    if (file == null) return;

    await _applyReferenceImage(await file.readAsBytes(), sourceLabel: 'Selfie');
  }

  Future<void> _applyReferenceImage(
    Uint8List rawBytes, {
    required String sourceLabel,
  }) async {
    final prepared = await MediaUtils.prepareReferenceImage(rawBytes);
    final validationError = MediaUtils.validateImageForApi(prepared);

    if (!mounted) return;
    setState(() {
      _referenceImageBytes = prepared;
      _result = null;
      _resetH5SessionState();
      _statusMessage = validationError;
    });

    if (validationError != null) {
      _showMessage(validationError, isError: true);
    } else {
      _showMessage(
        'Reference photo ready from $sourceLabel (${MediaUtils.formatBytes(prepared.length)}).',
      );
    }
  }

  Future<void> _captureLiveVideo() async {
    final granted = await PermissionUtils.ensureCamera();
    if (!mounted) return;
    if (!granted) {
      _showMessage(
        'Camera permission denied. Enable it in Settings to record video.',
        isError: true,
      );
      return;
    }

    final bytes = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (_) => const LiveCaptureScreen()),
    );
    if (bytes == null) return;

    final validationError = MediaUtils.validateVideoForApi(bytes);
    setState(() {
      _liveVideoBytes = bytes;
      _result = null;
      _statusMessage = validationError;
    });

    if (validationError != null) {
      _showMessage(validationError, isError: true);
    } else {
      _showMessage(
        'Live video captured (${MediaUtils.formatBytes(bytes.length)}). Tap Run verification.',
      );
    }
  }

  void _setAliyunDebugStep(String step) {
    if (!_isAliyunSelected) return;
    if (!mounted) return;
    setState(() => _aliyunDebugStep = step);
  }

  void _startAliyunWaitTimer() {
    _aliyunWaitTimer?.cancel();
    _aliyunWaitSeconds = 0;
    _aliyunWaitTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _aliyunWaitSeconds++;
        final msg = _statusMessage;
        if (msg == null) return;
        if (msg.startsWith('Preparing')) {
          _statusMessage = 'Preparing… (${_aliyunWaitSeconds}s)';
        } else if (msg.startsWith('Calling InitFaceVerify')) {
          _statusMessage =
              'Calling InitFaceVerify… (${_aliyunWaitSeconds}s)';
        }
      });
    });
  }

  void _stopAliyunWatchdog() {
    _aliyunWatchdogTimer?.cancel();
    _aliyunWatchdogTimer = null;
  }

  void _startAliyunWatchdog(Stopwatch sessionStopwatch) {
    _stopAliyunWatchdog();
    _aliyunWatchdogTimer = Timer(_aliyunH5SessionWatchdog, () {
      if (!mounted || !_loading) return;
      final lastStep = _aliyunDebugStep ?? 'unknown';
      _metaInfoLoaderKey.currentState?.cancel(reason: 'watchdog_timeout');
      final provider = _selectedProvider;
      if (provider is AliyunFaceVerificationService) {
        provider.cancelInflightRequest();
      }
      final completer = _metaInfoCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.completeError(StateError('Watchdog timeout'));
      }
      _stopAliyunWaitTimer();
      setState(() {
        _loading = false;
        _aliyunMetaInfoLoaderActive = false;
        _statusMessage = null;
        _result = FaceVerificationResult(
          providerId: 'aliyun_cloudauth',
          providerName: 'Aliyun CloudAuth',
          latency: sessionStopwatch.elapsed,
          success: false,
          isMatch: false,
          isLive: false,
          errorCode: 'WatchdogTimeout',
          errorMessage:
              'Request H5 Session exceeded ${_aliyunH5SessionWatchdog.inSeconds}s at: $lastStep',
          errorExplanationZh: 'H5 会话请求总超时',
          errorSuggestedFix:
              '查看 logcat [AliyunTrace] 定位卡在哪一步：MetaInfo CDN、InitFaceVerify 签名或网络。',
          apiAction: 'InitFaceVerify',
        );
      });
      _setAliyunDebugStep('Watchdog timeout at: $lastStep');
    });
  }

  void _stopAliyunWaitTimer() {
    _aliyunWaitTimer?.cancel();
    _aliyunWaitTimer = null;
    if (_aliyunWaitSeconds != 0 && mounted) {
      setState(() => _aliyunWaitSeconds = 0);
    }
  }

  void _cancelAliyunH5SessionWait() {
    _aliyunMetaInfoGeneration++;
    _metaInfoLoaderKey.currentState?.cancel(reason: 'user_cancel');
    final completer = _metaInfoCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(StateError('Cancelled'));
    }
    final provider = _selectedProvider;
    if (provider is AliyunFaceVerificationService) {
      provider.cancelInflightRequest();
    }
    _stopAliyunWaitTimer();
    _stopAliyunWatchdog();
    _setLoading(false, reason: 'user_cancel_h5_session');
    setState(() {
      _statusMessage = null;
      _aliyunMetaInfoLoaderActive = false;
    });
    _setAliyunDebugStep('H5 session request cancelled');
    _showMessage('Request cancelled.', isError: false);
  }

  void _onAliyunMetaInfoReady(String metaInfo) {
    if (mounted) {
      setState(() => _aliyunMetaInfoLoaderActive = false);
    }
    final completer = _metaInfoCompleter;
    if (completer == null || completer.isCompleted) return;
    completer.complete(metaInfo);
  }

  void _onAliyunMetaInfoError(String message) {
    final completer = _metaInfoCompleter;
    if (completer == null || completer.isCompleted) return;
    completer.completeError(message);
  }

  Future<String?> _waitForAliyunMetaInfo(
    int generation,
    Stopwatch sessionStopwatch,
  ) async {
    final completer = Completer<String>();
    _metaInfoCompleter = completer;
    try {
      return await completer.future.timeout(
        AliyunMetaInfoBootstrap.navigationTimeout,
      );
    } on TimeoutException {
      _metaInfoLoaderKey.currentState?.cancel(reason: 'loader_timeout');
      return null;
    } catch (e) {
      if (e is StateError && e.message == 'Cancelled') {
        return null;
      }
      return null;
    } finally {
      _metaInfoCompleter = null;
    }
  }

  void _setLoading(bool value, {String? reason}) {
    if (_loading != value) {
      setState(() => _loading = value);
    }
  }

  Future<void> _requestH5Session() async {
    final provider = _selectedProvider;
    if (provider == null) return;
    if (_h5SessionRequiresReference && _referenceImageBytes == null) return;
    final reference = _referenceImageBytes;

    final sessionStopwatch = Stopwatch()..start();
    if (provider is AliyunFaceVerificationService) {
      _setAliyunDebugStep('Request H5 session tapped');
    }

    setState(() {
      _result = null;
      _sdkToken = null;
      _verificationUrl = null;
      _livenessComplete = false;
    });

    late final FaceVerificationResult sessionResult;
    try {
      if (provider is TencentFaceIdService) {
        _setLoading(true, reason: 'tencent_h5_session');
        sessionResult = await provider.requestH5Session(
          referenceImageBytes: reference!,
        );
      } else if (provider is BaiduFaceVerificationService) {
        _setLoading(true, reason: 'baidu_h5_session');
        sessionResult = await provider.requestH5Session(
          referenceImageBytes: reference!,
          planId: _baiduH5Method.planId,
        );
      } else if (provider is AliyunFaceVerificationService) {
        final generation = ++_aliyunMetaInfoGeneration;
        _startAliyunWaitTimer();
        _startAliyunWatchdog(sessionStopwatch);
        _setLoading(true, reason: 'aliyun_h5_session_start');

        final metaOverride = AppConfig.aliyunCloudAuthMetaInfoOverride.trim();
        late final String metaInfo;
        if (metaOverride.isNotEmpty) {
          _setAliyunDebugStep('Step 1/2: MetaInfo (env override)');
          setState(() {
            _statusMessage = 'Using MetaInfo override… (0s)';
            _aliyunMetaInfoLoaderActive = false;
          });
          metaInfo = metaOverride;
        } else {
          setState(() {
            _statusMessage = 'Preparing… (0s)';
            _aliyunMetaInfoLoaderActive = true;
          });
          _setAliyunDebugStep('Step 1/2: MetaInfo (hidden WebView)');
          await Future<void>.delayed(Duration.zero);

          final loaded = await _waitForAliyunMetaInfo(
            generation,
            sessionStopwatch,
          );
          if (!mounted || generation != _aliyunMetaInfoGeneration) return;
          if (loaded == null || loaded.trim().isEmpty) {
            _stopAliyunWatchdog();
            setState(() {
              _statusMessage = null;
              _aliyunMetaInfoLoaderActive = false;
            });
            _setAliyunDebugStep('MetaInfo failed/cancelled');
            if (_loading) {
              _setLoading(false, reason: 'metainfo_failed');
              setState(() {
                _result = FaceVerificationResult(
                  providerId: 'aliyun_cloudauth',
                  providerName: 'Aliyun CloudAuth',
                  latency: sessionStopwatch.elapsed,
                  success: false,
                  isMatch: false,
                  isLive: false,
                  errorCode: 'MetaInfoFailed',
                  errorMessage:
                      'MetaInfo loading cancelled or timed out after '
                      '${AliyunMetaInfoBootstrap.navigationTimeout.inSeconds}s.',
                  errorExplanationZh: 'MetaInfo 加载失败或超时',
                  errorSuggestedFix:
                      '检查设备能否访问 ${AliyunMetaInfoBootstrap.jsUrl}；'
                      '关闭 VPN 或换网络后重试。',
                  apiAction: 'InitFaceVerify',
                );
              });
            }
            return;
          }

          setState(() => _aliyunMetaInfoLoaderActive = false);
          await WidgetsBinding.instance.endOfFrame;
          metaInfo = loaded;
        }

        _setAliyunDebugStep('Step 2/2: InitFaceVerify');
        setState(() {
          _aliyunWaitSeconds = 0;
          _statusMessage = 'Calling InitFaceVerify… (0s)';
        });

        Uint8List? aliyunReference;
        if (!_aliyunUsesFaceContrastPictureUrl) {
          aliyunReference =
              await MediaUtils.prepareReferenceImageForAliyun(reference!);
          if (!mounted || generation != _aliyunMetaInfoGeneration) return;
        }

        sessionResult = await provider.requestH5Session(
          referenceImageBytes: aliyunReference,
          metaInfo: metaInfo,
          model: _aliyunH5Method.model,
        );
        _stopAliyunWatchdog();
        _stopAliyunWaitTimer();
      } else if (provider is FinAuthFaceVerificationService) {
        _setLoading(true, reason: 'finauth_h5_session');
        sessionResult = await provider.requestH5Session(
          referenceImageBytes: reference!,
          procedureType: _finAuthH5Method.procedureType,
        );
      } else {
        return;
      }
    } finally {
      if (mounted) {
        _stopAliyunWaitTimer();
        _stopAliyunWatchdog();
        final wasAliyunWait = _statusMessage != null &&
            (_statusMessage!.startsWith('Preparing') ||
                _statusMessage!.startsWith('Calling InitFaceVerify'));
        _setLoading(false, reason: 'request_h5_session_finally');
        setState(() {
          _aliyunMetaInfoLoaderActive = false;
          if (_statusMessage != null && wasAliyunWait) {
            _statusMessage = null;
          }
        });
      }
    }

    if (!mounted) return;
    setState(() {
      _sdkToken = sessionResult.sdkToken;
      _verificationUrl = sessionResult.verificationUrl;
      _statusMessage = null;
      if (sessionResult.success) {
        // InitFaceVerify success is session setup only — not verification.
        _result = null;
      } else {
        _result = sessionResult;
      }
    });
    if (provider is AliyunFaceVerificationService) {
      _setAliyunDebugStep(
        sessionResult.success ? 'H5 session ready' : 'InitFaceVerify failed',
      );
    }
    if (!sessionResult.success) {
      _recordMetrics(sessionResult);
      if (provider is! AliyunFaceVerificationService) {
        _showMessage(
          sessionResult.errorMessage ?? 'Failed to start H5 session',
          isError: true,
        );
      }
    } else if (sessionResult.verificationUrl == null ||
        sessionResult.verificationUrl!.isEmpty) {
      _showMessage(
        'CertifyId ready. Set ALIYUN_CLOUDAUTH_CERTIFY_URL_TYPE=H5 in .env '
        'and retry to obtain CertifyUrl for WebView liveness.',
        isError: false,
      );
    } else {
      _showMessage('H5 session ready. Tap Start H5 Liveness to open WebView.');
    }
  }

  Future<void> _startH5Liveness() async {
    final token = _sdkToken;
    final verificationUrl = _verificationUrl;
    if (token == null || token.isEmpty) {
      _showMessage('Request an H5 session first.', isError: true);
      return;
    }
    if (verificationUrl == null || verificationUrl.isEmpty) {
      _showMessage(
        'No CertifyUrl in InitFaceVerify response. Set '
        'ALIYUN_CLOUDAUTH_CERTIFY_URL_TYPE=H5 in .env and request a new session.',
        isError: true,
      );
      return;
    }

    if (_isAliyunSelected) {
      _setAliyunDebugStep('Opening H5 liveness WebView');
    }

    _setLoading(true, reason: 'h5_liveness_start');

    final granted = await PermissionUtils.ensureH5LivenessPermissions();
    if (!mounted) return;
    if (!granted) {
      _setLoading(false, reason: 'h5_liveness_permission_denied');
      _showMessage(
        'Camera permission denied. Enable it in Settings to start H5 liveness.',
        isError: true,
      );
      return;
    }

    setState(() => _livenessComplete = false);

    final completion = await Navigator.push<H5LivenessCompletion>(
      context,
      MaterialPageRoute(
        builder: (_) => H5LivenessScreen(
          verificationUrl: verificationUrl,
          redirectUrl: _h5RedirectUrl,
          callbackStyle: _h5CallbackStyle,
        ),
      ),
    );

    if (!mounted) return;
    _setLoading(false, reason: 'h5_liveness_returned');

    if (completion == null || !completion.success) {
      if (_isAliyunSelected) {
        _setAliyunDebugStep('H5 liveness failed/cancelled');
      }
      _showMessage(
        completion?.errorMessage ?? 'H5 liveness cancelled',
        isError: completion != null,
      );
      return;
    }

    if (completion.bizToken != null && completion.bizToken!.isNotEmpty) {
      setState(() => _sdkToken = completion.bizToken);
    }

    if (_isAliyunSelected) {
      _setAliyunDebugStep('DescribeFaceVerify…');
    }

    setState(() => _livenessComplete = true);
    _setLoading(true, reason: 'auto_verify_after_liveness');
    _showMessage('H5 liveness complete. Fetching verification result…');

    await _runVerification(autoTriggered: true);
  }

  Future<void> _requestSdkToken() async {
    final provider = _selectedProvider;
    final reference = _referenceImageBytes;
    if (provider == null || reference == null) return;

    setState(() {
      _loading = true;
      _result = null;
      _sdkToken = null;
      _verificationUrl = null;
      _livenessComplete = false;
    });

    final result = await provider.requestSdkToken(
      referenceImageBytes: reference,
    );

    if (!mounted) return;
    setState(() {
      _sdkToken = result.sdkToken;
      _loading = false;
      if (result.success) {
        _result = null;
      } else {
        _result = result;
      }
    });
    if (!result.success) {
      _recordMetrics(result);
      _showMessage(result.errorMessage ?? 'Failed to get SdkToken', isError: true);
    } else {
      _showMessage('SdkToken ready. Tap Start Liveness to open the eKYC SDK.');
    }
  }

  Future<void> _startLiveness() async {
    final token = _sdkToken;
    if (token == null || token.isEmpty) {
      _showMessage('Request an SdkToken first.', isError: true);
      return;
    }

    final available = await TencentEkycBridge.isAvailable();
    if (!mounted) return;
    setState(() => _ekycSdkAvailable = available);

    if (!available) {
      _showMessage(
        'Tencent eKYC SDK is not integrated on this device. '
        'Add native SDK binaries (see README), then rebuild.',
        isError: true,
      );
      return;
    }

    setState(() {
      _loading = true;
      _livenessComplete = false;
    });

    final launchResult = await TencentEkycBridge.startLiveness(sdkToken: token);

    if (!mounted) return;

    if (!launchResult.success) {
      setState(() => _loading = false);
      _showMessage(
        launchResult.errorMessage ??
            'Liveness failed (${launchResult.errorCode ?? "unknown"})',
        isError: true,
      );
      return;
    }

    setState(() {
      _livenessComplete = true;
      _loading = true;
    });
    _showMessage('Liveness passed. Fetching verification result…');

    await _runVerification(autoTriggered: true);
  }

  Future<void> _runVerification({bool autoTriggered = false}) async {
    final provider = _selectedProvider;
    if (provider == null) return;

    if (!provider.isConfigured) {
      final credHint = switch (provider) {
        BaiduFaceVerificationService() =>
          'Add BAIDU_API_KEY and BAIDU_SECRET_KEY to .env first.',
        AliyunFaceVerificationService() =>
          'Add ALIYUN_ACCESS_KEY_ID, ALIYUN_ACCESS_KEY_SECRET, and ALIYUN_CLOUDAUTH_SCENE_ID to .env first.',
        FinAuthFaceVerificationService() =>
          'Add FINAUTH_API_KEY and FINAUTH_API_SECRET to .env first.',
        _ =>
          'Add TENCENT_SECRET_ID and TENCENT_SECRET_KEY to .env first.',
      };
      _showMessage(credHint, isError: true);
      return;
    }

    setState(() {
      _loading = true;
      _isVerifying = true;
      _result = null;
    });

    FaceVerificationResult? result;
    try {
      if (_flow == VerificationFlow.pureApi) {
        final reference = _referenceImageBytes;
        final video = _liveVideoBytes;
        if (reference == null || video == null) {
          _showMessage('Complete steps 1 and 2 before verifying.', isError: true);
          return;
        }
        result = await provider.verifyWithReferenceAndVideo(
          referenceImageBytes: reference,
          liveVideoBytes: video,
        );
      } else if (_flow == VerificationFlow.saasH5) {
        final token = _sdkToken;
        if (token == null || token.isEmpty) {
          _showMessage('Request an H5 session first.', isError: true);
          return;
        }
        if (!autoTriggered && !_livenessComplete) {
          _showMessage('Complete H5 liveness in WebView first.', isError: true);
          return;
        }
        if (provider is TencentFaceIdService) {
          result = await provider.fetchH5VerificationResult(bizToken: token);
        } else if (provider is BaiduFaceVerificationService) {
          result = await provider.fetchH5VerificationResult(verifyToken: token);
        } else if (provider is AliyunFaceVerificationService) {
          result = await provider.fetchH5VerificationResult(certifyId: token);
          _setAliyunDebugStep(
            result.success ? 'Verification complete' : 'DescribeFaceVerify failed',
          );
        } else if (provider is FinAuthFaceVerificationService) {
          result = await provider.fetchH5VerificationResult(bizId: token);
        } else {
          _showMessage('H5 flow is not supported for this provider.', isError: true);
          return;
        }
      } else {
        final token = _sdkToken;
        if (token == null || token.isEmpty) {
          _showMessage('Request an SdkToken first.', isError: true);
          return;
        }
        if (!autoTriggered && !_livenessComplete) {
          _showMessage('Complete liveness in the eKYC SDK first.', isError: true);
          return;
        }
        result = await provider.fetchSdkVerificationResult(sdkToken: token);
      }

      if (!mounted) return;
      setState(() => _result = result);
      _recordMetrics(result);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _isVerifying = false;
        });
      }
    }
  }

  void _recordMetrics(FaceVerificationResult result) {
    _metrics.record(
      VerificationMetrics(
        providerId: result.providerId,
        providerName: result.providerName,
        latency: result.latency,
        success: result.success,
        isMatch: result.isMatch,
        isLive: result.isLive,
        similarity: result.similarity,
        timestamp: DateTime.now(),
        errorMessage: result.errorMessage,
        apiAction: result.apiAction,
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        action: isError
            ? SnackBarAction(
                label: 'Settings',
                onPressed: PermissionUtils.openSettings,
              )
            : null,
      ),
    );
  }

  void _resetFlow() {
    setState(() {
      _referenceImageBytes = null;
      _liveVideoBytes = null;
      _resetH5SessionState();
      _result = null;
      _statusMessage = null;
      _aliyunDebugStep = null;
      _loading = false;
      _isVerifying = false;
    });
  }

  bool get _canVerify {
    if (_flow == VerificationFlow.pureApi) {
      return _referenceImageBytes != null && _liveVideoBytes != null;
    }
    if (_flow == VerificationFlow.saasH5) {
      return _sdkToken != null &&
          _sdkToken!.isNotEmpty &&
          _livenessComplete;
    }
    return _sdkToken != null &&
        _sdkToken!.isNotEmpty &&
        _livenessComplete;
  }

  @override
  Widget build(BuildContext context) {
    final provider = _selectedProvider;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Verification'),
        backgroundColor: theme.colorScheme.inversePrimary,
        actions: [
          IconButton(
            tooltip: 'Reset',
            onPressed: _resetFlow,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
          _buildStepProgress(),
          const SizedBox(height: 16),
          _buildProviderSelector(),
          const SizedBox(height: 12),
          _buildFlowSelector(),
          if (_isBaiduSelected && _flow == VerificationFlow.saasH5) ...[
            const SizedBox(height: 12),
            _buildBaiduH5MethodTabs(),
          ],
          if (_isAliyunSelected && _flow == VerificationFlow.saasH5) ...[
            const SizedBox(height: 12),
            _buildAliyunH5MethodTabs(),
          ],
          if (_isFinAuthSelected && _flow == VerificationFlow.saasH5) ...[
            const SizedBox(height: 12),
            _buildFinAuthH5MethodTabs(),
          ],
          const SizedBox(height: 12),
          if (provider != null && _showCredentialsWarning) _buildCredentialsWarning(),
          if (_statusMessage != null) ...[
            const SizedBox(height: 12),
            _buildStatusBanner(_statusMessage!),
          ],
          if (_isAliyunSelected &&
              _flow == VerificationFlow.saasH5 &&
              _aliyunDebugStep != null) ...[
            const SizedBox(height: 12),
            _buildAliyunDebugOverlay(),
          ],
          const SizedBox(height: 16),
          _buildStepCard(
            step: 1,
            complete: _referenceStepComplete,
            title: 'Upload reference photo',
            subtitle: _aliyunUsesFaceContrastPictureUrl
                ? 'Optional for Aliyun — InitFaceVerify uses FaceContrastPictureUrl '
                    'from .env (${AppConfig.aliyunCloudAuthFaceContrastPictureUrl}).'
                : 'Pick from gallery or take a selfie (基准图). Max 3 MB after encoding.',
            child: Column(
              children: [
                _buildImagePreview(
                  bytes: _referenceImageBytes,
                  placeholder: 'No reference photo selected',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : _pickReferenceImage,
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Gallery'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : _captureReferenceSelfie,
                        icon: const Icon(Icons.camera_front),
                        label: const Text('Selfie'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_flow == VerificationFlow.pureApi)
            _buildStepCard(
              step: 2,
              complete: _liveVideoBytes != null,
              title: 'Record live face video',
              subtitle:
                  'Use the front camera for 2–6 seconds (MP4). Max 8 MB after encoding.',
              child: Column(
                children: [
                  _buildVideoStatus(),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _captureLiveVideo,
                    icon: const Icon(Icons.videocam),
                    label: Text(
                      _liveVideoBytes == null
                          ? 'Open camera & record'
                          : 'Re-record video',
                    ),
                  ),
                ],
              ),
            )
          else if (_flow == VerificationFlow.saasH5) ...[
            _buildStepCard(
              step: 2,
              complete: _sdkToken != null,
              title: 'Get H5 verification session',
              subtitle: _isBaiduSelected
                  ? '${_baiduH5Method.label} · plan_id ${_baiduH5Method.planId} · '
                      'verifyToken/generate + uploadMatchImage.'
                  : _isAliyunSelected
                      ? '${_aliyunH5Method.label} · Model ${_aliyunH5Method.model} · '
                          'MetaInfo WebView (or env override), InitFaceVerify with '
                          '${_aliyunUsesFaceContrastPictureUrl ? "FaceContrastPictureUrl" : "base64 photo"}.'
                      : _isFinAuthSelected
                          ? '${_finAuthH5Method.label} · get_token with image_ref1.'
                      : 'Calls ApplyWebVerificationBizTokenIntl with your reference photo.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _loading ||
                            (_h5SessionRequiresReference &&
                                _referenceImageBytes == null)
                        ? null
                        : _requestH5Session,
                    icon: const Icon(Icons.link),
                    label: const Text('Request H5 session'),
                  ),
                  if (_sdkToken != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      _isBaiduSelected
                          ? 'verify_token: $_sdkToken'
                          : _isAliyunSelected
                              ? 'CertifyId: $_sdkToken'
                              : _isFinAuthSelected
                                  ? 'biz_id: $_sdkToken'
                                  : 'BizToken: $_sdkToken',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (_verificationUrl != null) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      _verificationUrl!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ] else if (_isAliyunSelected && _sdkToken != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'CertifyUrl not returned. Set ALIYUN_CLOUDAUTH_CERTIFY_URL_TYPE=H5 '
                      'for WebView liveness.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildStepCard(
              step: 3,
              complete: _livenessComplete,
              title: 'Complete liveness in H5 WebView',
              subtitle: _isBaiduSelected
                  ? 'Opens Baidu faceprint H5 (brain.baidu.com). Completion detected via callback ?token=.'
                  : _isAliyunSelected
                      ? 'Opens Aliyun CertifyUrl in WebView. Completion detected via ReturnUrl ?response=.'
                      : _isFinAuthSelected
                          ? 'Opens FinAuth DoVerification H5. Completion detected via return_url ?biz_id=.'
                      : 'Opens Tencent H5 liveness page. Completion detected via RedirectURL?token=.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _loading ||
                            _sdkToken == null ||
                            _verificationUrl == null
                        ? null
                        : _startH5Liveness,
                    icon: const Icon(Icons.language),
                    label: const Text('Start H5 Liveness'),
                  ),
                  if (_livenessComplete) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.shade700, size: 18),
                        const SizedBox(width: 8),
                        const Text('H5 liveness completed'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ] else ...[
            _buildStepCard(
              step: 2,
              complete: _sdkToken != null,
              title: 'Get SdkToken for eKYC SDK',
              subtitle:
                  'Calls GetFaceIdTokenIntl (compare mode). Liveness runs in Tencent eKYC SDK.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _loading || _referenceImageBytes == null
                        ? null
                        : _requestSdkToken,
                    icon: const Icon(Icons.vpn_key),
                    label: const Text('Request SdkToken'),
                  ),
                  if (_sdkToken != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      _sdkToken!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildStepCard(
              step: 3,
              complete: _livenessComplete,
              title: 'Complete liveness in Tencent eKYC SDK',
              subtitle:
                  'Opens the native eKYC SDK with your SdkToken. Requires SDK binaries (see README).',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_ekycSdkAvailable == false)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'SDK not detected on this build. Add AAR/Framework and rebuild.',
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: _loading || _sdkToken == null
                        ? null
                        : _startLiveness,
                    icon: const Icon(Icons.face_retouching_natural),
                    label: const Text('Start Liveness'),
                  ),
                  if (_livenessComplete) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.shade700, size: 18),
                        const SizedBox(width: 8),
                        const Text('Liveness completed'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildStepCard(
            step: _flow == VerificationFlow.pureApi ? 3 : 4,
            complete: _result?.success == true,
            title: 'Run verification',
            subtitle: _verificationStepSubtitle(),
            child: FilledButton.icon(
              onPressed: _loading || !_canVerify ? null : _runVerification,
              icon: _isVerifying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_user),
              label: Text(_isVerifying ? 'Verifying…' : 'Run verification'),
            ),
          ),
          if (_result != null) ...[
            const SizedBox(height: 24),
            if (_isAliyunSelected &&
                !_result!.success &&
                _result!.apiAction ==
                    AliyunFaceVerificationResponseParser.initFaceVerifyAction)
              _buildAliyunInitErrorCard(_result!)
            else
              _buildResultCard(_result!),
          ],
          if (_metrics.records.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildMetricsSection(),
          ],
              ],
            ),
          ),
          if (_aliyunMetaInfoLoaderActive)
            AliyunMetaInfoLoader(
              key: _metaInfoLoaderKey,
              onMetaInfoReady: _onAliyunMetaInfoReady,
              onError: _onAliyunMetaInfoError,
            ),
        ],
      ),
    );
  }

  Widget _buildStepProgress() {
    final labels = _flow == VerificationFlow.pureApi
        ? ['Reference', 'Live video', 'Verify']
        : _flow == VerificationFlow.saasH5
            ? ['Reference', 'H5 session', 'Liveness', 'Verify']
            : ['Reference', 'SdkToken', 'Liveness', 'Verify'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0)
                Expanded(
                  child: Container(
                    height: 2,
                    color: _currentStep > i + 1
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade300,
                  ),
                ),
              _buildStepDot(step: i + 1, label: labels[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStepDot({required int step, required String label}) {
    final active = _currentStep >= step;
    final finalStep = _flow == VerificationFlow.pureApi ? 3 : 4;
    final complete =
        _currentStep > step || (step == finalStep && _result?.success == true);

    return Column(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: complete
              ? Colors.green
              : active
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.shade300,
          child: complete
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : Text(
                  '$step',
                  style: TextStyle(
                    color: active ? Colors.white : Colors.black54,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }

  Widget _buildStatusBanner(String message) {
    final showCancel = _isAliyunSelected &&
        _flow == VerificationFlow.saasH5 &&
        _loading &&
        (message.startsWith('Preparing') ||
            message.startsWith('Calling InitFaceVerify'));

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (_loading && showCancel)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.info_outline),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
            if (showCancel)
              TextButton(
                onPressed: _cancelAliyunH5SessionWait,
                child: const Text('Cancel'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAliyunDebugOverlay() {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.bug_report, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aliyun trace',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Text(
                    _aliyunDebugStep ?? '',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (_loading)
                    Text(
                      _aliyunWaitSeconds > 0
                          ? 'Waiting… ${_aliyunWaitSeconds}s'
                          : 'Loading…',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Provider', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<FaceVerificationProvider>(
              value: _selectedProvider,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: _providers
                  .map(
                    (p) => DropdownMenuItem(
                      value: p,
                      child: Text(p.displayName),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedProvider = value;
                  if (value is BaiduFaceVerificationService &&
                      _flow == VerificationFlow.saasNativeSdk) {
                    _flow = VerificationFlow.pureApi;
                  }
                  if (value is AliyunFaceVerificationService) {
                    _flow = VerificationFlow.saasH5;
                    _aliyunH5Method = AliyunH5LivenessMethod.defaultMethod;
                    final defaultIndex =
                        AliyunH5LivenessMethod.all.indexOf(_aliyunH5Method);
                    if (defaultIndex >= 0) {
                      _aliyunH5TabController.index = defaultIndex;
                    }
                  }
                  if (value is FinAuthFaceVerificationService) {
                    _flow = VerificationFlow.saasH5;
                    _finAuthH5Method = FinAuthH5LivenessMethod.fromEnv();
                    final defaultIndex =
                        FinAuthH5LivenessMethod.all.indexOf(_finAuthH5Method);
                    if (defaultIndex >= 0) {
                      _finAuthH5TabController.index = defaultIndex;
                    }
                  }
                  _result = null;
                  _liveVideoBytes = null;
                  _resetH5SessionState();
                  _statusMessage = null;
                  _aliyunDebugStep = null;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBaiduH5MethodTabs() {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('H5 liveness method', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Each tab uses a different faceprint plan_id (与上传照片比对).',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TabBar(
              controller: _baiduH5TabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              indicatorColor: theme.colorScheme.primary,
              dividerColor: Colors.transparent,
              onTap: (index) =>
                  _onBaiduH5MethodChanged(BaiduH5LivenessMethod.all[index]),
              tabs: [
                for (final method in BaiduH5LivenessMethod.all)
                  Tab(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(method.tabLabel),
                        Text(
                          method.planId,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Selected: ${_baiduH5Method.label}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAliyunH5MethodTabs() {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('H5 liveness model', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'InitFaceVerify Model param for PV_FV (face contrast + liveness).',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TabBar(
              controller: _aliyunH5TabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              indicatorColor: theme.colorScheme.primary,
              dividerColor: Colors.transparent,
              onTap: (index) =>
                  _onAliyunH5MethodChanged(AliyunH5LivenessMethod.all[index]),
              tabs: [
                for (final method in AliyunH5LivenessMethod.all)
                  Tab(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(method.tabLabel),
                        Text(
                          method.model,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Selected: ${_aliyunH5Method.label}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinAuthH5MethodTabs() {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('H5 liveness method', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'get_token procedure_type for FinAuth H5 Lite overseas.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TabBar(
              controller: _finAuthH5TabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              indicatorColor: theme.colorScheme.primary,
              dividerColor: Colors.transparent,
              onTap: (index) =>
                  _onFinAuthH5MethodChanged(FinAuthH5LivenessMethod.all[index]),
              tabs: [
                for (final method in FinAuthH5LivenessMethod.all)
                  Tab(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(method.tabLabel),
                        Text(
                          method.procedureType,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Selected: ${_finAuthH5Method.label}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  String _verificationStepSubtitle() {
    if (_isBaiduSelected && _flow == VerificationFlow.pureApi) {
      return 'Video liveness on live clip, then 1:1 match vs reference (threshold ${AppConfig.baiduMatchThreshold.toStringAsFixed(0)}).';
    }
    if (_isBaiduSelected && _flow == VerificationFlow.saasH5) {
      return '${_baiduH5Method.label} · polls faceprint/result/detail after WebView.';
    }
    if (_isAliyunSelected && _flow == VerificationFlow.saasH5) {
      return '${_aliyunH5Method.label} · polls DescribeFaceVerify after WebView.';
    }
    if (_isFinAuthSelected && _flow == VerificationFlow.saasH5) {
      return '${_finAuthH5Method.label} · polls get_result after WebView (threshold ${AppConfig.finauthMatchThresholdKey}).';
    }
    if (_flow == VerificationFlow.pureApi) {
      return 'Calls CompareFaceLiveness (intl) or LivenessCompare (domestic).';
    }
    if (_flow == VerificationFlow.saasH5) {
      return 'Polls GetWebVerificationResultIntl after H5 WebView completes.';
    }
    return 'Polls GetFaceIdResultIntl after SDK completes.';
  }

  Widget _buildFlowSelector() {
    final segments = <ButtonSegment<VerificationFlow>>[
      if (_supportsPureApi)
        const ButtonSegment(
          value: VerificationFlow.pureApi,
          label: Text('Pure API'),
          icon: Icon(Icons.http),
        ),
      const ButtonSegment(
        value: VerificationFlow.saasH5,
        label: Text('SaaS H5'),
        icon: Icon(Icons.language),
      ),
      if (_supportsNativeSdk)
        const ButtonSegment(
          value: VerificationFlow.saasNativeSdk,
          label: Text('Native SDK'),
          icon: Icon(Icons.phone_android),
        ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Flow', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<VerificationFlow>(
              segments: segments,
              selected: {_flow},
              onSelectionChanged: (value) {
                setState(() {
                  _flow = value.first;
                  _result = null;
                  _liveVideoBytes = null;
                  _sdkToken = null;
                  _verificationUrl = null;
                  _livenessComplete = false;
                  _statusMessage = null;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCredentialsWarning() {
    final provider = _selectedProvider;
    final message = switch (provider) {
      BaiduFaceVerificationService() =>
        'Baidu credentials missing. Set BAIDU_API_KEY and BAIDU_SECRET_KEY in .env.',
      AliyunFaceVerificationService() =>
        'Aliyun credentials missing. Set ALIYUN_ACCESS_KEY_ID, ALIYUN_ACCESS_KEY_SECRET, and ALIYUN_CLOUDAUTH_SCENE_ID in .env.',
      FinAuthFaceVerificationService() =>
        'FinAuth credentials missing. Set FINAUTH_API_KEY and FINAUTH_API_SECRET in .env.',
      _ =>
        'Tencent credentials missing. Copy .env.example to .env and add your SecretId/SecretKey.',
    };
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.warning_amber,
                color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepCard({
    required int step,
    required bool complete,
    required String title,
    String? subtitle,
    Widget? child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  complete ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: complete ? Colors.green : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Step $step: $title',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            if (child != null) ...[
              const SizedBox(height: 12),
              child,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview({
    required Uint8List? bytes,
    required String placeholder,
  }) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade400),
        ),
        child: bytes == null
            ? Center(child: Text(placeholder))
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
      ),
    );
  }

  Widget _buildVideoStatus() {
    if (_liveVideoBytes == null) {
      return const Text('No live video recorded yet.');
    }
    final encodedMb =
        (MediaUtils.base64EncodedLength(_liveVideoBytes!) / (1024 * 1024))
            .toStringAsFixed(2);
    return Text(
      'Live video captured (${MediaUtils.formatBytes(_liveVideoBytes!.length)}, '
      '~$encodedMb MB encoded). Ready to verify.',
    );
  }

  Widget _buildAliyunInitErrorCard(FaceVerificationResult result) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Text(
                  'InitFaceVerify 失败',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (result.errorCode != null)
              _infoRow('Code', result.errorCode!),
            if (result.errorMessage != null)
              _infoRow('Message', result.errorMessage!),
            if (result.errorExplanationZh != null)
              _infoRow('说明', result.errorExplanationZh!),
            if (result.requestId != null)
              _infoRow('RequestId', result.requestId!),
            if (result.errorSuggestedFix != null) ...[
              const SizedBox(height: 8),
              Text(
                '建议排查',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                result.errorSuggestedFix!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ],
            if (result.latency.inMilliseconds > 0)
              _infoRow('耗时', '${result.latency.inMilliseconds} ms'),
            if (_aliyunDebugStep != null)
              _infoRow('Last step', _aliyunDebugStep!),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(FaceVerificationResult result) {
    final theme = Theme.of(context);
    final apiSucceeded = result.success;
    final overallPass = apiSucceeded && result.isMatch && result.isLive;

    return Card(
      color: apiSucceeded
          ? (overallPass
              ? Colors.green.shade50
              : theme.colorScheme.surfaceContainerHighest)
          : theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  !apiSucceeded
                      ? Icons.error_outline
                      : overallPass
                          ? Icons.verified
                          : Icons.warning_amber,
                  color: !apiSucceeded
                      ? theme.colorScheme.error
                      : overallPass
                          ? Colors.green.shade700
                          : Colors.orange.shade800,
                ),
                const SizedBox(width: 8),
                Text(
                  !apiSucceeded
                      ? 'API error'
                      : overallPass
                          ? 'Verification passed'
                          : 'Verification completed',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!result.success) ...[
              Text(
                result.errorMessage ??
                    result.description ??
                    'Verification failed',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              if (result.errorExplanationZh != null) ...[
                const SizedBox(height: 8),
                _infoRow('说明', result.errorExplanationZh!),
              ],
              if (result.errorSuggestedFix != null) ...[
                const SizedBox(height: 4),
                _infoRow('建议', result.errorSuggestedFix!),
              ],
              if (result.errorCode != null)
                _infoRow('Code', result.errorCode!),
              if (result.requestId != null)
                _infoRow('RequestId', result.requestId!),
            ] else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statusChip('Match', result.isMatch),
                  _statusChip('Liveness', result.isLive),
                ],
              ),
              const SizedBox(height: 12),
              _infoRow('Provider', result.providerName),
              if (result.apiAction != null)
                _infoRow('API', result.apiAction!),
              if (result.similarity != null)
                _infoRow('Similarity', '${result.similarity!.toStringAsFixed(2)} / 100'),
              if (result.resultCode != null)
                _infoRow('Result code', result.resultCode!),
              if (result.description != null)
                _infoRow('Description', result.description!),
              _infoRow('Latency', '${result.latency.inMilliseconds} ms'),
              if (result.requestId != null)
                _infoRow('Request ID', result.requestId!),
              if (result.sdkToken != null &&
                  (_flow == VerificationFlow.saasH5 ||
                      _flow == VerificationFlow.saasNativeSdk))
                _infoRow(
                  _flow == VerificationFlow.saasH5
                      ? (_isBaiduSelected ? 'verify_token' : 'BizToken')
                      : 'SdkToken',
                  result.sdkToken!,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String label, bool passed) {
    return Chip(
      avatar: Icon(
        passed ? Icons.check : Icons.close,
        size: 16,
        color: passed ? Colors.green.shade800 : Colors.red.shade800,
      ),
      label: Text('$label: ${passed ? 'Pass' : 'Fail'}'),
      backgroundColor: passed ? Colors.green.shade100 : Colors.red.shade100,
    );
  }

  Widget _buildMetricsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Recent metrics',
                    style: Theme.of(context).textTheme.titleMedium),
                TextButton(
                  onPressed: () => setState(_metrics.clear),
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._metrics.records.take(5).map(
                  (m) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      m.success ? Icons.check_circle : Icons.error,
                      color: m.success ? Colors.green : Colors.red,
                    ),
                    title: Text(
                      '${m.providerName} — ${m.latency.inMilliseconds} ms',
                    ),
                    subtitle: Text(
                      m.success
                          ? 'match=${m.isMatch}, live=${m.isLive}, sim=${m.similarity?.toStringAsFixed(1) ?? "n/a"}'
                          : m.errorMessage ?? 'Failed',
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
