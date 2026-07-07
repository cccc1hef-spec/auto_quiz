import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Auto Quiz',
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue)),
        home: const HomePage(),
        debugShowCheckedModeBanner: false,
      );
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
  OverlayEntry? _overlayEntry;
  bool _overlayVisible = true;

  // ⚠️ 暂时注释掉 MethodChannel，避免原生调用
  // static const platform = MethodChannel('com.example.auto_quiz/main');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showOverlay());
  }

  @override
  void dispose() {
    _hideOverlay();
    super.dispose();
  }

  void _showOverlay() {
    _hideOverlay();
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 100,
        right: 10,
        child: GestureDetector(
          onPanUpdate: (details) {},
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.quiz, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _isProcessing ? '答题中...' : 'Auto Quiz',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                      child: const Text('开始', style: TextStyle(color: Colors.white)),
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

  Future<void> _startQuiz() async {
    if (_isProcessing) return;
    if (_apiUrlController.text.isEmpty || _apiKeyController.text.isEmpty) {
      _showToast('请填写API地址和Key');
      return;
    }
    setState(() {
      _isProcessing = true;
      _status = '正在模拟答题...';
    });

    // ⚠️ 暂时不调用原生方法，只模拟 API 请求
    try {
      final answer = await _getAnswer('请回答 1+1 等于几？');
      setState(() {
        _status = '模拟完成！答案: $answer';
        _isProcessing = false;
      });
      _showToast('模拟答案: $answer');
    } catch (e) {
      setState(() {
        _status = '错误: $e';
        _isProcessing = false;
      });
      _showToast('错误: $e');
    }
  }

  Future<String> _getAnswer(String question) async {
    final url = _apiUrlController.text.trim();
    final key = _apiKeyController.text.trim();
    final model = _modelController.text.trim();
    final body = {
      'model': model.isNotEmpty ? model : 'glm-4-plus',
      'messages': [
        {'role': 'system', 'content': '只返回选项字母（A/B/C/D），不加其他文字。'},
        {'role': 'user', 'content': question}
      ],
      'max_tokens': 10,
      'temperature': 0.1,
    };
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $key'},
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content']?.toString().trim() ?? '';
        final match = RegExp(r'[A-D]').firstMatch(content.toUpperCase());
        return match?.group(0) ?? content;
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auto Quiz'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.help),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('使用说明'),
                content: const Text(
                  '1. 开启无障碍服务\n'
                  '2. 开启屏幕录制权限\n'
                  '3. 填写API配置\n'
                  '4. 打开题目页面，点击悬浮窗"开始"',
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(_), child: const Text('知道'))],
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('显示悬浮窗'),
              value: _overlayVisible,
              onChanged: (v) {
                setState(() {
                  _overlayVisible = v;
                  v ? _showOverlay() : _hideOverlay();
                });
              },
            ),
            TextField(
              controller: _apiUrlController,
              decoration: const InputDecoration(
                labelText: 'API 地址',
                hintText: 'https://open.bigmodel.cn/api/paas/v4/',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: '粘贴你的 Key',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: '模型（可选）',
                hintText: 'glm-4-plus',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _startQuiz,
                child: Text(_isProcessing ? '处理中...' : '开始答题'),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.grey.shade100,
              child: Row(children: [const Text('状态: '), Expanded(child: Text(_status))]),
            ),
          ],
        ),
      ),
    );
  }
}
