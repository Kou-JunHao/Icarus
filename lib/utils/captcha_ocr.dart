/// 验证码 OCR 识别
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

/// 验证码 OCR 识别器
class CaptchaOcr {
  static final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  /// 识别验证码图片
  ///
  /// [imageBytes] 验证码图片数据
  /// 返回识别的验证码文本（4位字母数字）
  static Future<String?> recognize(Uint8List imageBytes) async {
    File? tempFile;
    try {
      // 将图片数据保存为临时文件
      final tempDir = await getTemporaryDirectory();
      tempFile = File(
        '${tempDir.path}/captcha_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await tempFile.writeAsBytes(imageBytes);

      // 使用 ML Kit 识别文本
      final inputImage = InputImage.fromFile(tempFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      // 提取并清理验证码
      String captcha = _extractCaptcha(recognizedText.text);

      print('OCR 原始识别结果: ${recognizedText.text}');
      print('OCR 处理后验证码: $captcha');

      return captcha.isNotEmpty ? captcha : null;
    } catch (e) {
      print('验证码识别失败: $e');
      return null;
    } finally {
      // 删除临时文件
      if (tempFile != null && await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  /// 从识别结果中提取验证码
  static String _extractCaptcha(String text) {
    // 移除空格和特殊字符，只保留字母和数字
    String cleaned = text.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');

    // 验证码通常是4位
    if (cleaned.length >= 4) {
      cleaned = cleaned.substring(0, 4);
    }

    // 转为小写（根据教务系统需求调整）
    return cleaned.toLowerCase();
  }

  /// 释放资源
  static Future<void> dispose() async {
    await _textRecognizer.close();
  }
}
