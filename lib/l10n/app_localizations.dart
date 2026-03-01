import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('zh'),
  ];

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'appTitle': 'RePhone Security',
      'tabCameras': 'Cameras',
      'tabMembership': 'Membership',
      'tabProfile': 'Profile',
      'settingsGeneral': 'General settings',
      'settingsLanguage': 'Language',
      'settingsLanguageFollowSystem': 'Follow system',
      'settingsLanguageChinese': 'Chinese',
      'settingsLanguageEnglish': 'English',
      'settingsAppPermissions': 'App permissions',
      'settingsAppPermissionsSubtitle': 'Manage camera and microphone permissions',
      'settingsResetPassword': 'Reset password',
      'settingsResetPasswordSubtitle': 'Change current account password',
      'settingsDeleteAccount': 'Delete account',
      'settingsDeleteAccountSubtitle': 'Permanently delete account and all data',
      'settingsLogout': 'Log out',
      'settingsLogoutSubtitle': 'Sign out from current account',
      'settingsLogoutDialogTitle': 'Log out',
      'settingsLogoutDialogContent': 'Are you sure you want to log out?',
      'settingsLogoutDialogCancel': 'Cancel',
      'settingsLogoutDialogConfirm': 'Confirm',
      'settingsLogoutSuccess': 'Logged out',
      'languagePageTitle': 'Language',
      'languageOptionSystem': 'Follow system',
      'languageOptionChinese': 'Chinese',
      'languageOptionEnglish': 'English',
      'languageOptionSystemDetail': 'Automatically match Chinese or English',
      'languageOptionChineseDetail': 'Always use Chinese',
      'languageOptionEnglishDetail': 'Always use English',
      'authTitle': 'Sign in / Register',
      'authChooseMethod': 'Choose sign-in method',
      'authDesc': 'Sign in to sync devices and view alerts at any time.',
      'authEmailLogin': 'Sign in with email',
      'authScanToBind': 'Bind by scanning QR code',
      'authTermsPrefix': 'By continuing you agree to',
      'authTermsLink': 'Terms of Service',
      'authPrivacyLink': 'Privacy Policy',
      'welcomeTitle': 'Welcome to RePhone Security',
      'welcomeDesc': 'Turn old phones into home security cameras easily.',
      'welcomeButton': 'Start now',
      'welcomeFooter': 'Sign in once to start cross-device protection.',
      'aboutTitle': 'About us',
      'aboutTerms': 'Terms of Service',
      'aboutPrivacy': 'Privacy Policy',
      'aboutView': 'Tap to view',
      'helpCenterTitle': 'Help center',
      'helpFeedback': 'Feedback',
      'helpFeedbackHint': 'Describe issues, feature requests or suggestions...',
      'helpContactOptional': 'Contact (optional)',
      'helpContactHint': 'WeChat / phone number (optional)',
      'helpSubmit': 'Submit feedback',
      'helpSubmitting': 'Submitting...',
      'helpFeedbackEmpty': 'Please enter feedback content',
      'helpFeedbackTooLong': 'Feedback is too long (max 5000 characters)',
      'helpFeedbackThanks': 'Thanks, we will handle it soon',
      'helpEmailFeedback': 'Email feedback',
      'helpEmailTip': 'You can also send email to this address',
      'helpEmailCopied': 'Email copied',
      'helpCopyEmail': 'Copy email',
      'cameraListTitle': 'Cameras',
      'cameraListEmpty': 'No cameras yet',
      'cameraListEmptyHint': 'Bind a device by scanning QR code.',
      'cameraListBindButton': 'Bind camera',
      'cameraListAsMonitor': 'Use as monitor',
      'cameraListAsCamera': 'Use as camera',
      'cameraListUnnamed': 'Unnamed device',
      'cameraListUnknownLocation': 'Unknown location',
      'cameraListLoadFailed': 'Failed to load device list',
      'cameraListStatusOnline': 'Online',
      'cameraListStatusOffline': 'Offline',
      'cameraListTimeJustNow': 'Just now',
      'cameraListTimeMinutesAgo': '{minutes} minutes ago',
      'cameraListTimeHoursAgo': '{hours} hours ago',
      'cameraListTimeDaysAgo': '{days} days ago',
      'cameraListPleaseLogin': 'Please sign in first',
      'cameraListBindSuccess': 'Device bound successfully',
      'cameraDefaultLocationLivingRoom': 'Living room',
      'cameraListActionPlayback': 'Playback',
      'cameraListActionSettings': 'Settings',
      'cameraRoleMonitor': 'Monitor mode',
      'cameraRoleCamera': 'Camera mode',
      'qrScanTitle': 'Scan QR code',
      'qrScanProcessing': 'Binding...',
      'qrScanHint': 'Align the QR code within the frame',
      'qrGenerateTitle': 'Device QR code',
      'qrGenerateDesc': 'Scan with camera device to bind this account.',
      'qrGenerateMonitorEmailLabel': 'Monitor email: {email}',
      'qrGenerateWaitingForScan': 'Waiting for camera device to scan and bind...',
      'qrScanInvalidFormat': 'Invalid QR code format',
      'qrScanBindFailedPrefix': 'Binding failed: ',
      'appPermissionsTitle': 'App permissions',
      'appPermissionsCamera': 'Camera',
      'appPermissionsCameraSubtitle': 'Used for video call and monitoring',
      'appPermissionsMic': 'Microphone',
      'appPermissionsMicSubtitle': 'Used for voice talk and audio capture',
      'appPermissionsPhotos': 'Photos',
      'appPermissionsPhotosSubtitle': 'Used to save screenshots and recordings',
      'appPermissionsNote': 'Note: permission switches must be managed in system settings.',
      'resetPasswordTitle': 'Reset password',
      'resetPasswordOld': 'Current password',
      'resetPasswordNew': 'New password',
      'resetPasswordConfirm': 'Confirm new password',
      'resetPasswordSubmit': 'Submit',
      'resetPasswordSuccess': 'Password updated',
      'resetPasswordLoadUserFailed': 'Failed to load user info, please sign in again',
      'resetPasswordFailed': 'Update failed',
      'resetPasswordOldEmpty': 'Please enter current password',
      'resetPasswordNewEmpty': 'Please enter new password',
      'resetPasswordTooShort': 'Password must be at least 6 characters',
      'resetPasswordConfirmEmpty': 'Please confirm new password',
      'resetPasswordNotMatch': 'Passwords do not match',
      'deleteAccountTitle': 'Delete account',
      'deleteAccountDesc': 'This will permanently delete the account and all data.',
      'deleteAccountButton': 'Delete account',
      'deleteAccountConfirmTitle': 'Confirm delete',
      'deleteAccountConfirmContent': 'This operation cannot be undone. Continue?',
      'deleteAccountConfirmOk': 'Delete',
      'deleteAccountConfirmCancel': 'Cancel',
      'deleteAccountSuccess': 'Account deleted',
      'deleteAccountWarning': 'Warning: this action cannot be undone.',
      'deleteAccountPasswordTip': 'Enter your password to confirm.',
      'deleteAccountPasswordEmpty': 'Please enter password',
      'commonPassword': 'Password',
      'profileTitle': 'Profile',
      'profileMembership': 'Membership',
      'profileHelpCenter': 'Help center',
      'profileAbout': 'About us',
      'profileGeneralSettings': 'General settings',
      'profileNotLoggedIn': 'Not logged in',
      'profileSettingsTitle': 'Settings',
      'profileHelpCenterSubtitle': 'FAQs, contact support',
      'profileAboutSubtitle': 'Version info, user agreements',
      'profileGeneralSettingsSubtitle': 'Account deletion, log out',
      'profileOpenPagePrefix': 'Open ',
      'membershipTitle': 'Membership',
      'membershipPlanBasic': 'Basic',
      'membershipPlanPro': 'Premium',
      'membershipPlanCurrent': 'Current plan',
      'membershipPlanPricePerMonth': '{price}/month',
      'membershipFeatureNoDeviceLimit': 'No device limit',
      'membershipFeatureBasicCloudImages': '1-day cloud storage (images only)',
      'membershipFeatureProCloudPlayback': '3-day cloud video playback',
      'membershipFeatureLiveStreaming': 'Live streaming',
      'membershipFeatureNoAds': 'Ad-free experience',
      'membershipFeatureMoreComing': 'More features coming soon',
      'membershipActionSubscribe': 'Subscribe now',
      'membershipActionManage': 'Manage subscription',
      'membershipStatusPremium': 'Premium member',
      'membershipStatusBasic': 'Free user',
      'membershipExpiryPrefix': 'Expires on: ',
      'membershipSectionTitle': 'Membership benefits & plans',
      'membershipBadgeRecommended': 'Recommended',
      'membershipBadgeCurrent': 'Current',
      'membershipPriceFree': 'Free',
      'membershipDurationForever': 'Forever',
      'membershipDurationMonth': 'month',
      'membershipDurationYear': 'year',
      'membershipPlanMonthly': 'Monthly',
      'membershipPlanYearly': 'Yearly',
      'membershipFaqTitle': 'FAQ',
      'membershipFaqCancelTitle': 'How to cancel subscription?',
      'membershipFaqCancelContent':
          'You can cancel anytime in the App Store or Play Store subscription management. Cancellation takes effect at the end of the current billing period.',
      'membershipFaqEffectTitle': 'When does membership take effect?',
      'membershipFaqEffectContent':
          'After successful subscription, your membership takes effect immediately and you can use all premium features.',
      'membershipDialogUpgradeTitle': 'Upgrade membership',
      'membershipDialogUpgradeContent':
          'Upgrade to premium membership to unlock more powerful features.',
      'membershipDialogLater': 'Later',
      'membershipDialogSubscribeTitle': 'Subscribe plan',
      'membershipDialogSubscribeContent': 'Confirm to subscribe to this plan?',
      'membershipDialogProcessing': 'Processing subscription...',
      'membershipButtonUpgrade': 'Upgrade now',
      'membershipUpgradeHint': 'Upgrade to unlock more features',
      'membershipLoadProductsFailed': 'Failed to load membership plans, please retry',
      'cameraRoleMonitor': 'Monitor',
      'cameraRoleCamera': 'Camera',
      'cameraSettingsTitle': 'Device settings',
      'cameraSettingsName': 'Camera name',
      'cameraSettingsLocation': 'Camera location',
      'cameraSettingsToggleAudio': 'Audio',
      'cameraSettingsToggleMotion': 'Motion detection',
      'cameraSettingsSaving': 'Saving...',
      'cameraSettingsSaved': 'Saved',
      'cameraSettingsSaveFailed': 'Save failed',
      'cameraSettingsDeleteTitle': 'Delete device',
      'cameraSettingsDeleteContent':
          'Are you sure you want to delete this device? This action cannot be undone.',
      'cameraSettingsDeleteButton': 'Delete',
      'cameraSettingsDeleted': 'Device deleted',
      'cameraSettingsDeleteFailed': 'Delete failed',
      'cameraSettingsFieldEmpty': 'This field cannot be empty',
      'cameraSettingsEditTitlePrefix': 'Edit ',
      'cameraSettingsSaveButton': 'Save',
      'cameraEndpointTitle': 'Camera',
      'cameraEndpointGoToMonitor': 'Switch to monitor device',
      'cameraEndpointRecording': 'Recording...',
      'cameraEndpointRecord10s': 'Record 10s clip',
      'cameraEndpointRecordSaved': 'Clip saved',
      'cameraEndpointNotificationPermissionRequired':
          'Notification permission is required to keep camera running in background. Please grant it in settings.',
      'cameraEndpointServiceStarted': 'Foreground service started',
      'cameraEndpointBatteryOptimizationsOff': 'Battery optimizations disabled, running well',
      'cameraEndpointBatteryOptimizationsOn':
          'Consider disabling battery optimizations to keep connection stable',
      'cameraEndpointServiceStartFailed': 'Failed to start foreground service: ',
      'cameraEndpointEmailVerifyFailed': 'Connection rejected: email verification failed',
      'cameraEndpointLogMicOn': 'Monitor has turned on camera audio',
      'cameraEndpointLogMicOff': 'Monitor has muted camera audio',
      'cameraEndpointLogMonitorMessage': 'Monitor message: ',
      'cameraEndpointExitDialogTitle': 'Exit camera',
      'cameraEndpointExitDialogContent':
          'Are you sure you want to exit the camera? This will stop video capture and foreground service.',
      'cameraEndpointConnecting': 'Connecting to server...',
      'cameraEndpointConnectedWithId': 'Connected to server (ID: {id})',
      'playbackTitleSuffix': 'Playback',
      'playbackConnecting': 'Connecting to camera...',
      'playbackLoadList': 'Loading recordings...',
      'playbackConnectFailed': 'Unable to connect to camera',
      'playbackRetry': 'Retry',
      'playbackEmpty': 'No recordings on this day',
      'playbackPullToRefresh': 'Pull down to refresh',
      'playbackSaveToGallerySuccess': 'Saved to gallery',
      'playbackSaveToGalleryFailed': 'Save failed',
      'playbackVideoTitle': 'Playback',
      'playbackCreateTempFileFailed': 'Failed to create temporary file',
      'playbackDownloadingAndSaving': 'Downloading and saving...',
      'playbackFetchingVideo': 'Fetching video...',
      'playbackGetVideoFailed': 'Failed to get video',
      'playbackDeleteEventFailed': 'Delete failed',
      'playbackSmartDetectionLabel': 'Smart detection clip',
      'playbackVipRequiredTitle': 'VIP Required',
      'playbackVipRequiredContent': 'Cloud video playback is a VIP feature. Please upgrade to view recordings.',
      'playbackVipRequiredButton': 'Upgrade to VIP',
      'webviewLoadFailed': 'Page failed to load',
      'webviewRetry': 'Retry',
      'webviewRefresh': 'Refresh',
      'monitorViewerWaiting': 'Waiting for camera...',
      'emailFlowInputEmailTitle': 'Enter email',
      'emailFlowInputEmailHint': 'Your email address',
      'emailFlowInputEmailDesc':
          'We will check whether the email is registered. Unregistered email will go through quick sign-up.',
      'emailFlowEmailLabel': 'Email',
      'emailFlowEmailRequired': 'Please enter email',
      'emailFlowEmailInvalid': 'Invalid email format',
      'emailFlowCodeSent': 'Verification code has been sent to your email',
      'emailFlowPasswordLoginTitle': 'Enter password',
      'emailFlowEmailRegisteredTitle': 'Email already registered',
      'emailFlowSendCode': 'Send code',
      'emailFlowVerifyCodeTitle': 'Enter verification code',
      'emailFlowVerifyCodeHint': '6-digit code',
      'emailFlowCodeInvalid': 'Please enter a 6-digit code',
      'emailFlowNext': 'Next',
      'emailFlowSetPasswordTitle': 'Set password',
      'emailFlowPasswordHint': 'Password (at least 6 characters)',
      'emailFlowConfirmPasswordHint': 'Confirm password',
      'emailFlowFinish': 'Finish',
      'emailFlowLoginButton': 'Sign in',
      'emailFlowLoginSuccess': 'Signed in successfully',
      'emailFlowSendCodeDesc': 'Send verification code to this email',
      'emailFlowCreateAccountTitle': 'Create account',
      'emailFlowConfirmPasswordNotMatch': 'The two passwords do not match',
      'emailFlowRegisterSuccess': 'Registration successful',
      'commonCancel': 'Cancel',
      'commonConfirm': 'Confirm',
      'commonOk': 'OK',
      'commonNetworkError': 'Network error, please try again later',
      'commonRetry': 'Retry',
      'membershipPurchaseVerifying': 'Verifying purchase...',
      'membershipPleaseLogin': 'Please login first',
      'membershipPurchaseVerifyFailed': 'Purchase verification failed',
      'membershipPurchaseFailed': 'Purchase failed',
    },
    'zh': {
      'appTitle': 'RePhone 安全',
      'tabCameras': '相机列表',
      'tabMembership': '会员',
      'tabProfile': '个人中心',
      'settingsGeneral': '通用设置',
      'settingsLanguage': '语言',
      'settingsLanguageFollowSystem': '跟随系统',
      'settingsLanguageChinese': '中文',
      'settingsLanguageEnglish': '英文',
      'settingsAppPermissions': '应用权限',
      'settingsAppPermissionsSubtitle': '管理相机、麦克风等权限',
      'settingsResetPassword': '重置密码',
      'settingsResetPasswordSubtitle': '修改当前账户登录密码',
      'settingsDeleteAccount': '注销账号',
      'settingsDeleteAccountSubtitle': '永久删除账号及所有数据',
      'settingsLogout': '退出登录',
      'settingsLogoutSubtitle': '退出当前登录账户',
      'settingsLogoutDialogTitle': '退出登录',
      'settingsLogoutDialogContent': '确定要退出当前账户吗？',
      'settingsLogoutDialogCancel': '取消',
      'settingsLogoutDialogConfirm': '确定',
      'settingsLogoutSuccess': '已退出登录',
      'languagePageTitle': '语言',
      'languageOptionSystem': '跟随系统',
      'languageOptionChinese': '简体中文',
      'languageOptionEnglish': 'English',
      'languageOptionSystemDetail': '自动匹配中文或英文',
      'languageOptionChineseDetail': '始终使用中文',
      'languageOptionEnglishDetail': '始终使用英文',
      'authTitle': '登录 / 注册',
      'authChooseMethod': '选择登录方式',
      'authDesc': '登录后可同步设备、查看告警记录，随时掌握安全动态。',
      'authEmailLogin': '使用电子邮件登录',
      'authScanToBind': '扫码绑定设备',
      'authTermsPrefix': '继续操作即表示你同意',
      'authTermsLink': '服务条款',
      'authPrivacyLink': '隐私协议',
      'welcomeTitle': '欢迎使用 RePhone 安全',
      'welcomeDesc': '将闲置旧手机轻松变为家庭安防摄像头。',
      'welcomeButton': '立即开始',
      'welcomeFooter': '只需一次登录，即可开启跨设备守护体验',
      'aboutTitle': '关于我们',
      'aboutTerms': '服务条款',
      'aboutPrivacy': '隐私协议',
      'aboutView': '点击查看',
      'helpCenterTitle': '帮助中心',
      'helpFeedback': '意见反馈',
      'helpFeedbackHint': '请描述你遇到的问题、期望的功能或改进建议…',
      'helpContactOptional': '联系方式（可选）',
      'helpContactHint': '微信 / 手机号（可选）',
      'helpSubmit': '提交反馈',
      'helpSubmitting': '提交中...',
      'helpFeedbackEmpty': '请填写反馈内容',
      'helpFeedbackTooLong': '反馈内容过长（最多 5000 字符）',
      'helpFeedbackThanks': '感谢反馈，我们会尽快处理',
      'helpEmailFeedback': '邮件反馈',
      'helpEmailTip': '也可以直接发送邮件到该邮箱',
      'helpEmailCopied': '邮箱已复制',
      'helpCopyEmail': '复制邮箱',
      'cameraListTitle': '相机列表',
      'cameraListEmpty': '暂无相机',
      'cameraListEmptyHint': '通过扫码绑定设备后即可开始监控。',
      'cameraListBindButton': '绑定相机',
      'cameraListAsMonitor': '作为监控端使用',
      'cameraListAsCamera': '作为相机端使用',
      'cameraListUnnamed': '未命名设备',
      'cameraListUnknownLocation': '未知位置',
      'cameraListLoadFailed': '加载绑定列表失败',
      'cameraListStatusOnline': '在线',
      'cameraListStatusOffline': '离线',
      'cameraListTimeJustNow': '刚刚',
      'cameraListTimeMinutesAgo': '{minutes}分钟前',
      'cameraListTimeHoursAgo': '{hours}小时前',
      'cameraListTimeDaysAgo': '{days}天前',
      'cameraListPleaseLogin': '请先登录',
      'cameraListBindSuccess': '设备绑定成功！',
      'cameraDefaultLocationLivingRoom': '客厅',
      'cameraListActionPlayback': '回看',
      'cameraListActionSettings': '设置',
      'cameraRoleMonitor': '监控端',
      'cameraRoleCamera': '相机端',
      'qrScanTitle': '扫描二维码',
      'qrScanProcessing': '正在处理绑定...',
      'qrScanHint': '将二维码对准扫描框',
      'qrGenerateTitle': '设备二维码',
      'qrGenerateDesc': '请使用相机端扫描此二维码完成绑定。',
      'qrGenerateMonitorEmailLabel': '监控端邮箱：{email}',
      'qrGenerateWaitingForScan': '等待相机端扫描并绑定...',
      'qrScanInvalidFormat': '无效的二维码格式',
      'qrScanBindFailedPrefix': '绑定失败: ',
      'appPermissionsTitle': '应用权限',
      'appPermissionsCamera': '相机权限',
      'appPermissionsCameraSubtitle': '用于视频通话和监控画面采集',
      'appPermissionsMic': '麦克风权限',
      'appPermissionsMicSubtitle': '用于语音对讲和音频采集',
      'appPermissionsPhotos': '相册权限',
      'appPermissionsPhotosSubtitle': '用于保存截图和录像',
      'appPermissionsNote': '注意：权限开关需要跳转至系统设置中进行管理。',
      'resetPasswordTitle': '重置密码',
      'resetPasswordOld': '当前密码',
      'resetPasswordNew': '新密码',
      'resetPasswordConfirm': '确认新密码',
      'resetPasswordSubmit': '提交',
      'resetPasswordSuccess': '密码已更新',
      'resetPasswordLoadUserFailed': '获取用户信息失败，请重新登录',
      'resetPasswordFailed': '修改失败',
      'resetPasswordOldEmpty': '请输入旧密码',
      'resetPasswordNewEmpty': '请输入新密码',
      'resetPasswordTooShort': '密码长度至少为6位',
      'resetPasswordConfirmEmpty': '请再次输入新密码',
      'resetPasswordNotMatch': '两次输入的密码不一致',
      'deleteAccountTitle': '注销账号',
      'deleteAccountDesc': '此操作将永久删除账号及所有数据。',
      'deleteAccountButton': '立即注销账号',
      'deleteAccountConfirmTitle': '确认注销',
      'deleteAccountConfirmContent': '该操作无法撤销，确定要继续吗？',
      'deleteAccountConfirmOk': '注销',
      'deleteAccountConfirmCancel': '取消',
      'deleteAccountSuccess': '账号已注销',
      'deleteAccountWarning': '警告：注销账号是不可逆的操作。',
      'deleteAccountPasswordTip': '请输入您的密码以确认身份。',
      'deleteAccountPasswordEmpty': '请输入密码',
      'commonPassword': '密码',
      'profileTitle': '个人中心',
      'profileMembership': '会员',
      'profileHelpCenter': '帮助中心',
      'profileAbout': '关于我们',
      'profileGeneralSettings': '通用设置',
      'profileNotLoggedIn': '未登录',
      'profileSettingsTitle': '设置',
      'profileHelpCenterSubtitle': '常见问题、联系客服',
      'profileAboutSubtitle': '版本信息、用户协议',
      'profileGeneralSettingsSubtitle': '账号注销、退出登录',
      'profileOpenPagePrefix': '打开 ',
      'membershipTitle': '会员',
      'membershipPlanBasic': '基础版',
      'membershipPlanPro': '高级版',
      'membershipPlanCurrent': '当前套餐',
      'membershipPlanPricePerMonth': '{price}/月',
      'membershipFeatureNoDeviceLimit': '设备数量不设上限',
      'membershipFeatureBasicCloudImages': '1 天云存储（仅图片）',
      'membershipFeatureProCloudPlayback': '3 天云存储视频回看',
      'membershipFeatureLiveStreaming': '支持视频直播',
      'membershipFeatureNoAds': '无广告体验',
      'membershipFeatureMoreComing': '更多特权敬请期待',
      'membershipActionSubscribe': '立即开通',
      'membershipActionManage': '管理订阅',
      'membershipStatusPremium': '高级会员',
      'membershipStatusBasic': '基础用户',
      'membershipExpiryPrefix': '到期时间: ',
      'membershipSectionTitle': '会员特权与套餐',
      'membershipBadgeRecommended': '推荐',
      'membershipBadgeCurrent': '当前',
      'membershipPriceFree': '免费',
      'membershipDurationForever': '永久',
      'membershipDurationMonth': '月',
      'membershipDurationYear': '年',
      'membershipPlanMonthly': '月付',
      'membershipPlanYearly': '年付',
      'membershipFaqTitle': '常见问题',
      'membershipFaqCancelTitle': '如何取消订阅？',
      'membershipFaqCancelContent':
          '您可以随时在应用商店的订阅管理中取消订阅，取消后将在当前计费周期结束时生效。',
      'membershipFaqEffectTitle': '会员权益何时生效？',
      'membershipFaqEffectContent':
          '订阅成功后，会员权益将立即生效，您可以马上享受所有高级功能。',
      'membershipDialogUpgradeTitle': '升级会员',
      'membershipDialogUpgradeContent': '升级到高级会员，享受更多特权功能！',
      'membershipDialogLater': '稍后再说',
      'membershipDialogSubscribeTitle': '订阅套餐',
      'membershipDialogSubscribeContent': '确定要订阅该套餐吗？',
      'membershipDialogProcessing': '正在处理订阅...',
      'membershipButtonUpgrade': '立即升级',
      'membershipUpgradeHint': '升级会员解锁更多权益',
      'membershipLoadProductsFailed': '加载会员套餐失败，请重试',
      'cameraSettingsTitle': '设备设置',
      'cameraSettingsName': '相机名称',
      'cameraSettingsLocation': '相机位置',
      'cameraSettingsToggleAudio': '采集声音',
      'cameraSettingsToggleMotion': '移动侦测',
      'cameraSettingsSaving': '保存中...',
      'cameraSettingsSaved': '已保存',
      'cameraSettingsSaveFailed': '保存失败',
      'cameraSettingsDeleteTitle': '删除设备',
      'cameraSettingsDeleteContent': '确定要删除此设备吗？此操作无法撤销。',
      'cameraSettingsDeleteButton': '删除',
      'cameraSettingsDeleted': '设备已删除',
      'cameraSettingsDeleteFailed': '删除失败',
      'cameraSettingsFieldEmpty': '该字段不能为空',
      'cameraSettingsEditTitlePrefix': '修改',
      'cameraSettingsSaveButton': '保存',
      'cameraEndpointTitle': '相机端',
      'cameraEndpointGoToMonitor': '前往监控端',
      'cameraEndpointRecording': '录制中...',
      'cameraEndpointRecord10s': '录制 10 秒视频',
      'cameraEndpointRecordSaved': '视频片段已保存',
      'cameraEndpointNotificationPermissionRequired': '需要通知权限以保持相机在后台运行，请在设置中授予权限',
      'cameraEndpointServiceStarted': '前台服务已启动',
      'cameraEndpointBatteryOptimizationsOff': '电池优化已关闭，运行状态良好',
      'cameraEndpointBatteryOptimizationsOn': '建议在设置中关闭电池优化以保证连接稳定',
      'cameraEndpointServiceStartFailed': '启动前台服务失败: ',
      'cameraEndpointEmailVerifyFailed': '拒绝连接：邮箱验证失败',
      'cameraEndpointLogMicOn': '监控端已开启相机端声音',
      'cameraEndpointLogMicOff': '监控端已关闭相机端声音',
      'cameraEndpointLogMonitorMessage': '监控端消息: ',
      'cameraEndpointExitDialogTitle': '退出相机',
      'cameraEndpointExitDialogContent': '确定要退出相机端吗？\n退出后将停止视频采集和前台服务。',
      'cameraEndpointConnecting': '连接服务器中...',
      'cameraEndpointConnectedWithId': '已连接服务器 (ID: {id})',
      'playbackTitleSuffix': '回看',
      'playbackConnecting': '正在连接相机...',
      'playbackLoadList': '正在加载录像列表...',
      'playbackConnectFailed': '无法连接到相机',
      'playbackRetry': '重试',
      'playbackEmpty': '该日期暂无录像',
      'playbackPullToRefresh': '下拉可刷新列表',
      'playbackSaveToGallerySuccess': '已保存到相册',
      'playbackSaveToGalleryFailed': '保存失败',
      'playbackVideoTitle': '回看录像',
      'playbackCreateTempFileFailed': '无法创建临时文件',
      'playbackDownloadingAndSaving': '正在下载并保存...',
      'playbackFetchingVideo': '正在获取视频...',
      'playbackGetVideoFailed': '获取视频失败',
      'playbackDeleteEventFailed': '删除失败',
      'playbackSmartDetectionLabel': '智能检测录像',
      'playbackVipRequiredTitle': '需要VIP会员',
      'playbackVipRequiredContent': '云端录像回看是VIP功能，请升级会员后查看。',
      'playbackVipRequiredButton': '升级VIP',
      'webviewLoadFailed': '页面加载失败',
      'webviewRetry': '重试',
      'webviewRefresh': '刷新',
      'monitorViewerWaiting': '等待相机画面...',
      'emailFlowInputEmailTitle': '填写邮箱地址',
      'emailFlowInputEmailHint': '你的邮箱地址',
      'emailFlowInputEmailDesc': '我们将根据邮箱判断是否已注册，未注册将进入快捷注册流程。',
      'emailFlowEmailLabel': '邮箱',
      'emailFlowEmailRequired': '请输入邮箱',
      'emailFlowEmailInvalid': '邮箱格式不正确',
      'emailFlowCodeSent': '验证码已发送到邮箱，请查收',
      'emailFlowPasswordLoginTitle': '输入密码',
      'emailFlowEmailRegisteredTitle': '邮箱已注册',
      'emailFlowSendCode': '发送验证码',
      'emailFlowVerifyCodeTitle': '输入验证码',
      'emailFlowVerifyCodeHint': '6 位验证码',
      'emailFlowCodeInvalid': '请输入6位验证码',
      'emailFlowNext': '下一步',
      'emailFlowSetPasswordTitle': '设置密码',
      'emailFlowPasswordHint': '密码（至少 6 位）',
      'emailFlowConfirmPasswordHint': '确认密码',
      'emailFlowFinish': '完成',
      'emailFlowLoginButton': '登录',
      'emailFlowLoginSuccess': '登录成功',
      'emailFlowSendCodeDesc': '发送验证码到邮箱',
      'emailFlowCreateAccountTitle': '创建账号',
      'emailFlowConfirmPasswordNotMatch': '两次输入不一致',
      'emailFlowRegisterSuccess': '注册成功',
      'commonCancel': '取消',
      'commonConfirm': '确定',
      'commonOk': '好的',
      'commonNetworkError': '网络异常，请稍后再试',
      'commonRetry': '重试',
      'membershipPurchaseVerifying': '正在验证购买...',
      'membershipPleaseLogin': '请先登录',
      'membershipPurchaseVerifyFailed': '购买验证失败',
      'membershipPurchaseFailed': '购买失败',
    },
  };

  String _t(String key) {
    final langCode = _localizedValues.containsKey(locale.languageCode) ? locale.languageCode : 'en';
    final langMap = _localizedValues[langCode]!;
    return langMap[key] ?? _localizedValues['en']![key] ?? key;
  }

  String get appTitle => _t('appTitle');
  String get tabCameras => _t('tabCameras');
  String get tabMembership => _t('tabMembership');
  String get tabProfile => _t('tabProfile');

  String get settingsGeneral => _t('settingsGeneral');
  String get settingsLanguage => _t('settingsLanguage');
  String get settingsLanguageFollowSystem => _t('settingsLanguageFollowSystem');
  String get settingsLanguageChinese => _t('settingsLanguageChinese');
  String get settingsLanguageEnglish => _t('settingsLanguageEnglish');
  String get settingsAppPermissions => _t('settingsAppPermissions');
  String get settingsAppPermissionsSubtitle => _t('settingsAppPermissionsSubtitle');
  String get settingsResetPassword => _t('settingsResetPassword');
  String get settingsResetPasswordSubtitle => _t('settingsResetPasswordSubtitle');
  String get settingsDeleteAccount => _t('settingsDeleteAccount');
  String get settingsDeleteAccountSubtitle => _t('settingsDeleteAccountSubtitle');
  String get settingsLogout => _t('settingsLogout');
  String get settingsLogoutSubtitle => _t('settingsLogoutSubtitle');
  String get settingsLogoutDialogTitle => _t('settingsLogoutDialogTitle');
  String get settingsLogoutDialogContent => _t('settingsLogoutDialogContent');
  String get settingsLogoutDialogCancel => _t('settingsLogoutDialogCancel');
  String get settingsLogoutDialogConfirm => _t('settingsLogoutDialogConfirm');
  String get settingsLogoutSuccess => _t('settingsLogoutSuccess');

  String get languagePageTitle => _t('languagePageTitle');
  String get languageOptionSystem => _t('languageOptionSystem');
  String get languageOptionChinese => _t('languageOptionChinese');
  String get languageOptionEnglish => _t('languageOptionEnglish');
  String get languageOptionSystemDetail => _t('languageOptionSystemDetail');
  String get languageOptionChineseDetail => _t('languageOptionChineseDetail');
  String get languageOptionEnglishDetail => _t('languageOptionEnglishDetail');

  String get authTitle => _t('authTitle');
  String get authChooseMethod => _t('authChooseMethod');
  String get authDesc => _t('authDesc');
  String get authEmailLogin => _t('authEmailLogin');
  String get authScanToBind => _t('authScanToBind');
  String get authTermsPrefix => _t('authTermsPrefix');
  String get authTermsLink => _t('authTermsLink');
  String get authPrivacyLink => _t('authPrivacyLink');

  String get welcomeTitle => _t('welcomeTitle');
  String get welcomeDesc => _t('welcomeDesc');

  String get aboutTitle => _t('aboutTitle');
  String get aboutTerms => _t('aboutTerms');
  String get aboutPrivacy => _t('aboutPrivacy');
  String get aboutView => _t('aboutView');

  String get helpCenterTitle => _t('helpCenterTitle');
  String get helpFeedback => _t('helpFeedback');
  String get helpFeedbackHint => _t('helpFeedbackHint');
  String get helpContactOptional => _t('helpContactOptional');
  String get helpContactHint => _t('helpContactHint');
  String get helpSubmit => _t('helpSubmit');
  String get helpSubmitting => _t('helpSubmitting');
  String get helpFeedbackEmpty => _t('helpFeedbackEmpty');
  String get helpFeedbackTooLong => _t('helpFeedbackTooLong');
  String get helpFeedbackThanks => _t('helpFeedbackThanks');
  String get helpEmailFeedback => _t('helpEmailFeedback');
  String get helpEmailTip => _t('helpEmailTip');
  String get helpEmailCopied => _t('helpEmailCopied');
  String get helpCopyEmail => _t('helpCopyEmail');

  String get cameraListTitle => _t('cameraListTitle');
  String get cameraListEmpty => _t('cameraListEmpty');
  String get cameraListEmptyHint => _t('cameraListEmptyHint');
  String get cameraListBindButton => _t('cameraListBindButton');
  String get cameraListAsMonitor => _t('cameraListAsMonitor');
  String get cameraListAsCamera => _t('cameraListAsCamera');
  String get cameraListBindSuccess => _t('cameraListBindSuccess');
  String get cameraDefaultLocationLivingRoom =>
      _t('cameraDefaultLocationLivingRoom');
  String get cameraRoleMonitor => _t('cameraRoleMonitor');
  String get cameraRoleCamera => _t('cameraRoleCamera');
  String get qrScanTitle => _t('qrScanTitle');
  String get qrScanProcessing => _t('qrScanProcessing');
  String get qrScanHint => _t('qrScanHint');
  String get qrGenerateTitle => _t('qrGenerateTitle');
  String get qrGenerateDesc => _t('qrGenerateDesc');
  String get qrGenerateMonitorEmailLabel => _t('qrGenerateMonitorEmailLabel');
  String get qrGenerateWaitingForScan => _t('qrGenerateWaitingForScan');
  String get qrScanInvalidFormat => _t('qrScanInvalidFormat');
  String get qrScanBindFailedPrefix => _t('qrScanBindFailedPrefix');

  String get appPermissionsTitle => _t('appPermissionsTitle');
  String get appPermissionsCamera => _t('appPermissionsCamera');
  String get appPermissionsCameraSubtitle => _t('appPermissionsCameraSubtitle');
  String get appPermissionsMic => _t('appPermissionsMic');
  String get appPermissionsMicSubtitle => _t('appPermissionsMicSubtitle');
  String get appPermissionsPhotos => _t('appPermissionsPhotos');
  String get appPermissionsPhotosSubtitle => _t('appPermissionsPhotosSubtitle');
  String get appPermissionsNote => _t('appPermissionsNote');

  String get resetPasswordTitle => _t('resetPasswordTitle');
  String get resetPasswordOld => _t('resetPasswordOld');
  String get resetPasswordNew => _t('resetPasswordNew');
  String get resetPasswordConfirm => _t('resetPasswordConfirm');
  String get resetPasswordSubmit => _t('resetPasswordSubmit');
  String get resetPasswordSuccess => _t('resetPasswordSuccess');
  String get resetPasswordTooShort => _t('resetPasswordTooShort');

  String get deleteAccountTitle => _t('deleteAccountTitle');
  String get deleteAccountButton => _t('deleteAccountButton');
  String get deleteAccountConfirmTitle => _t('deleteAccountConfirmTitle');
  String get deleteAccountConfirmContent => _t('deleteAccountConfirmContent');
  String get deleteAccountConfirmOk => _t('deleteAccountConfirmOk');
  String get deleteAccountConfirmCancel => _t('deleteAccountConfirmCancel');
  String get deleteAccountSuccess => _t('deleteAccountSuccess');

  String get webviewLoadFailed => _t('webviewLoadFailed');
  String get webviewRetry => _t('webviewRetry');
  String get webviewRefresh => _t('webviewRefresh');

  String get profileTitle => _t('profileTitle');
  String get profileMembership => _t('profileMembership');
  String get profileHelpCenter => _t('profileHelpCenter');
  String get profileAbout => _t('profileAbout');
  String get profileGeneralSettings => _t('profileGeneralSettings');
  String get profileNotLoggedIn => _t('profileNotLoggedIn');
  String get profileSettingsTitle => _t('profileSettingsTitle');
  String get profileHelpCenterSubtitle => _t('profileHelpCenterSubtitle');
  String get profileAboutSubtitle => _t('profileAboutSubtitle');
  String get profileGeneralSettingsSubtitle => _t('profileGeneralSettingsSubtitle');
  String get profileOpenPagePrefix => _t('profileOpenPagePrefix');

  String get membershipTitle => _t('membershipTitle');
  String get membershipPlanBasic => _t('membershipPlanBasic');
  String get membershipPlanPro => _t('membershipPlanPro');
  String get membershipPlanCurrent => _t('membershipPlanCurrent');
  String get membershipPlanPricePerMonth => _t('membershipPlanPricePerMonth');
  String get membershipFeatureNoDeviceLimit => _t('membershipFeatureNoDeviceLimit');
  String get membershipFeatureBasicCloudImages => _t('membershipFeatureBasicCloudImages');
  String get membershipFeatureProCloudPlayback => _t('membershipFeatureProCloudPlayback');
  String get membershipFeatureLiveStreaming => _t('membershipFeatureLiveStreaming');
  String get membershipFeatureNoAds => _t('membershipFeatureNoAds');
  String get membershipFeatureMoreComing => _t('membershipFeatureMoreComing');
  String get membershipActionSubscribe => _t('membershipActionSubscribe');
  String get membershipActionManage => _t('membershipActionManage');
  String get membershipStatusPremium => _t('membershipStatusPremium');
  String get membershipStatusBasic => _t('membershipStatusBasic');
  String get membershipExpiryPrefix => _t('membershipExpiryPrefix');
  String get membershipSectionTitle => _t('membershipSectionTitle');
  String get membershipBadgeRecommended => _t('membershipBadgeRecommended');
  String get membershipBadgeCurrent => _t('membershipBadgeCurrent');
  String get membershipPriceFree => _t('membershipPriceFree');
  String get membershipDurationForever => _t('membershipDurationForever');
  String get membershipDurationMonth => _t('membershipDurationMonth');
  String get membershipDurationYear => _t('membershipDurationYear');
  String get membershipPlanMonthly => _t('membershipPlanMonthly');
  String get membershipPlanYearly => _t('membershipPlanYearly');
  String get membershipFaqTitle => _t('membershipFaqTitle');
  String get membershipFaqCancelTitle => _t('membershipFaqCancelTitle');
  String get membershipFaqCancelContent => _t('membershipFaqCancelContent');
  String get membershipFaqEffectTitle => _t('membershipFaqEffectTitle');
  String get membershipFaqEffectContent => _t('membershipFaqEffectContent');
  String get membershipDialogUpgradeTitle => _t('membershipDialogUpgradeTitle');
  String get membershipDialogUpgradeContent => _t('membershipDialogUpgradeContent');
  String get membershipDialogLater => _t('membershipDialogLater');
  String get membershipDialogSubscribeTitle => _t('membershipDialogSubscribeTitle');
  String get membershipDialogSubscribeContent => _t('membershipDialogSubscribeContent');
  String get membershipDialogProcessing => _t('membershipDialogProcessing');
  String get membershipButtonUpgrade => _t('membershipButtonUpgrade');
  String get membershipUpgradeHint => _t('membershipUpgradeHint');
  String get membershipLoadProductsFailed => _t('membershipLoadProductsFailed');

  String get cameraSettingsTitle => _t('cameraSettingsTitle');
  String get cameraSettingsName => _t('cameraSettingsName');
  String get cameraSettingsLocation => _t('cameraSettingsLocation');
  String get cameraSettingsToggleAudio => _t('cameraSettingsToggleAudio');
  String get cameraSettingsToggleMotion => _t('cameraSettingsToggleMotion');
  String get cameraSettingsSaving => _t('cameraSettingsSaving');
  String get cameraSettingsSaved => _t('cameraSettingsSaved');
  String get cameraSettingsSaveFailed => _t('cameraSettingsSaveFailed');
  String get cameraSettingsDeleteTitle => _t('cameraSettingsDeleteTitle');
  String get cameraSettingsDeleteContent => _t('cameraSettingsDeleteContent');
  String get cameraSettingsDeleteButton => _t('cameraSettingsDeleteButton');
  String get cameraSettingsDeleted => _t('cameraSettingsDeleted');
  String get cameraSettingsDeleteFailed => _t('cameraSettingsDeleteFailed');
  String get cameraSettingsFieldEmpty => _t('cameraSettingsFieldEmpty');
  String get cameraSettingsEditTitlePrefix => _t('cameraSettingsEditTitlePrefix');
  String get cameraSettingsSaveButton => _t('cameraSettingsSaveButton');

  String get playbackTitleSuffix => _t('playbackTitleSuffix');
  String get playbackConnecting => _t('playbackConnecting');
  String get playbackLoadList => _t('playbackLoadList');
  String get playbackConnectFailed => _t('playbackConnectFailed');
  String get playbackRetry => _t('playbackRetry');
  String get playbackEmpty => _t('playbackEmpty');
  String get playbackPullToRefresh => _t('playbackPullToRefresh');
  String get playbackSaveToGallerySuccess => _t('playbackSaveToGallerySuccess');
  String get playbackSaveToGalleryFailed => _t('playbackSaveToGalleryFailed');
  String get playbackVideoTitle => _t('playbackVideoTitle');
  String get playbackCreateTempFileFailed => _t('playbackCreateTempFileFailed');
  String get playbackDownloadingAndSaving => _t('playbackDownloadingAndSaving');
  String get playbackFetchingVideo => _t('playbackFetchingVideo');
  String get playbackGetVideoFailed => _t('playbackGetVideoFailed');
  String get playbackDeleteEventFailed => _t('playbackDeleteEventFailed');
  String get playbackSmartDetectionLabel => _t('playbackSmartDetectionLabel');
  String get playbackVipRequiredTitle => _t('playbackVipRequiredTitle');
  String get playbackVipRequiredContent => _t('playbackVipRequiredContent');
  String get playbackVipRequiredButton => _t('playbackVipRequiredButton');

  String get cameraEndpointTitle => _t('cameraEndpointTitle');
  String get cameraEndpointGoToMonitor => _t('cameraEndpointGoToMonitor');
  String get cameraEndpointRecording => _t('cameraEndpointRecording');
  String get cameraEndpointRecord10s => _t('cameraEndpointRecord10s');
  String get cameraEndpointRecordSaved => _t('cameraEndpointRecordSaved');
  String get cameraEndpointNotificationPermissionRequired =>
      _t('cameraEndpointNotificationPermissionRequired');
  String get cameraEndpointServiceStarted => _t('cameraEndpointServiceStarted');
  String get cameraEndpointBatteryOptimizationsOff =>
      _t('cameraEndpointBatteryOptimizationsOff');
  String get cameraEndpointBatteryOptimizationsOn =>
      _t('cameraEndpointBatteryOptimizationsOn');
  String get cameraEndpointServiceStartFailed => _t('cameraEndpointServiceStartFailed');
  String get cameraEndpointEmailVerifyFailed => _t('cameraEndpointEmailVerifyFailed');
  String get cameraEndpointLogMicOn => _t('cameraEndpointLogMicOn');
  String get cameraEndpointLogMicOff => _t('cameraEndpointLogMicOff');
  String get cameraEndpointLogMonitorMessage => _t('cameraEndpointLogMonitorMessage');
  String get cameraEndpointExitDialogTitle => _t('cameraEndpointExitDialogTitle');
  String get cameraEndpointExitDialogContent => _t('cameraEndpointExitDialogContent');
  String get cameraEndpointConnecting => _t('cameraEndpointConnecting');
  String get cameraEndpointConnectedWithId => _t('cameraEndpointConnectedWithId');

  String get monitorViewerWaiting => _t('monitorViewerWaiting');

  String get emailFlowInputEmailTitle => _t('emailFlowInputEmailTitle');
  String get emailFlowInputEmailHint => _t('emailFlowInputEmailHint');
  String get emailFlowInputEmailDesc => _t('emailFlowInputEmailDesc');
  String get emailFlowEmailLabel => _t('emailFlowEmailLabel');
  String get emailFlowEmailRequired => _t('emailFlowEmailRequired');
  String get emailFlowEmailInvalid => _t('emailFlowEmailInvalid');
  String get emailFlowCodeSent => _t('emailFlowCodeSent');
  String get emailFlowPasswordLoginTitle => _t('emailFlowPasswordLoginTitle');
  String get emailFlowEmailRegisteredTitle => _t('emailFlowEmailRegisteredTitle');
  String get emailFlowSendCode => _t('emailFlowSendCode');
  String get emailFlowVerifyCodeTitle => _t('emailFlowVerifyCodeTitle');
  String get emailFlowVerifyCodeHint => _t('emailFlowVerifyCodeHint');
  String get emailFlowCodeInvalid => _t('emailFlowCodeInvalid');
  String get emailFlowNext => _t('emailFlowNext');
  String get emailFlowSetPasswordTitle => _t('emailFlowSetPasswordTitle');
  String get emailFlowPasswordHint => _t('emailFlowPasswordHint');
  String get emailFlowConfirmPasswordHint => _t('emailFlowConfirmPasswordHint');
  String get emailFlowFinish => _t('emailFlowFinish');
  String get emailFlowLoginButton => _t('emailFlowLoginButton');
  String get emailFlowLoginSuccess => _t('emailFlowLoginSuccess');
  String get emailFlowSendCodeDesc => _t('emailFlowSendCodeDesc');
  String get emailFlowCreateAccountTitle => _t('emailFlowCreateAccountTitle');
  String get emailFlowConfirmPasswordNotMatch => _t('emailFlowConfirmPasswordNotMatch');
  String get emailFlowRegisterSuccess => _t('emailFlowRegisterSuccess');

  String get commonCancel => _t('commonCancel');
  String get commonConfirm => _t('commonConfirm');
  String get commonOk => _t('commonOk');
  String get commonNetworkError => _t('commonNetworkError');
  String get commonRetry => _t('commonRetry');

  String get membershipPurchaseVerifying => _t('membershipPurchaseVerifying');
  String get membershipPleaseLogin => _t('membershipPleaseLogin');
  String get membershipPurchaseVerifyFailed => _t('membershipPurchaseVerifyFailed');
  String get membershipPurchaseFailed => _t('membershipPurchaseFailed');

  String get commonPassword => _t('commonPassword');

  String tr(String key) => _t(key);
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'zh'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) {
    return false;
  }
}

class LocaleManager {
  static const String _prefsKey = 'app_language';
  static final ValueNotifier<Locale?> localeNotifier = ValueNotifier<Locale?>(null);

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_prefsKey);
      if (code == null || code == 'system') {
        localeNotifier.value = null;
        return;
      }
      if (code == 'zh') {
        localeNotifier.value = const Locale('zh');
        return;
      }
      if (code == 'en') {
        localeNotifier.value = const Locale('en');
        return;
      }
      localeNotifier.value = const Locale('en');
    } catch (_) {
      localeNotifier.value = null;
    }
  }

  static Future<void> setSystem() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
    localeNotifier.value = null;
  }

  static Future<void> setChinese() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, 'zh');
    } catch (_) {}
    localeNotifier.value = const Locale('zh');
  }

  static Future<void> setEnglish() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, 'en');
    } catch (_) {}
    localeNotifier.value = const Locale('en');
  }

  static Locale resolveLocale(Locale? deviceLocale, Iterable<Locale> supportedLocales) {
    if (deviceLocale != null) {
      for (final supported in supportedLocales) {
        if (supported.languageCode == deviceLocale.languageCode) {
          return supported;
        }
      }
    }
    return const Locale('en');
  }
}
