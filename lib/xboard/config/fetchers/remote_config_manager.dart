import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import '../core/config_settings.dart';
import '../../core/core.dart';

// 初始化文件级日志器
final _logger = FileLogger('remote_config_manager.dart');

/// 远程配置状态枚举
enum RemoteConfigStatus { uninitialized, loading, success, error }

/// 配置获取结果
class ConfigResult<T> {
  final bool isSuccess;
  final T? data;
  final String? error;
  final String source;
  final RemoteConfigStatus status;
  final DateTime fetchTime;

  const ConfigResult({
    required this.isSuccess,
    this.data,
    this.error,
    required this.source,
    required this.status,
    required this.fetchTime,
  });

  factory ConfigResult.success(T data, String source) {
    return ConfigResult(
      isSuccess: true,
      data: data,
      source: source,
      status: RemoteConfigStatus.success,
      fetchTime: DateTime.now(),
    );
  }

  factory ConfigResult.failure(String error, String source) {
    return ConfigResult(
      isSuccess: false,
      error: error,
      source: source,
      status: RemoteConfigStatus.error,
      fetchTime: DateTime.now(),
    );
  }
}

/// 多配置源结果
class MultiConfigResult {
  final List<ConfigResult<Map<String, dynamic>>> results;

  const MultiConfigResult({required this.results});

  /// 明文配置源结果（兼容旧接口）
  ConfigResult<Map<String, dynamic>> get redirectResult => results.firstWhere(
    (result) => result.source == 'redirect',
    orElse: () => ConfigResult.failure('明文配置源未注册', 'redirect'),
  );

  /// 加密配置源结果（兼容旧接口，返回第一个 encrypted 结果）
  ConfigResult<Map<String, dynamic>> get encryptedResult => results.firstWhere(
    (result) => result.source.startsWith('encrypted'),
    orElse: () => ConfigResult.failure('加密配置源未注册', 'encrypted'),
  );

  /// 是否有任何一个配置源成功
  bool get hasSuccess =>
      results.any((result) => result.isSuccess && result.data != null);

  /// 获取第一个成功的配置数据
  Map<String, dynamic>? get firstSuccessfulData => firstSuccessful?.data;

  /// 获取第一个成功的配置源名称
  String? get firstSuccessfulSource => firstSuccessful?.source;

  /// 获取第一个成功的结果
  ConfigResult<Map<String, dynamic>>? get firstSuccessful {
    final successfulResults = results
        .where((result) => result.isSuccess && result.data != null)
        .toList();
    if (successfulResults.isEmpty) return null;
    successfulResults.sort(
      (a, b) => _sourcePriority(a.source).compareTo(_sourcePriority(b.source)),
    );
    return successfulResults.first;
  }

  int _sourcePriority(String source) {
    final lower = source.toLowerCase();
    if (lower == 'redirect' || lower == 'main') return 1;
    if (lower.startsWith('encrypted')) return 2;
    return 100;
  }

  @override
  String toString() {
    final summary = results.map((r) => '${r.source}: ${r.status}').join(', ');
    return 'MultiConfigResult{$summary}';
  }
}

/// HTTP客户端抽象接口
abstract class IHttpClient {
  Future<String?> getString(String url, {Duration? timeout});
}

/// 简单的HTTP客户端实现
class SimpleHttpClient implements IHttpClient {
  @override
  Future<String?> getString(String url, {Duration? timeout}) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      client.connectionTimeout = timeout ?? const Duration(seconds: 10);

      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode == 200) {
        return await response.transform(utf8.decoder).join();
      }

      return null;
    } catch (e) {
      return null;
    } finally {
      client?.close();
    }
  }
}

/// 配置源抽象接口
abstract class ConfigSource {
  String get sourceName;
  int get priority;
  Future<ConfigResult<Map<String, dynamic>>> fetchConfig();
}

/// 重定向配置源实现
class RedirectConfigSource implements ConfigSource {
  final IHttpClient _httpClient;
  final String redirectUrl;
  final Duration timeout;

  RedirectConfigSource({
    IHttpClient? httpClient,
    required this.redirectUrl,
    Duration? timeout,
  }) : _httpClient = httpClient ?? SimpleHttpClient(),
       timeout = timeout ?? const Duration(seconds: 10);

  @override
  String get sourceName => 'redirect';

  @override
  int get priority => 1;

  @override
  Future<ConfigResult<Map<String, dynamic>>> fetchConfig() async {
    try {
      _logger.info('开始获取重定向配置源: $redirectUrl');
      final rawData = await _httpClient.getString(
        redirectUrl,
        timeout: timeout,
      );

      if (rawData == null || rawData.trim().isEmpty) {
        _logger.error('重定向配置源获取失败: 数据为空');
        return ConfigResult.failure("重定向配置源获取失败", sourceName);
      }

      final jsonData = json.decode(rawData.trim()) as Map<String, dynamic>;
      _logger.info('重定向配置源获取成功');
      return ConfigResult.success(jsonData, sourceName);
    } catch (e) {
      _logger.error('重定向配置源异常', e);
      return ConfigResult.failure("重定向配置源异常: ${e.toString()}", sourceName);
    }
  }
}

/// 加密配置源实现（兼容任意托管平台：GitHub/CDN/自建服务器）
class EncryptedConfigSource implements ConfigSource {
  final IHttpClient _httpClient;
  final String name;
  final String url;
  final String encryptionKeyBase64;
  final Duration timeout;

  EncryptedConfigSource({
    IHttpClient? httpClient,
    required this.name,
    required this.url,
    required this.encryptionKeyBase64,
    Duration? timeout,
  }) : _httpClient = httpClient ?? SimpleHttpClient(),
       timeout = timeout ?? const Duration(seconds: 10);

  @override
  String get sourceName => name.toLowerCase();

  @override
  int get priority => 2;

  @override
  Future<ConfigResult<Map<String, dynamic>>> fetchConfig() async {
    try {
      final encryptedData = await _httpClient.getString(url, timeout: timeout);

      if (encryptedData == null) {
        return ConfigResult.failure("加密配置源获取失败", sourceName);
      }

      final decryptedConfig = await _decryptConfigData(encryptedData.trim());

      if (decryptedConfig == null) {
        return ConfigResult.failure("加密配置源解密失败", sourceName);
      }

      return ConfigResult.success(decryptedConfig, sourceName);
    } catch (e) {
      return ConfigResult.failure("加密配置源异常: ${e.toString()}", sourceName);
    }
  }

  /// 解密配置数据（AES-GCM解密）
  Future<Map<String, dynamic>?> _decryptConfigData(
    String encryptedBase64,
  ) async {
    try {
      final encryptedBytes = base64.decode(encryptedBase64);
      final keyBytes = base64.decode(encryptionKeyBase64);

      const nonceLength = 16;
      const tagLength = 16;

      if (encryptedBytes.length < nonceLength + tagLength) {
        throw Exception('加密数据长度不足: ${encryptedBytes.length}');
      }

      final nonce = encryptedBytes.sublist(0, nonceLength);
      final ciphertext = encryptedBytes.sublist(
        nonceLength,
        encryptedBytes.length - tagLength,
      );
      final tag = encryptedBytes.sublist(encryptedBytes.length - tagLength);

      final key = Key(keyBytes);
      final iv = IV(nonce);
      final encrypter = Encrypter(AES(key, mode: AESMode.gcm));

      final encrypted = Encrypted(Uint8List.fromList(ciphertext + tag));
      final decrypted = encrypter.decrypt(encrypted, iv: iv);

      final jsonData = json.decode(decrypted) as Map<String, dynamic>;
      return jsonData;
    } catch (e) {
      return null;
    }
  }
}

/// 远程配置源（兼容旧接口）
class RemoteConfigSource {
  final String name;
  final String url;
  final Map<String, String>? headers;
  final Duration timeout;

  const RemoteConfigSource({
    required this.name,
    required this.url,
    this.headers,
    this.timeout = const Duration(seconds: 10),
  });

  /// 从配置源获取数据
  Future<ConfigResult<Map<String, dynamic>>> fetch() async {
    try {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      client.connectionTimeout = timeout;

      final uri = Uri.parse(url);
      final request = await client.getUrl(uri);

      // 添加请求头
      if (headers != null) {
        headers!.forEach((key, value) {
          request.headers.add(key, value);
        });
      }

      final response = await request.close();

      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final data = json.decode(responseBody) as Map<String, dynamic>;

        client.close();
        return ConfigResult.success(data, name);
      } else {
        client.close();
        return ConfigResult.failure(
          'HTTP ${response.statusCode}: ${response.reasonPhrase}',
          name,
        );
      }
    } catch (e) {
      return ConfigResult.failure('Network error: $e', name);
    }
  }
}

/// 远程配置管理器
class RemoteConfigManager {
  final List<ConfigSource> _configSources;
  final int _maxRetries;
  final Duration _retryDelay;
  final bool _enableConcurrentFetch;

  RemoteConfigManager({
    List<ConfigSource>? sources,
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 2),
    bool enableConcurrentFetch = true,
  }) : _configSources = sources ?? _createDefaultSources(),
       _maxRetries = maxRetries,
       _retryDelay = retryDelay,
       _enableConcurrentFetch = enableConcurrentFetch;

  /// 从配置设置创建RemoteConfigManager
  factory RemoteConfigManager.fromSettings(RemoteConfigSettings settings) {
    final sources = <ConfigSource>[];

    var encryptedIndex = 0;
    for (final sourceConfig in settings.sources) {
      switch (sourceConfig.name.toLowerCase()) {
        case 'redirect':
        case 'main':
          sources.add(
            RedirectConfigSource(
              redirectUrl: sourceConfig.url,
              timeout: sourceConfig.timeout ?? settings.timeout,
            ),
          );
          break;
        case 'encrypted':
          if (sourceConfig.encryptionKey == null ||
              sourceConfig.encryptionKey!.isEmpty) {
            throw Exception('加密配置源必须提供 encryption_key');
          }
          encryptedIndex++;
          sources.add(
            EncryptedConfigSource(
              name: encryptedIndex == 1
                  ? 'encrypted'
                  : 'encrypted#$encryptedIndex',
              url: sourceConfig.url,
              encryptionKeyBase64: sourceConfig.encryptionKey!,
              timeout: sourceConfig.timeout ?? settings.timeout,
            ),
          );
          break;
        default:
          sources.add(
            RedirectConfigSource(
              redirectUrl: sourceConfig.url,
              timeout: sourceConfig.timeout ?? settings.timeout,
            ),
          );
          break;
      }
    }

    return RemoteConfigManager(
      sources: sources,
      maxRetries: settings.maxRetries,
      retryDelay: settings.retryDelay,
    );
  }

  /// 创建默认配置源（空列表，必须从配置文件提供）
  static List<ConfigSource> _createDefaultSources() {
    return [];
  }

  /// 从所有配置源获取配置
  Future<MultiConfigResult> fetchAllConfigs() async {
    if (_configSources.isEmpty) {
      throw Exception('没有可用的配置源');
    }

    if (_enableConcurrentFetch) {
      return MultiConfigResult(
        results: await _fetchFirstSuccessfulConcurrent(_configSources),
      );
    }

    final results = <ConfigResult<Map<String, dynamic>>>[];
    for (final source in _configSources) {
      results.add(await _fetchWithRetry(source));
      if (results.last.isSuccess && results.last.data != null) break;
    }
    return MultiConfigResult(results: results);
  }

  /// 只获取重定向配置源的结果
  Future<ConfigResult<Map<String, dynamic>>> getRedirectConfig() async {
    final redirectSource = _configSources.firstWhere(
      (source) => source.sourceName == 'redirect',
      orElse: () => throw Exception('重定向配置源未注册'),
    );
    return await _fetchWithRetry(redirectSource);
  }

  /// 只获取加密配置源的结果（支持多个 encrypted 源，返回第一个成功结果）
  Future<ConfigResult<Map<String, dynamic>>> getEncryptedConfig() async {
    final encryptedSources = _configSources
        .where((source) => source.sourceName.startsWith('encrypted'))
        .toList();
    if (encryptedSources.isEmpty) {
      throw Exception('加密配置源未注册');
    }

    if (_enableConcurrentFetch) {
      return (await _fetchFirstSuccessfulConcurrent(encryptedSources)).first;
    }

    ConfigResult<Map<String, dynamic>>? lastResult;
    for (final source in encryptedSources) {
      lastResult = await _fetchWithRetry(source);
      if (lastResult.isSuccess && lastResult.data != null) {
        return lastResult;
      }
    }
    return lastResult!;
  }

  /// 从指定配置源获取配置
  Future<ConfigResult<Map<String, dynamic>>> fetchFromSource(
    String sourceName,
  ) async {
    if (sourceName.toLowerCase() == 'encrypted') {
      return getEncryptedConfig();
    }

    final source = _configSources.firstWhere(
      (s) => s.sourceName == sourceName,
      orElse: () => throw ArgumentError('Unknown source: $sourceName'),
    );

    return await _fetchWithRetry(source);
  }

  /// 获取第一个可用的配置
  Future<ConfigResult<Map<String, dynamic>>> fetchConfig() async {
    final multiResult = await fetchAllConfigs();

    if (multiResult.hasSuccess) {
      return multiResult.firstSuccessful!;
    } else {
      return ConfigResult.failure('All config sources failed', 'all');
    }
  }

  /// 并发获取多个配置源：谁先成功解密/解析，就立刻返回谁。
  ///
  /// Dart 的 Future 无法通用取消已经发出的 HTTP 请求；这里会忽略后续结果。
  /// 如果所有源都失败，则返回所有失败结果，方便上层判断失败。
  Future<List<ConfigResult<Map<String, dynamic>>>>
  _fetchFirstSuccessfulConcurrent(List<ConfigSource> sources) {
    final completer = Completer<List<ConfigResult<Map<String, dynamic>>>>();
    final failures = <ConfigResult<Map<String, dynamic>>>[];
    var completedCount = 0;

    for (final source in sources) {
      _fetchWithRetry(source).then((result) {
        if (completer.isCompleted) return;

        completedCount++;
        if (result.isSuccess && result.data != null) {
          completer.complete([result]);
          return;
        }

        failures.add(result);
        if (completedCount == sources.length) {
          completer.complete(failures);
        }
      });
    }

    return completer.future;
  }

  /// 带重试的获取
  Future<ConfigResult<Map<String, dynamic>>> _fetchWithRetry(
    ConfigSource source,
  ) async {
    ConfigResult<Map<String, dynamic>>? lastResult;

    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      lastResult = await source.fetchConfig();

      if (lastResult.isSuccess) {
        return lastResult;
      }

      // 如果不是最后一次尝试，等待后重试
      if (attempt < _maxRetries) {
        await Future.delayed(_retryDelay);
      }
    }

    return lastResult!;
  }

  /// 添加配置源
  void addSource(ConfigSource source) {
    _configSources.add(source);
  }

  /// 移除配置源
  void removeSource(String sourceName) {
    _configSources.removeWhere((source) => source.sourceName == sourceName);
  }

  /// 获取所有配置源名称
  List<String> get sourceNames =>
      _configSources.map((s) => s.sourceName).toList();

  /// 获取配置源数量
  int get sourceCount => _configSources.length;
}
