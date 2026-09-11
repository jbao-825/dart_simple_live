import 'dart:async';
import 'dart:io' as io;
import 'dart:math';

import 'package:web_socket_channel/io.dart';

import 'http_client.dart';

enum SocketStatus { connected, failed, closed }

class WebScoketUtils {
  SocketStatus status = SocketStatus.closed;

  /// 链接
  final String url;

  /// 备用链接
  final String? backupUrl;

  /// 备用链接列表
  final List<String> backupUrls;

  /// 心跳时间
  final int heartBeatTime;

  /// 接收到信息
  final Function(dynamic)? onMessage;

  /// 连接关闭
  final Function(String msg)? onClose;

  /// 尝试重连
  final Function()? onReconnect;

  /// 准备就绪
  final Function()? onReady;

  /// 心跳
  final Function()? onHeartBeat;

  /// 请求头
  Map<String, dynamic>? headers;

  /// 单个候选地址的连接超时时间。
  final Duration connectTimeout;

  /// 是否随机化候选地址顺序。
  final bool shuffleUrls;

  /// 每轮最多尝试的候选地址数量，null 表示全部尝试。
  final int? maxConnectAttempts;

  /// 连接断开后的重连间隔。
  final Duration reconnectDelay;

  WebScoketUtils({
    required this.url,
    required this.heartBeatTime,
    this.onMessage,
    this.onClose,
    this.onReconnect,
    this.onReady,
    this.onHeartBeat,
    this.headers,
    this.backupUrl,
    this.backupUrls = const [],
    this.connectTimeout = const Duration(seconds: 10),
    this.shuffleUrls = false,
    this.maxConnectAttempts,
    this.reconnectDelay = const Duration(seconds: 5),
  });
  IOWebSocketChannel? webSocket;
  Timer? heartBeatTimer;

  /// 重连次数
  int reconnectTime = 0;
  Timer? reconnectTimer;

  /// 最大重连次数
  int maxReconnectTime = 5;

  StreamSubscription<dynamic>? streamSubscription;

  /// 走代理时持有的 HttpClient，连接关闭时一并释放，避免泄漏
  io.HttpClient? _proxyClient;
  bool _manualClosed = true;
  bool _connecting = false;

  List<String> get _connectUrls {
    final urls = <String>[url];
    if (backupUrl != null && backupUrl!.isNotEmpty) {
      urls.add(backupUrl!);
    }
    urls.addAll(backupUrls.where((url) => url.isNotEmpty));
    return urls.toSet().toList();
  }

  /// Exposes the de-duplicated candidate order for diagnostics and tests.
  List<String> get connectUrls => List.unmodifiable(_connectUrls);

  void connect({bool retry = false}) async {
    if (_connecting) {
      return;
    }
    _manualClosed = false;
    reconnectTimer?.cancel();
    reconnectTimer = null;
    _connecting = true;
    streamSubscription?.cancel();
    streamSubscription = null;
    heartBeatTimer?.cancel();
    heartBeatTimer = null;
    try {
      await webSocket?.sink.close();
    } catch (_) {}
    webSocket = null;
    final urls = _connectUrls.toList();
    if (shuffleUrls) {
      urls.shuffle(Random());
    }
    final candidates = retry && urls.length > 1 ? urls.skip(1).toList() : urls;
    final limitedUrls = maxConnectAttempts == null
        ? candidates
        : candidates.take(maxConnectAttempts!).toList();
    Object? lastError;
    StackTrace? lastStackTrace;
    try {
      for (final wsurl in limitedUrls) {
        if (_manualClosed) {
          return;
        }
        io.HttpClient? proxyClient;
        try {
          // 与 HTTP 请求共用同一套代理判定：仅 B 站域名且已启用代理时走代理
          final proxy = HttpClient.resolveProxy(Uri.parse(wsurl).host);
          if (proxy != null) {
            proxyClient = io.HttpClient();
            proxyClient.findProxy = (_) => "PROXY $proxy";
          }
          final socket = await io.WebSocket.connect(
            wsurl,
            headers: headers,
            customClient: proxyClient,
          ).timeout(connectTimeout);
          // 等待连接期间若已被手动关闭，释放刚建立的连接并退出
          if (_manualClosed) {
            await socket.close();
            proxyClient?.close(force: true);
            return;
          }
          webSocket = IOWebSocketChannel(socket);
          _proxyClient = proxyClient;
          ready();
          return;
        } catch (e, s) {
          lastError = e;
          lastStackTrace = s;
          try {
            await webSocket?.sink.close();
          } catch (_) {}
          webSocket = null;
          proxyClient?.close(force: true);
        }
      }
      if (!_manualClosed) {
        onError(lastError ?? "WebSocket connection failed", lastStackTrace);
      }
    } finally {
      _connecting = false;
    }
  }

  /// 连接完成
  void ready() {
    status = SocketStatus.connected;

    heartBeatTimer?.cancel();

    streamSubscription = webSocket?.stream.listen(
      (data) => receiveMessage(data),
      onError: (e, s) => onError(e, s),
      onDone: onDone,
    );

    onReady?.call();
    initHeartBeat();
  }

  void initHeartBeat() {
    heartBeatTimer = Timer.periodic(Duration(milliseconds: heartBeatTime), (
      timer,
    ) {
      onHeartBeat?.call();
    });
  }

  void receiveMessage(dynamic data) {
    //接受到一条信息才算重连成功
    reconnectTime = 0;
    onMessage?.call(data);
  }

  void onError(e, s) {
    status = SocketStatus.failed;
    onClose?.call(e.toString());
  }

  void onDone() {
    if (status == SocketStatus.closed) {
      return;
    }
    onReconnect?.call();
    reconnect();
  }

  void sendMessage(dynamic message) {
    if (status == SocketStatus.connected) {
      webSocket?.sink.add(message);
    }
  }

  void close() {
    _manualClosed = true;
    status = SocketStatus.closed;

    streamSubscription?.cancel();

    reconnectTimer?.cancel();
    reconnectTimer = null;

    webSocket?.sink.close();

    _proxyClient?.close(force: true);
    _proxyClient = null;

    heartBeatTimer?.cancel();
    heartBeatTimer = null;
  }

  void reconnect() {
    if (_manualClosed || reconnectTimer != null) {
      return;
    }
    status = SocketStatus.closed;
    if (reconnectTime < maxReconnectTime) {
      reconnectTime++;
      reconnectTimer = Timer(reconnectDelay, () {
        reconnectTimer = null;
        connect();
      });
    } else {
      onClose?.call("重连超过最大次数，与服务器断开连接");
      reconnectTimer?.cancel();
      reconnectTimer = null;
      close();
      return;
    }
  }
}
