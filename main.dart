import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:image_picker/image_picker.dart';
import 'chat_api.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const ChatHomePage(),
    );
  }
}

class ChatHomePage extends StatefulWidget {
  const ChatHomePage({super.key});
  @override
  State<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends State<ChatHomePage>
    with SingleTickerProviderStateMixin {
  final List<String> conversations = ["对话 1"];
  final Map<int, List<Map<String, dynamic>>> messages = {0: []};
  int currentIndex = 0;

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool isTyping = false;
  bool isAIStreaming = false;
  bool showScrollDownButton = false;

  late ChatApi chatApi;
  late stt.SpeechToText _speech;
  bool _isListening = false;

  late AnimationController _dotController;
  late Animation<double> _dotAnimation;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // 保持和你原来一样的初始化
    chatApi = ChatApi("your-api-key-here");
    _speech = stt.SpeechToText();

    _controller.addListener(() {
      setState(() {
        isTyping = _controller.text.trim().isNotEmpty;
      });
    });

    _scrollController.addListener(_handleScroll);

    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _dotAnimation = Tween<double>(
      begin: 4.0,
      end: 12.0,
    ).animate(CurvedAnimation(parent: _dotController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _dotController.dispose();
    _scrollController.removeListener(_handleScroll);
    _controller.dispose();
    super.dispose();
  }

  void _handleScroll() {
    final scrollPosition = _scrollController.position;
    final shouldShowButton =
        scrollPosition.pixels > 100 &&
        scrollPosition.maxScrollExtent - scrollPosition.pixels > 100;

    if (shouldShowButton != showScrollDownButton) {
      setState(() {
        showScrollDownButton = shouldShowButton;
      });
    }
  }

  void _newConversation() {
    setState(() {
      conversations.add("对话 ${conversations.length + 1}");
      currentIndex = conversations.length - 1;
      messages[currentIndex] = [];
      showScrollDownButton = false;
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      messages[currentIndex]?.add({"role": "user", "content": text});
      _controller.clear();
      isTyping = false;
      messages[currentIndex]?.add({"role": "assistant", "content": ""});
      isAIStreaming = true;
      showScrollDownButton = false;
    });

    final aiIndex = messages[currentIndex]!.length - 1;
    _scrollToBottom();

    try {
      await for (var chunk in chatApi.sendMessageStream(text)) {
        if (!isAIStreaming) break;

        for (var char in chunk.split('')) {
          if (!isAIStreaming) break;
          await Future.delayed(const Duration(milliseconds: 25));
          setState(() {
            messages[currentIndex]![aiIndex]["content"] =
                (messages[currentIndex]![aiIndex]["content"] ?? "") + char;
          });

          if (_scrollController.hasClients &&
              _scrollController.position.pixels >=
                  _scrollController.position.maxScrollExtent - 100) {
            _scrollToBottom();
          }
        }
      }
    } finally {
      setState(() {
        isAIStreaming = false;
      });
      _scrollToBottom();
    }
  }

  void _stopAIStreaming() {
    setState(() {
      isAIStreaming = false;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
        setState(() {
          showScrollDownButton = false;
        });
      }
    });
  }

  void _startListening() async {
    bool available = await _speech.initialize(
      onStatus: (status) {},
      onError: (error) {},
    );
    if (!available) return;

    setState(() {
      _isListening = true;
    });

    _speech.listen(
      onResult: (result) {
        _controller.text = result.recognizedWords;
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
        if (result.finalResult) {
          _speech.stop();
          setState(() {
            _isListening = false;
            isTyping = _controller.text.trim().isNotEmpty;
          });
        }
      },
    );
  }

  void _stopListening() {
    _speech.stop();
    setState(() {
      _isListening = false;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image != null) {
      setState(() {
        messages[currentIndex]?.add({"role": "user", "image": image.path});
      });
      _scrollToBottom();
    }
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: Icon(Icons.photo),
                title: const Text('相册'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: Icon(Icons.camera_alt),
                title: const Text('拍照'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Icon(Icons.search),
                title: const Text('联网搜索'),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.insert_drive_file),
                title: const Text('上传文件'),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Helper: 在长连续无空格的字符串中插入零宽空格（\u200B），以便允许换行避免 overflow。
  String _insertZeroWidthSpaces(String text, {int chunk = 40}) {
    if (text.isEmpty) return text;
    return text.replaceAllMapped(RegExp(r'(\S{' + chunk.toString() + ',})'), (
      m,
    ) {
      final s = m[0]!;
      final sb = StringBuffer();
      for (var i = 0; i < s.length; i++) {
        sb.write(s[i]);
        if ((i + 1) % chunk == 0 && i != s.length - 1) sb.write('\u200B');
      }
      return sb.toString();
    });
  }

  Widget _buildUserBubble(Map<String, dynamic> msg) {
    final content = msg["content"] ?? "";
    final imagePath = msg["image"];
    final displayContent = _insertZeroWidthSpaces(content, chunk: 30);

    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (imagePath != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Image.file(
                  File(imagePath),
                  width: 200,
                  fit: BoxFit.cover,
                ),
              ),
            if (content.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  displayContent,
                  style: const TextStyle(color: Colors.black),
                  softWrap: true,
                ),
              ),
            if (content.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, size: 16),
                    onPressed: () {
                      _controller.text = content;
                      _controller.selection = TextSelection.fromPosition(
                        TextPosition(offset: _controller.text.length),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      Clipboard.setData(ClipboardData(text: content));
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text("已复制")));
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// --- 修复后的 Markdown + 打字机效果的 AI Bubble ---
  Widget _buildAIBubble(Map<String, dynamic> msg, int index) {
    final content = msg["content"] ?? "";
    final isLastAI =
        index == messages[currentIndex]!.length - 1 && isAIStreaming;

    if (content.isEmpty && isLastAI) {
      // 流式输出动画
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return AnimatedBuilder(
              animation: _dotAnimation,
              builder: (_, child) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: _dotAnimation.value,
                  height: _dotAnimation.value,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                );
              },
            );
          }),
        ),
      );
    } else {
      // 使用修复后的布局来渲染 Markdown
      final maxBubbleWidth = MediaQuery.of(context).size.width * 0.85;

      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
        ),
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 使用 SingleChildScrollView 包装整个内容，防止溢出
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: maxBubbleWidth - 24, // 减去padding
                ),
                child: GptMarkdown(
                  content,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  codeBuilder: (BuildContext ctx, String name, String code, bool closed) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SelectableText(
                          code,
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    );
                  },
                  imageBuilder: (BuildContext ctx, String imageUrl) {
                    return Image.network(imageUrl, fit: BoxFit.contain);
                  },
                  useDollarSignsForLatex: false,
                ),
              ),
            ),
            if (!isLastAI)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.copy, size: 16, color: Colors.white),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: content));
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text("已复制")));
                  },
                ),
              ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: ListView(
          children: [
            Container(
              height: 120,
              color: Colors.black87,
              child: const Center(
                child: Text(
                  "对话记录",
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
            ),
            for (int i = 0; i < conversations.length; i++)
              ListTile(
                title: Text(conversations[i]),
                onTap: () {
                  setState(() {
                    currentIndex = i;
                  });
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
        title: Text(
          conversations[currentIndex],
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _newConversation,
          ),
        ],
      ),
      body: Container(
        color: Colors.black,
        child: Column(
          children: [
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                trackVisibility: true,
                thickness: 8.0,
                radius: const Radius.circular(4.0),
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages[currentIndex]?.length ?? 0,
                  itemBuilder: (context, index) {
                    final msg = messages[currentIndex]![index];
                    if (msg["role"] == "user") {
                      return _buildUserBubble(msg);
                    } else {
                      return _buildAIBubble(msg, index);
                    }
                  },
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(24),
              ),
              constraints: const BoxConstraints(maxHeight: 120),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.white),
                    onPressed: _showAddOptions,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      maxLines: null,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: "询问任何问题",
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      style: const TextStyle(color: Colors.white),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _isListening ? Icons.mic_off : Icons.mic,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      if (_isListening) {
                        _stopListening();
                      } else {
                        _startListening();
                      }
                    },
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        isAIStreaming
                            ? Icons.stop
                            : (isTyping
                                  ? Icons.arrow_upward
                                  : Icons.graphic_eq),
                        color: Colors.black,
                      ),
                      onPressed: () {
                        if (isAIStreaming) {
                          _stopAIStreaming();
                        } else if (isTyping) {
                          _sendMessage();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}