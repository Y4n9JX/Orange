import 'dart:async';

import 'package:fl_clash/xboard/config/xboard_config.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_all/webview_all.dart';

class ChatwaySupportPage extends StatefulWidget {
  const ChatwaySupportPage({super.key});

  @override
  State<ChatwaySupportPage> createState() => _ChatwaySupportPageState();
}

class _ChatwaySupportPageState extends State<ChatwaySupportPage> {
  WebViewController? _controller;
  String? _supportUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initSupportPage();
  }

  Future<void> _initSupportPage() async {
    try {
      final panelUrl = await XBoardConfig.getFastestPanelUrl() ?? XBoardConfig.panelUrl;
      if (panelUrl == null || panelUrl.isEmpty) {
        throw Exception('panel url unavailable');
      }
      _supportUrl = panelUrl;
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (String _) {
              _isolateChatwayLauncher();
            },
          ),
        )
        ..loadRequest(Uri.parse(panelUrl));
    } catch (_) {
      _supportUrl = null;
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _isolateChatwayLauncher() async {
    final controller = _controller;
    if (controller == null) return;

    const script = r'''
      (() => {
        const keepElement = (el) => {
          if (!el) return false;
          const html = `${el.id || ''} ${el.className || ''}`.toLowerCase();
          if (html.includes('chatway')) return true;
          const rect = el.getBoundingClientRect?.();
          const style = window.getComputedStyle?.(el);
          if (!rect || !style) return false;
          const nearBottomRight = rect.right > window.innerWidth - 180 && rect.bottom > window.innerHeight - 180;
          const floating = style.position === 'fixed' || style.position === 'sticky';
          return floating && nearBottomRight;
        };

        const hideOthers = () => {
          document.documentElement.style.overflow = 'hidden';
          document.body.style.overflow = 'hidden';
          document.body.style.background = 'transparent';

          Array.from(document.body.children).forEach((el) => {
            const hasChatwayDescendant = el.querySelector?.('[id*="chatway" i], [class*="chatway" i], [data-chatway-launcher], [data-chatway-widget]');
            if (keepElement(el) || hasChatwayDescendant) {
              el.style.visibility = 'visible';
              el.style.opacity = '1';
              el.style.pointerEvents = 'auto';
              el.style.background = 'transparent';
              el.style.zIndex = '2147483647';
            } else {
              el.style.visibility = 'hidden';
              el.style.opacity = '0';
              el.style.pointerEvents = 'none';
            }
          });
        };

        hideOthers();
        const observer = new MutationObserver(() => hideOthers());
        observer.observe(document.body, { childList: true, subtree: true, attributes: true });
      })();
    ''';

    try {
      await controller.runJavaScript(script);
    } catch (_) {}
  }

  Future<void> _openExternalSupport() async {
    try {
      final target = _supportUrl;
      if (target == null || target.isEmpty) {
        throw Exception('empty support url');
      }
      final uri = Uri.parse(target);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('launch failed');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开官网客服页面，请检查面板地址配置')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_controller != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('在线客服'),
          actions: [
            IconButton(
              onPressed: _openExternalSupport,
              icon: const Icon(Icons.open_in_new),
              tooltip: '浏览器打开',
            ),
          ],
        ),
        body: WebViewWidget(controller: _controller!),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('在线客服'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.support_agent, size: 56),
              const SizedBox(height: 16),
              const Text(
                '正在加载官网客服页面',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                '加载完成后，你可以直接点击右下角的 Chatway 按钮联系在线客服。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _openExternalSupport,
                icon: const Icon(Icons.open_in_browser),
                label: const Text('打开客服网页'),
              ),
              const SizedBox(height: 12),
              SelectableText(_supportUrl ?? '未获取到官网地址', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
