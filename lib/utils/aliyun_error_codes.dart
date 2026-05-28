/// Human-readable Aliyun CloudAuth error codes for InitFaceVerify / DescribeFaceVerify.
class AliyunErrorInfo {
  const AliyunErrorInfo({
    required this.code,
    required this.chineseExplanation,
    required this.suggestedFix,
  });

  final String code;
  final String chineseExplanation;
  final String suggestedFix;
}

/// Maps Aliyun API [Code] and DescribeFaceVerify [SubCode] to Chinese explanations.
class AliyunErrorCodes {
  AliyunErrorCodes._();

  static const _initFaceVerifyCodes = <String, AliyunErrorInfo>{
    '200': AliyunErrorInfo(
      code: '200',
      chineseExplanation: '成功',
      suggestedFix: '无需处理。',
    ),
    '400': AliyunErrorInfo(
      code: '400',
      chineseExplanation: '参数不能为空',
      suggestedFix:
          '检查 SceneId、MetaInfo、ReturnUrl、UserId、Model 等必填参数是否已传入。',
    ),
    '401': AliyunErrorInfo(
      code: '401',
      chineseExplanation: '参数非法',
      suggestedFix:
          '核对 Model 值（如 MOVE_ACTION）、ProductCode=PV_FV、SceneId，'
          '以及 MetaInfo 是否来自 getMetaInfo()（Explorer 静态 MetaInfo 仅用于联调）。'
          'WebView 活体需设置 ALIYUN_CLOUDAUTH_CERTIFY_URL_TYPE=H5。',
    ),
    '402': AliyunErrorInfo(
      code: '402',
      chineseExplanation: '应用配置不存在',
      suggestedFix:
          '登录阿里云实人认证控制台，确认已创建应用并绑定当前 AccessKey 所属账号。',
    ),
    '404': AliyunErrorInfo(
      code: '404',
      chineseExplanation: '认证场景配置不存在',
      suggestedFix:
          '在控制台检查 ALIYUN_CLOUDAUTH_SCENE_ID 是否与 PV_FV 人脸比对场景 ID 一致，'
          '且场景已启用 H5 认证。',
    ),
    '410': AliyunErrorInfo(
      code: '410',
      chineseExplanation: '未开通服务或 OSS 未配置',
      suggestedFix:
          '在阿里云控制台开通实人认证 CloudAuth 服务，并确认 OSS 相关配置已完成。',
    ),
    '411': AliyunErrorInfo(
      code: '411',
      chineseExplanation: 'RAM 无权限',
      suggestedFix:
          '为当前 AccessKey 对应 RAM 用户/角色添加 cloudauth:InitFaceVerify、'
          'cloudauth:DescribeFaceVerify 权限。',
    ),
    '412': AliyunErrorInfo(
      code: '412',
      chineseExplanation: '欠费',
      suggestedFix: '检查阿里云账户余额与实人认证服务是否欠费停服。',
    ),
    '417': AliyunErrorInfo(
      code: '417',
      chineseExplanation: '自定义比对源图片特征提取失败',
      suggestedFix:
          '换一张清晰正脸照片；确保 JPEG/PNG、单人脸、无遮挡，且压缩后 ≤3 MB。',
    ),
    '419': AliyunErrorInfo(
      code: '419',
      chineseExplanation: '传入图片不可用',
      suggestedFix:
          '确认 FaceContrastPicture 为有效 JPEG/PNG，非损坏文件，且仅通过一种方式传图。',
    ),
    '420': AliyunErrorInfo(
      code: '420',
      chineseExplanation: '数据重复（多种传图方式）',
      suggestedFix: '仅使用 FaceContrastPicture 传基准图，不要同时传 FaceContrastPictureUrl。',
    ),
    '421': AliyunErrorInfo(
      code: '421',
      chineseExplanation: '传入图片过大',
      suggestedFix: '将基准图压缩至 3 MB 以内（App 已自动压缩，可换更小原图重试）。',
    ),
    '500': AliyunErrorInfo(
      code: '500',
      chineseExplanation: '系统错误',
      suggestedFix: '稍后重试；若持续失败，携带 RequestId 提交阿里云工单。',
    ),
    'SignatureDoesNotMatch': AliyunErrorInfo(
      code: 'SignatureDoesNotMatch',
      chineseExplanation: 'RPC 签名不匹配',
      suggestedFix:
          '1) 核对 ALIYUN_ACCESS_KEY_SECRET 无首尾空格；'
          '2) InitFaceVerify 使用全参数 POST body（避免 query+body 导致 %252F）；'
          '3) 确认未二次 URL 编码（logcat 中不应出现 %252F）；'
          '4) 查看 [AliyunTrace] signature_mismatch 与 queryLen/bodyLen。',
    ),
    'InvalidAccessKeyId.NotFound': AliyunErrorInfo(
      code: 'InvalidAccessKeyId.NotFound',
      chineseExplanation: 'AccessKeyId 不存在',
      suggestedFix: '核对 .env 中 ALIYUN_ACCESS_KEY_ID 是否正确。',
    ),
    'IncompleteSignature': AliyunErrorInfo(
      code: 'IncompleteSignature',
      chineseExplanation: '签名参数不完整',
      suggestedFix: '检查签名算法与必填公共参数（Timestamp、SignatureNonce 等）。',
    ),
  };

  /// DescribeFaceVerify ResultObject.SubCode values.
  static const _describeSubCodes = <String, AliyunErrorInfo>{
    '200': AliyunErrorInfo(
      code: '200',
      chineseExplanation: '认证通过',
      suggestedFix: '无需处理。',
    ),
    'Z5050': AliyunErrorInfo(
      code: 'Z5050',
      chineseExplanation: '认证通过',
      suggestedFix: 'H5 流程已完成，可正常读取比对分数。',
    ),
    'Z5051': AliyunErrorInfo(
      code: 'Z5051',
      chineseExplanation: '认证未通过',
      suggestedFix: '用户未完成活体或人脸比对未达标，请重新发起认证。',
    ),
    'Z5052': AliyunErrorInfo(
      code: 'Z5052',
      chineseExplanation: '认证未完成',
      suggestedFix: '用户在 H5 页面中途退出，需重新打开 CertifyUrl 完成活体。',
    ),
    'Z5053': AliyunErrorInfo(
      code: 'Z5053',
      chineseExplanation: '认证超时',
      suggestedFix: 'H5 认证页超时关闭，请重新 Request H5 Session。',
    ),
    'Z5054': AliyunErrorInfo(
      code: 'Z5054',
      chineseExplanation: '认证失败（系统）',
      suggestedFix: '携带 RequestId 查看阿里云控制台认证记录或提交工单。',
    ),
    'Z5055': AliyunErrorInfo(
      code: 'Z5055',
      chineseExplanation: '认证失败（用户取消）',
      suggestedFix: '用户主动取消，重新点击 Start H5 Liveness。',
    ),
    'Z5056': AliyunErrorInfo(
      code: 'Z5056',
      chineseExplanation: '认证失败（网络异常）',
      suggestedFix: '检查设备网络/VPN，确保 H5 页面可访问阿里云域名。',
    ),
    'Z5057': AliyunErrorInfo(
      code: 'Z5057',
      chineseExplanation: '认证失败（设备不支持）',
      suggestedFix: '更换支持摄像头的设备或更新 WebView/Chrome 内核。',
    ),
    'Z5058': AliyunErrorInfo(
      code: 'Z5058',
      chineseExplanation: '认证失败（活体检测未通过）',
      suggestedFix: '在光线充足环境下重新做活体动作。',
    ),
    'Z5059': AliyunErrorInfo(
      code: 'Z5059',
      chineseExplanation: '认证失败（人脸比对未通过）',
      suggestedFix: '确保 H5 采集人脸与基准图是同一人，且基准图清晰正脸。',
    ),
  };

  /// Resolves [code] (InitFaceVerify/DescribeFaceVerify top-level Code or RPC error).
  /// When [subCode] is provided (DescribeFaceVerify), it takes precedence for explanation.
  static AliyunErrorInfo resolve({
    String? code,
    String? subCode,
    String? apiMessage,
  }) {
    if (subCode != null && subCode.isNotEmpty) {
      final sub = _describeSubCodes[subCode];
      if (sub != null) return sub;
    }

    final normalized = code?.trim() ?? '';
    if (normalized.isNotEmpty) {
      final known = _initFaceVerifyCodes[normalized];
      if (known != null) return known;

      if (normalized.contains('SignatureDoesNotMatch')) {
        return _initFaceVerifyCodes['SignatureDoesNotMatch']!;
      }
    }

    return AliyunErrorInfo(
      code: normalized.isEmpty ? 'Unknown' : normalized,
      chineseExplanation: apiMessage?.isNotEmpty == true
          ? apiMessage!
          : '未知错误码',
      suggestedFix: normalized.isEmpty
          ? '查看 logcat [AliyunTrace] 完整日志，携带 RequestId 排查。'
          : '携带 Code=$normalized 与 RequestId 查阅阿里云实人认证文档或提交工单。',
    );
  }

  /// All InitFaceVerify / RPC codes for reference tables.
  static Map<String, AliyunErrorInfo> get initFaceVerifyCodes =>
      Map.unmodifiable(_initFaceVerifyCodes);

  /// DescribeFaceVerify SubCode reference.
  static Map<String, AliyunErrorInfo> get describeSubCodes =>
      Map.unmodifiable(_describeSubCodes);
}
