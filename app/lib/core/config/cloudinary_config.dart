class CloudinaryConfig {
  static const String cloudName = 'b2werciv';

  static const String uploadPreset = 'cofiz-app';

  static const String folder = 'receipts';

  static String get uploadEndpoint =>
      'https://api.cloudinary.com/v1_1/$cloudName/image/upload';
}