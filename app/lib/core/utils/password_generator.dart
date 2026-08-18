import 'dart:math';

class PasswordGenerator {
  static const String _uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _lowercase = 'abcdefghijklmnopqrstuvwxyz';
  static const String _numbers = '0123456789';

  /// Generate a random password
  /// Default length: 8 characters
  /// Format: Mix of uppercase, lowercase, and numbers
  static String generate({int length = 8}) {
    final random = Random.secure();
    const allChars = _uppercase + _lowercase + _numbers;

    String password = '';

    password += _uppercase[random.nextInt(_uppercase.length)];
    password += _lowercase[random.nextInt(_lowercase.length)];
    password += _numbers[random.nextInt(_numbers.length)];

    for (int i = 3; i < length; i++) {
      password += allChars[random.nextInt(allChars.length)];
    }

    // Shuffle the password
    List<String> passwordChars = password.split('');
    passwordChars.shuffle(random);

    return passwordChars.join();
  }
}
