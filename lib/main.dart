import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Auto Quiz',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _apiUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  String _status = '等待截屏...';
  bool _isProcessing = false;
  
  // 悬浮窗控制
  bool _overlayVisible = true;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showOverlay();
    });
  }

  @override
  void dispose() {
    _hideOverlay();
    super.dispose();
  }

  // 加载保存的设置
  Future<void> _loadSettings() async {
    // 实际项目中用 SharedPreferences 保存
  }

  // 显示悬浮窗
  void _showOverlay() {
    _hideOverlay();
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 100,
        right: 10,
        child: GestureDetector(
          onPanUpdate: (details) {
            // 拖动悬浮窗
            _overlayEntry?.markNeedsBuild();
          },
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.quiz, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _isProcessing ? '答题中...' : 'Auto Quiz',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _startQuiz,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '开始',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: _hideOverlay,
                    child: const Icon(Icons.close, color: Colors.white, size: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // 核心功能：截屏 → OCR → API → 自动点击
  Future<void> _startQuiz() async {
    if (_isProcessing) return;
    
    if (_apiUrlController.text.isEmpty || _apiKeyController.text.isEmpty) {
      _showToast('请先填写API地址和Key');
      return;
    }

    setState(() {
      _isProcessing = true;
      _status = '正在截屏...';
    });

    try {
      // 1. 通过 MethodChannel 调用原生截屏
      final screenshot = await _captureScreen();
      if (screenshot == null) {
        _showToast('截屏失败，请授予屏幕录制权限');
        setState(() {
          _isProcessing = false;
          _status = '截屏失败';
        });
        return;
      }

      // 2. OCR 识别（调用原生 ML Kit）
      setState(() => _status = '正在识别题目...');
      final ocrResult = await _performOCR(screenshot);
      if (ocrResult.isEmpty) {
        _showToast('未识别到文字');
        setState(() {
          _isProcessing = false;
          _status = '未识别到文字';
        });
        return;
      }

      // 3. 提取题目和选项
      setState(() => _status = '正在解析题目...');
      final question = _extractQuestion(ocrResult);
      if (question.isEmpty) {
        _showToast('未能解析出题目');
        setState(() {
          _isProcessing = false;
          _status = '解析失败';
        });
        return;
      }

      // 4. 调用 API 获取答案
      setState(() => _status = '正在获取答案...');
      final answer = await _getAnswer(question);
      if (answer.isEmpty) {
        _showToast('API 未返回答案');
        setState(() {
          _isProcessing = false;
          _status = '获取答案失败';
        });
        return;
      }

      // 5. 自动点击答案
      setState(() => _status = '正在点击答案...');
      await _clickAnswer(answer);

      setState(() {
        _isProcessing = false;
        _status = '答题完成！答案: $answer';
      });
      _showToast('已选择: $answer');

    } catch (e) {
      setState(() {
        _isProcessing = false;
        _status = '错误: $e';
      });
      _showToast('发生错误: $e');
    }
  }

  // 截屏（通过 MethodChannel 调用原生）
  Future<String?> _captureScreen() async {
    try {
      final result = await platform.invokeMethod('captureScreen');
      return result;
    } catch (e) {
      return null;
    }
  }

  // OCR 识别
  Future<String> _performOCR(String imagePath) async {
    try {
      final result = await platform.invokeMethod('performOCR', {'path': imagePath});
      return result ?? '';
    } catch (e) {
      return '';
    }
  }

  // 提取题目和选项（简单解析）
  String _extractQuestion(String text) {
    // 如果是纯文本识别结果，去掉冗余空格，寻找题目和选项
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return text;
    
    // 尝试组合成题目：前面部分是题干，后面是选项
    // 简单策略：合并所有行，但保留选项结构
    final cleaned = lines.map((l) => l.trim()).join('\n');
    return cleaned;
  }

  // 调用 AI API
  Future<String> _getAnswer(String question) async {
    final url = _apiUrlController.text.trim();
    final key = _apiKeyController.text.trim();
    final model = _modelController.text.trim();

    // 构建符合 OpenAI 格式的请求
    final requestBody = {
      'model': model.isNotEmpty ? model : 'glm-4-plus',
      'messages': [
        {
          'role': 'system',
          'content': '你是一个答题助手。请从题目和选项中选出正确答案，只返回选项字母（如 A、B、C、D），不要包含任何其他文字或解释。'
        },
        {
          'role': 'user',
          'content': question
        }
      ],
      'max_tokens': 20,
      'temperature': 0.1,
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $key',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content']?.toString().trim() ?? '';
        // 提取第一个字母（A/B/C/D）
        final match = RegExp(r'[A-D]').firstMatch(content.toUpperCase());
        return match?.group(0) ?? content;
      } else {
        return '';
      }
    } catch (e) {
      return '';
    }
  }

  // 自动点击（通过无障碍服务）
  Future<void> _clickAnswer(String answer) async {
    try {
      // 将答案字母转换为要点击的坐标或元素
      // 实际实现中，需要解析当前页面选项位置
      // 简化版：通过 MethodChannel 模拟点击
      await platform.invokeMethod('clickAnswer', {'answer': answer});
    } catch (e) {
      // 点击失败
    }
  }

  void _showToast(String msg) {
    // 简单的 Toast 实现
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // MethodChannel 定义
  static const platform = MethodChannel('com.example.auto_quiz/main');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auto Quiz 答题助手'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelpDialog(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 悬浮窗控制
            Row(
              children: [
                Switch(
                  value: _overlayVisible,
                  onChanged: (val) {
                    setState(() {
                      _overlayVisible = val;
                      if (val) {
                        _showOverlay();
                      } else {
                        _hideOverlay();
                      }
                    });
                  },
                ),
                const Text('显示悬浮窗'),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'API 配置',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _apiUrlController,
              decoration: const InputDecoration(
                labelText: 'API 地址',
                hintText: '例如: https://open.bigmodel.cn/api/paas/v4/',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: '请输入您的 API Key',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key),
                // 不设置 obscureText，方便复制粘贴
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: '模型名称（可选）',
                hintText: '如 glm-4-plus，不填使用默认',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.model_training),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _startQuiz,
                icon: _isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_isProcessing ? '处理中...' : '开始答题'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: _isProcessing ? Colors.grey : Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '状态',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(_status, style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('使用说明'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('1. 开启无障碍服务: 设置 → 无障碍 → Auto Quiz'),
              SizedBox(height: 8),
              Text('2. 开启屏幕录制权限（首次点击开始答题时授权）'),
              SizedBox(height: 8),
              Text('3. 填写 API 地址和 Key'),
              SizedBox(height: 8),
              Text('4. 打开题目页面，点击悬浮窗或应用内的"开始答题"'),
              SizedBox(height: 8),
              Text('5. 应用会自动截屏→识别→调用API→点击答案'),
              SizedBox(height: 8),
              Text('⚠️ 仅支持选择题，答案返回 A/B/C/D'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}
