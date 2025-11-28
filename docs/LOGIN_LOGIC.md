# 强智教务系统登录逻辑分析

## 概述

强智教务系统是国内高校广泛使用的教务管理系统，本文档详细记录其登录流程和加密算法。

---

## 登录流程

```
┌─────────────────────────────────────────────────────────────┐
│                      登录流程图                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. GET /                    ──→  获取 JSESSIONID Cookie    │
│                                                             │
│  2. POST /Logon.do?method=logon&flag=sess                   │
│                              ──→  获取加密参数 scode#sxh    │
│                                                             │
│  3. 本地执行加密算法                                         │
│     encode(用户名, 密码, scode, sxh) ──→ encoded           │
│                                                             │
│  4. GET /verifycode.servlet  ──→  获取验证码图片            │
│                                                             │
│  5. POST /Logon.do?method=logon                             │
│     ├─ userAccount: 用户名                                  │
│     ├─ userPassword: ""  (清空)                             │
│     ├─ encoded: 加密后的字符串                              │
│     └─ RANDOMCODE: 验证码                                   │
│                              ──→  302 重定向到主页          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 核心加密算法

### 原始 JavaScript 代码

```javascript
function loginajax() {
    var strUrl = "/Logon.do?method=logon&flag=sess";
    $.ajax({
        url: strUrl,
        type: "post",
        cache: false,
        dataType: "text",
        success: function(dataStr) {
            if (dataStr == "no") {
                return false;
            } else {
                var scode = dataStr.split("#")[0];
                var sxh = dataStr.split("#")[1];
                var code = document.getElementById("userAccount").value + "%%%" + 
                          document.getElementById("userPassword").value;
                var encoded = "";
                
                for (var i = 0; i < code.length; i++) {
                    if (i < 20) {
                        encoded = encoded + code.substring(i, i + 1) + 
                                 scode.substring(0, parseInt(sxh.substring(i, i + 1)));
                        scode = scode.substring(parseInt(sxh.substring(i, i + 1)), scode.length);
                    } else {
                        encoded = encoded + code.substring(i, code.length);
                        i = code.length;
                    }
                }
                
                document.getElementById("encoded").value = encoded;
                document.getElementById("userPassword").value = "";
                document.getElementById("loginForm").submit();
            }
        }
    });
}
```

### Python 实现

```python
def encode_password(username: str, password: str, scode: str, sxh: str) -> str:
    """
    强智教务系统密码加密算法
    
    算法原理：
    1. 将 "用户名%%%密码" 作为原始字符串 code
    2. 对于 code 的前20个字符，每个字符后面插入 scode 的一部分
    3. 插入长度由 sxh 的对应位置数字决定
    4. 超过20个字符后，直接追加剩余内容
    
    Args:
        username: 用户名/学号
        password: 密码
        scode: 服务器返回的加密种子（随机字符串）
        sxh: 服务器返回的位置索引（数字字符串，如 "31202130..."）
        
    Returns:
        加密后的字符串
    
    Example:
        >>> encode_password("2021001", "123456", "abcdefghij", "3120213021")
        # code = "2021001%%%123456"
        # i=0: '2' + scode[0:3]='abc' → encoded='2abc', scode='defghij'
        # i=1: '0' + scode[0:1]='d'   → encoded='2abc0d', scode='efghij'
        # i=2: '2' + scode[0:2]='ef'  → encoded='2abc0d2ef', scode='ghij'
        # ...继续直到 i>=20 或 code 结束
    """
    code = f"{username}%%%{password}"
    encoded = ""
    
    for i in range(len(code)):
        if i < 20:
            # 取当前字符
            encoded += code[i]
            
            # 获取要插入的 scode 长度（sxh[i] 是一个数字字符）
            insert_len = int(sxh[i])
            
            # 追加 scode 的前 insert_len 个字符
            encoded += scode[:insert_len]
            
            # 从 scode 中移除已使用的字符
            scode = scode[insert_len:]
        else:
            # 超过20个字符后，直接追加剩余内容并结束
            encoded += code[i:]
            break
    
    return encoded
```

### 加密示例

```
输入:
  username = "1145141919810"
  password = "mypassword"
  scode    = "X8E6q3nU4i79ZC262QY52atdu1rd9X4Rehk89"
  sxh      = "32231121223122121321"

过程:
  code = "1145141919810%%%mypassword" (长度26)
  
  i=0:  '1' + 'X8E' (3个字符)     → "1X8E",               scode剩余='6q3nU4i79ZC262QY52atdu1rd9X4Rehk89'
  i=1:  '1' + '6q' (2个字符)      → "1X8E16q",            scode剩余='3nU4i79ZC262QY52atdu1rd9X4Rehk89'
  i=2:  '4' + '3n' (2个字符)      → "1X8E16q43n",         scode剩余='U4i79ZC262QY52atdu1rd9X4Rehk89'
  i=3:  '5' + 'U' (1个字符)       → "1X8E16q43n5U",       scode剩余='4i79ZC262QY52atdu1rd9X4Rehk89'
  i=4:  '1' + '4' (1个字符)       → "1X8E16q43n5U14",     scode剩余='i79ZC262QY52atdu1rd9X4Rehk89'
  i=5:  '4' + 'i7' (2个字符)      → "1X8E16q43n5U144i7",  scode剩余='9ZC262QY52atdu1rd9X4Rehk89'
  i=6:  '1' + '9' (1个字符)       → "1X8E16q43n5U144i719"
  i=7:  '9' + 'ZC' (2个字符)      → "1X8E16q43n5U144i7199ZC"
  i=8:  '1' + '26' (2个字符)      → "1X8E16q43n5U144i7199ZC126"
  i=9:  '9' + '2QY' (3个字符)     → "1X8E16q43n5U144i7199ZC12692QY"
  i=10: '8' + '5' (1个字符)       → "1X8E16q43n5U144i7199ZC12692QY85"
  i=11: '1' + '2a' (2个字符)      → "1X8E16q43n5U144i7199ZC12692QY8512a"
  i=12: '0' + 'td' (2个字符)      → "1X8E16q43n5U144i7199ZC12692QY8512a0td"
  i=13: '%' + 'u' (1个字符)       → "1X8E16q43n5U144i7199ZC12692QY8512a0td%u"
  i=14: '%' + '1r' (2个字符)      → "1X8E16q43n5U144i7199ZC12692QY8512a0td%u%1r"
  i=15: '%' + 'd' (1个字符)       → "1X8E16q43n5U144i7199ZC12692QY8512a0td%u%1r%d"
  i=16: 'm' + '9X4' (3个字符)     → "...%dm9X4"
  i=17: 'y' + 'Re' (2个字符)      → "...yRe"
  i=18: 'p' + 'h' (1个字符)       → "...ph"
  i=19: 'a' + 'k89' (3个字符)     → "...ak89"
  i>=20: 追加剩余字符 'ssword'

输出:
  encoded = "1X8E16q43n5U144i7199ZC12692QY8512a0td%u%1r%dm9X4yRephak89ssword"
```

---

## API 接口说明

### 1. 获取加密参数

```
POST /Logon.do?method=logon&flag=sess

响应格式: "scode#sxh"
示例: "X8E6q3nU4i79ZC262QY52atdu1rd9X4Rehk89#32231121223122121321"

说明:
- scode: 随机加密种子，长度约 35-45 字符
- sxh: 位置索引，固定20个数字字符（1-3）
```

### 2. 获取验证码

```
GET /verifycode.servlet

响应: PNG 图片数据
说明: 4位字母数字验证码
```

### 3. 提交登录

```
POST /Logon.do?method=logon
Content-Type: application/x-www-form-urlencoded

参数:
- userAccount: 用户名（明文）
- userPassword: 空字符串
- encoded: 加密后的字符串
- RANDOMCODE: 验证码

成功响应: 302 重定向到 /jsxsd/framework/xsMainV.htmlx
失败响应: 200，页面包含错误信息
```

---

## 错误信息提取

错误信息位于 HTML 中的 `<font id="showMsg" color="red">` 元素：

```python
import re

def extract_error(html: str) -> str:
    """提取登录错误信息"""
    patterns = [
        r'id=["\']showMsg["\'][^>]*>([^<]+)<',
        r'<font[^>]*color=["\']?red["\']?[^>]*>([^<]+)</font>',
    ]
    
    for pattern in patterns:
        match = re.search(pattern, html, re.IGNORECASE)
        if match:
            return match.group(1).strip()
    
    return "未知错误"
```

常见错误信息：
- `该帐号不存在或密码错误,请联系管理员!`
- `验证码错误!!`
- `请安装加密狗插件，插入加密狗！`（实际是验证码为空）

---

## 完整登录代码

```python
import requests
import re
from urllib.parse import urljoin
from PIL import Image
import ddddocr

# 修复 Pillow 10+ 兼容性
if not hasattr(Image, 'ANTIALIAS'):
    Image.ANTIALIAS = Image.Resampling.LANCZOS


class QZLogin:
    """强智教务系统登录类"""
    
    def __init__(self, base_url: str):
        self.base_url = base_url.rstrip('/')
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0',
        })
        self.ocr = ddddocr.DdddOcr()
    
    def _url(self, path: str) -> str:
        return urljoin(self.base_url, path)
    
    def _encode(self, username: str, password: str, scode: str, sxh: str) -> str:
        """加密算法"""
        code = f"{username}%%%{password}"
        encoded = ""
        for i in range(len(code)):
            if i < 20:
                encoded += code[i]
                n = int(sxh[i])
                encoded += scode[:n]
                scode = scode[n:]
            else:
                encoded += code[i:]
                break
        return encoded
    
    def login(self, username: str, password: str, max_retry: int = 10) -> bool:
        """
        执行登录
        
        Args:
            username: 学号
            password: 密码
            max_retry: 最大重试次数（验证码识别可能失败）
            
        Returns:
            登录是否成功
        """
        for attempt in range(max_retry):
            try:
                # 1. 获取Cookie
                self.session.get(self.base_url)
                
                # 2. 获取加密参数
                resp = self.session.post(self._url('/Logon.do?method=logon&flag=sess'))
                if '#' not in resp.text:
                    continue
                scode, sxh = resp.text.strip().split('#', 1)
                
                # 3. 加密密码
                encoded = self._encode(username, password, scode, sxh)
                
                # 4. 获取验证码
                resp = self.session.get(self._url('/verifycode.servlet'))
                captcha = self.ocr.classification(resp.content)
                
                # 5. 提交登录
                resp = self.session.post(
                    self._url('/Logon.do?method=logon'),
                    data={
                        'userAccount': username,
                        'userPassword': '',
                        'encoded': encoded,
                        'RANDOMCODE': captcha,
                    },
                    allow_redirects=True
                )
                
                # 6. 检查结果
                if 'main' in resp.url.lower():
                    print(f"[+] 登录成功 (第{attempt+1}次)")
                    return True
                
                # 提取错误
                match = re.search(r'id=["\']showMsg["\'][^>]*>([^<]+)<', resp.text)
                if match:
                    error = match.group(1).strip()
                    if '验证码' in error:
                        continue  # 验证码错误，重试
                    print(f"[-] {error}")
                    return False
                    
            except Exception as e:
                print(f"[-] 异常: {e}")
                continue
        
        print(f"[-] 达到最大重试次数")
        return False


# 使用示例
if __name__ == '__main__':
    client = QZLogin("https://jwyth.hnkjxy.net.cn")
    
    if client.login("学号", "密码"):
        # 登录成功，使用 client.session 进行后续操作
        session = client.session
        # resp = session.get("https://xxx/jsxsd/grxx/xsxx")
```

---

## 依赖安装

```bash
pip install requests ddddocr pillow
```

---

## 注意事项

1. **验证码识别率**: ddddocr 识别率约 70-90%，配合重试机制可达 99%
2. **Session 保持**: 登录成功后需保持同一 Session 进行后续请求
3. **Cookie 有效期**: JSESSIONID 有时效性，长时间不操作需重新登录
4. **并发限制**: 避免频繁请求，可能触发验证码更换或封禁

---

## 文件结构

```
jwxtlogin/
├── login.py         # 基础登录脚本（手动输入验证码）
├── auto_login.py    # 无感自动登录（OCR识别验证码）
├── test_login.py    # 调试测试脚本
├── debug.py         # 登录流程分析工具
└── requirements.txt # 依赖列表
```
