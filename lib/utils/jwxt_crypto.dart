/// 强智教务系统加密工具类
///
/// 实现教务系统的密码加密算法
library;

class JwxtCrypto {
  /// 加密算法
  ///
  /// 将用户名和密码按照强智教务系统的加密规则进行编码
  ///
  /// [username] 用户名/学号
  /// [password] 密码
  /// [scode] 服务器返回的加密种子（随机字符串）
  /// [sxh] 服务器返回的位置索引（数字字符串，20个字符）
  ///
  /// 算法原理：
  /// 1. 将 "用户名%%%密码" 作为原始字符串 code
  /// 2. 对于 code 的前20个字符，每个字符后面插入 scode 的一部分
  /// 3. 插入长度由 sxh 的对应位置数字决定
  /// 4. 超过20个字符后，直接追加剩余内容
  static String encode({
    required String username,
    required String password,
    required String scode,
    required String sxh,
  }) {
    final code = '$username%%%$password';
    final buffer = StringBuffer();
    var remainingScode = scode;

    for (var i = 0; i < code.length; i++) {
      if (i < 20) {
        // 取当前字符
        buffer.write(code[i]);

        // 获取要插入的 scode 长度（sxh[i] 是一个数字字符）
        final insertLen = int.parse(sxh[i]);

        // 追加 scode 的前 insertLen 个字符
        if (remainingScode.length >= insertLen) {
          buffer.write(remainingScode.substring(0, insertLen));
          // 从 scode 中移除已使用的字符
          remainingScode = remainingScode.substring(insertLen);
        }
      } else {
        // 超过20个字符后，直接追加剩余内容并结束
        buffer.write(code.substring(i));
        break;
      }
    }

    return buffer.toString();
  }

  /// 解析服务器返回的加密参数
  ///
  /// [response] 服务器返回的 "scode#sxh" 格式字符串
  /// 返回 (scode, sxh) 元组，如果格式错误返回 null
  static ({String scode, String sxh})? parseEncryptParams(String response) {
    final parts = response.trim().split('#');
    if (parts.length != 2) {
      return null;
    }
    return (scode: parts[0], sxh: parts[1]);
  }
}
