import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static Future<void> load() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // `.env` is optional during development; credentials can be empty.
    }
  }

  static String _env(String key, [String fallback = '']) {
    if (!dotenv.isInitialized) return fallback;
    return dotenv.env[key] ?? fallback;
  }

  /// Public env accessor for models that map plan IDs to H5 liveness methods.
  static String envValue(String key, [String fallback = '']) => _env(key, fallback);

  static String get tencentSecretId => _env('TENCENT_SECRET_ID');

  static String get tencentSecretKey => _env('TENCENT_SECRET_KEY');

  static String get tencentRegion =>
      _env('TENCENT_REGION', 'ap-singapore');

  /// FaceID API host (product 1061).
  /// International: faceid.intl.tencentcloudapi.com
  /// Domestic: faceid.tencentcloudapi.com
  static String get tencentFaceIdHost =>
      _env('TENCENT_FACEID_HOST', 'faceid.intl.tencentcloudapi.com');

  /// SILENT or ACTION for pure-API liveness compare.
  static String get tencentFaceIdLivenessType =>
      _env('TENCENT_FACEID_LIVENESS_TYPE', 'SILENT');

  /// Required when LivenessType=ACTION. Example: "2" (blink) or "4,2".
  static String get tencentFaceIdValidateData =>
      _env('TENCENT_FACEID_VALIDATE_DATA');

  /// SaaS SDK secure level: 1–4 (default 4 = motion + reflection).
  static String get tencentFaceIdSecureLevel =>
      _env('TENCENT_FACEID_SECURE_LEVEL', '4');

  /// SaaS SDK version: BASIC, ENHANCED, PRO, PLUS.
  static String get tencentFaceIdSdkVersion =>
      _env('TENCENT_FACEID_SDK_VERSION', 'BASIC');

  /// Optional RuleId for domestic GetFaceIdToken / H5 ApplyWebVerification.
  static String get tencentFaceIdRuleId => _env('TENCENT_FACEID_RULE_ID');

  /// H5 redirect URL passed to ApplyWebVerificationBizToken(Intl).
  /// Tencent appends `?token={BizToken}` after liveness completes.
  static String get tencentFaceIdH5RedirectUrl => _env(
        'TENCENT_FACEID_H5_REDIRECT_URL',
        'https://facedetection.local/liveness/callback',
      );

  /// When true, H5 Config.AutoSkip skips Tencent's result page on success.
  static bool get tencentFaceIdH5AutoSkip =>
      _env('TENCENT_FACEID_H5_AUTO_SKIP', 'false').toLowerCase() == 'true';

  static bool get hasTencentCredentials =>
      tencentSecretId.isNotEmpty && tencentSecretKey.isNotEmpty;

  static String get baiduApiKey => _env('BAIDU_API_KEY');

  static String get baiduSecretKey => _env('BAIDU_SECRET_KEY');

  static bool get hasBaiduCredentials =>
      baiduApiKey.isNotEmpty && baiduSecretKey.isNotEmpty;

  /// H5 redirect base URL. App embeds verify_token as ?token= for WebView detection.
  static String get baiduFaceprintH5CallbackUrl => _env(
        'BAIDU_FACEPRINT_H5_CALLBACK_URL',
        'https://facedetection.local/baidu/h5/callback',
      );

  static bool get hasBaiduH5Config => hasBaiduCredentials;

  /// Baidu face match pass threshold (recommended 80).
  static double get baiduMatchThreshold =>
      double.tryParse(_env('BAIDU_MATCH_THRESHOLD', '80')) ?? 80;

  /// Baidu video liveness threshold key: frr_1e-4, frr_1e-3, frr_1e-2.
  static String get baiduLivenessThresholdKey =>
      _env('BAIDU_LIVENESS_THRESHOLD_KEY', 'frr_1e-3');

  /// NONE, LOW, NORMAL, HIGH — applied to live image in face/v3/match.
  static String get baiduLivenessControl =>
      _env('BAIDU_LIVENESS_CONTROL', 'NORMAL');

  /// NONE, LOW, NORMAL, HIGH — quality control for match images.
  static String get baiduQualityControl =>
      _env('BAIDU_QUALITY_CONTROL', 'NORMAL');

  static String get aliyunAccessKeyId => _env('ALIYUN_ACCESS_KEY_ID');

  static String get aliyunAccessKeySecret => _env('ALIYUN_ACCESS_KEY_SECRET');

  static String get aliyunCloudAuthSceneId => _env('ALIYUN_CLOUDAUTH_SCENE_ID');

  static String get aliyunCloudAuthRegionId =>
      _env('ALIYUN_CLOUDAUTH_REGION_ID', 'cn-shanghai');

  /// H5 ReturnUrl — Aliyun redirects here with ?response= JSON after liveness.
  /// A `.local` URL is fine for signature debugging but will not receive real
  /// H5 redirects; use a public HTTPS URL in production.
  static String get aliyunCloudAuthReturnUrl => _env(
        'ALIYUN_CLOUDAUTH_RETURN_URL',
        'https://facedetection.local/aliyun/h5/callback',
      );

  /// InitFaceVerify Model param. Default MOVE_ACTION (recommended).
  static String get aliyunCloudAuthModel =>
      _env('ALIYUN_CLOUDAUTH_MODEL', 'MOVE_ACTION');

  /// InitFaceVerify Crop: T allows face crop for non-SDK photos (recommended).
  static String get aliyunCloudAuthCrop =>
      _env('ALIYUN_CLOUDAUTH_CROP', 'T');

  static String get aliyunCloudAuthUserId =>
      _env('ALIYUN_CLOUDAUTH_USER_ID', 'facedetection-demo-user');

  /// Server-side callback URL (GET with certifyId + passed). Omit for minimal InitFaceVerify.
  static String get aliyunCloudAuthCallbackUrl =>
      _env('ALIYUN_CLOUDAUTH_CALLBACK_URL');

  /// Willingness agreement JSON array for voluntary auth scenes. Omit for minimal InitFaceVerify.
  static String get aliyunCloudAuthVoluntaryCustomizedContent =>
      _env('ALIYUN_CLOUDAUTH_VOLUNTARY_CUSTOMIZED_CONTENT');

  /// End-user IP reported to CloudAuth. Omit for minimal InitFaceVerify.
  static String get aliyunCloudAuthSourceIp => _env('ALIYUN_CLOUDAUTH_SOURCE_IP');

  /// InitFaceVerify face contrast URL override. Empty unless
  /// `ALIYUN_CLOUDAUTH_FACE_CONTRAST_PICTURE_URL` is explicitly set in `.env`.
  static String get aliyunCloudAuthFaceContrastPictureUrl {
    if (!dotenv.isInitialized) return '';
    if (!dotenv.env.containsKey('ALIYUN_CLOUDAUTH_FACE_CONTRAST_PICTURE_URL')) {
      return '';
    }
    return dotenv.env['ALIYUN_CLOUDAUTH_FACE_CONTRAST_PICTURE_URL'] ?? '';
  }

  /// When true, InitFaceVerify sends FaceContrastPictureUrl only (no base64).
  /// Only enabled when `ALIYUN_CLOUDAUTH_FACE_CONTRAST_PICTURE_URL` is set to a
  /// non-empty value; default is base64 FaceContrastPicture from the reference photo.
  static bool get aliyunUsesFaceContrastPictureUrl {
    if (!dotenv.isInitialized) return false;
    if (!dotenv.env.containsKey('ALIYUN_CLOUDAUTH_FACE_CONTRAST_PICTURE_URL')) {
      return false;
    }
    return (dotenv.env['ALIYUN_CLOUDAUTH_FACE_CONTRAST_PICTURE_URL'] ?? '')
        .trim()
        .isNotEmpty;
  }

  /// When set, replaces WebView getMetaInfo() (Explorer-style static MetaInfo for testing).
  static String get aliyunCloudAuthMetaInfoOverride =>
      _env('ALIYUN_CLOUDAUTH_METAINFO_OVERRIDE');

  /// Optional. Default `H5` for in-app WebView liveness (CertifyUrl).
  /// Set empty to omit CertifyUrlType for CertifyId-only responses.
  static String get aliyunCloudAuthCertifyUrlType =>
      _env('ALIYUN_CLOUDAUTH_CERTIFY_URL_TYPE', 'H5');

  /// Optional CertifyUrlStyle when [aliyunCloudAuthCertifyUrlType] is set: S or L.
  static String get aliyunCloudAuthCertifyUrlStyle =>
      _env('ALIYUN_CLOUDAUTH_CERTIFY_URL_STYLE');

  /// Optional ProcedurePriority when [aliyunCloudAuthCertifyUrlType] is set.
  static String get aliyunCloudAuthProcedurePriority =>
      _env('ALIYUN_CLOUDAUTH_PROCEDURE_PRIORITY');

  /// verifyScore pass threshold from DescribeFaceVerify MaterialInfo.
  static double get aliyunMatchThreshold =>
      double.tryParse(_env('ALIYUN_MATCH_THRESHOLD', '70')) ?? 70;

  static bool get hasAliyunCredentials =>
      aliyunAccessKeyId.isNotEmpty && aliyunAccessKeySecret.isNotEmpty;

  static bool get hasAliyunH5Config =>
      hasAliyunCredentials && aliyunCloudAuthSceneId.isNotEmpty;

  /// When true, writes FaceContrastPicture base64 to temp files for debugging.
  static bool get aliyunDebugDumpFaceContrastBase64 =>
      _env('ALIYUN_DEBUG_DUMP_FACE_CONTRAST', 'false').toLowerCase() == 'true';

  /// When true, logs the full local `stringToSign` in AliyunTrace request JSON.
  static bool get aliyunLogStringToSign =>
      _env('ALIYUN_LOG_STRING_TO_SIGN', 'false').toLowerCase() == 'true';

  // --- Megvii FinAuth H5 Lite (overseas) ---

  static String get finauthApiKey => _env('FINAUTH_API_KEY');

  static String get finauthApiSecret => _env('FINAUTH_API_SECRET');

  /// Overseas API host (default api-global.yljz.com). Regional hosts may differ.
  static String get finauthApiHost =>
      _env('FINAUTH_API_HOST', 'api-global.yljz.com');

  /// DoVerification base URL (GET ?token=). Default matches overseas docs.
  static String get finauthDoVerificationBase => _env(
        'FINAUTH_DO_VERIFICATION_BASE',
        'https://api-global.yljz.com/finauth/lite/do',
      );

  /// return_url — FinAuth redirects here after H5 liveness (GET appends ?biz_id=).
  static String get finauthH5ReturnUrl => _env(
        'FINAUTH_H5_RETURN_URL',
        'https://facedetection.local/finauth/h5/callback',
      );

  /// notify_url — required by get_token (server POST callback; not used in-app POC).
  static String get finauthNotifyUrl => _env(
        'FINAUTH_NOTIFY_URL',
        'https://facedetection.local/finauth/notify',
      );

  /// Optional console scene_id for H5 theme / flow config.
  static String get finauthSceneId => _env('FINAUTH_SCENE_ID');

  /// User uuid for get_token (comparison_type=0 or -1).
  static String get finauthUserUuid =>
      _env('FINAUTH_USER_UUID', 'facedetection-demo-user');

  /// Face compare (0) or liveness-only (-1).
  static String get finauthComparisonType =>
      _env('FINAUTH_COMPARISON_TYPE', '0');

  /// flash, distance, or still.
  static String get finauthProcedureType =>
      _env('FINAUTH_PROCEDURE_TYPE', 'flash');

  static String get finauthProcedurePriority =>
      _env('FINAUTH_PROCEDURE_PRIORITY');

  /// Page language: 0=en, 1=zh, 2=id, 3=th, etc.
  static String get finauthLanguage => _env('FINAUTH_LANGUAGE', '0');

  /// GET recommended for WebView callback detection (?biz_id=); POST returns form body.
  static String get finauthActionHttpMethod =>
      _env('FINAUTH_ACTION_HTTP_METHOD', 'GET');

  /// redirect_type when action_http_method=GET (0 default, 1 replace history).
  static String get finauthRedirectType => _env('FINAUTH_REDIRECT_TYPE');

  /// fmp_mode: 0=include cloud anti-spoof in liveness_result; 1=scores only.
  static String get finauthFmpMode => _env('FINAUTH_FMP_MODE', '0');

  /// verify_result.result_ref1 confidence threshold key: 1e-3, 1e-4, 1e-5, 1e-6.
  static String get finauthMatchThresholdKey =>
      _env('FINAUTH_MATCH_THRESHOLD_KEY', '1e-4');

  static bool get hasFinAuthCredentials =>
      finauthApiKey.isNotEmpty && finauthApiSecret.isNotEmpty;

  static bool get hasFinAuthH5Config => hasFinAuthCredentials;
}
