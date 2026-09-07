import 'dart:io' as io;

import 'package:simple_live_core/src/common/core_error.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'custom_interceptor.dart';

class HttpClient {
  static HttpClient? _httpUtil;

  // 代理配置（静态，所有实例共享）
  static bool _proxyEnabled = false;
  static String _proxyAddress = "";
  static bool _proxyBilibiliOnly = true;

  /// 动态设置代理配置，即时生效
  static void setProxySettings({
    required bool enabled,
    required String address,
    bool bilibiliOnly = true,
  }) {
    _proxyEnabled = enabled;
    _proxyAddress = address;
    _proxyBilibiliOnly = bilibiliOnly;
    _httpUtil?._applyProxy();
  }

  /// 当前是否启用代理
  static bool get isProxyEnabled => _proxyEnabled;

  /// 当前代理地址（已去除首尾空格）
  static String get proxyAddress => _proxyAddress.trim();

  /// 是否仅代理 B 站相关域名
  static bool get isProxyBilibiliOnly => _proxyBilibiliOnly;

  /// 解析访问 [host] 时应使用的代理地址；应直连时返回 null。
  /// HTTP 请求与弹幕 WebSocket 共用同一套判定，避免两处逻辑不一致。
  static String? resolveProxy(String host) {
    if (!_proxyEnabled || _proxyAddress.trim().isEmpty) {
      return null;
    }
    if (_proxyBilibiliOnly &&
        !host.contains('bilibili.com') &&
        !host.contains('bilivideo.cn')) {
      return null;
    }
    return _proxyAddress.trim();
  }

  static HttpClient get instance {
    _httpUtil ??= HttpClient();
    return _httpUtil!;
  }

  late Dio dio;
  HttpClient() {
    dio = Dio(
      BaseOptions(
        connectTimeout: Duration(seconds: 20),
        receiveTimeout: Duration(seconds: 20),
        sendTimeout: Duration(seconds: 20),
      ),
    );

    _applyProxy();
    dio.interceptors.add(CustomInterceptor());
  }

  /// 根据当前代理配置应用到 dio
  void _applyProxy() {
    if (!_proxyEnabled || _proxyAddress.trim().isEmpty) {
      // 关闭代理，恢复默认 adapter（直连）
      dio.httpClientAdapter = IOHttpClientAdapter();
      return;
    }

    final adapter = IOHttpClientAdapter();
    adapter.createHttpClient = () {
      final client = io.HttpClient();
      client.findProxy = (uri) {
        final proxy = resolveProxy(uri.host);
        return proxy == null ? "DIRECT" : "PROXY $proxy";
      };
      return client;
    };
    dio.httpClientAdapter = adapter;
  }

  /// Get请求，返回String
  /// * [url] 请求链接
  /// * [queryParameters] 请求参数
  /// * [cancel] 任务取消Token
  Future<String> getText(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
    CancelToken? cancel,
  }) async {
    try {
      queryParameters ??= {};
      header ??= {};
      var result = await dio.get(
        url,
        queryParameters: queryParameters,
        options: Options(
          responseType: ResponseType.plain,
          headers: header,
        ),
        cancelToken: cancel,
      );
      return result.data;
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.badResponse) {
        throw CoreError(e.message ?? "",
            statusCode: e.response?.statusCode ?? 0);
      } else {
        throw CoreError("发送GET请求失败");
      }
    }
  }

  /// Get请求，返回Map
  /// * [url] 请求链接
  /// * [queryParameters] 请求参数
  /// * [cancel] 任务取消Token
  Future<dynamic> getJson(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
    CancelToken? cancel,
  }) async {
    try {
      queryParameters ??= {};
      header ??= {};
      var result = await dio.get(
        url,
        queryParameters: queryParameters,
        options: Options(
          responseType: ResponseType.json,
          headers: header,
        ),
        cancelToken: cancel,
      );
      return result.data;
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.badResponse) {
        throw CoreError(e.message ?? "",
            statusCode: e.response?.statusCode ?? 0);
      } else {
        throw CoreError("发送GET请求失败");
      }
    }
  }

  /// Post请求，返回Map
  /// * [url] 请求链接
  /// * [queryParameters] 请求参数
  /// * [data] 内容
  /// * [cancel] 任务取消Token
  Future<dynamic> postJson(
    String url, {
    Map<String, dynamic>? queryParameters,
    dynamic data,
    Map<String, dynamic>? header,
    bool formUrlEncoded = false,
    CancelToken? cancel,
  }) async {
    try {
      queryParameters ??= {};
      header ??= {};
      data ??= {};
      var result = await dio.post(
        url,
        queryParameters: queryParameters,
        data: data,
        options: Options(
          responseType: ResponseType.json,
          headers: header,
          contentType:
              formUrlEncoded ? Headers.formUrlEncodedContentType : null,
        ),
        cancelToken: cancel,
      );
      return result.data;
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.badResponse) {
        throw CoreError(e.message ?? "",
            statusCode: e.response?.statusCode ?? 0);
      } else {
        throw CoreError("发送POST请求失败");
      }
    }
  }

  /// Head请求，返回Response
  /// * [url] 请求链接
  /// * [queryParameters] 请求参数
  /// * [cancel] 任务取消Token
  Future<Response> head(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? header,
    CancelToken? cancel,
  }) async {
    try {
      queryParameters ??= {};
      header ??= {};
      var result = await dio.head(
        url,
        queryParameters: queryParameters,
        options: Options(
          headers: header,
          receiveDataWhenStatusError: true,
        ),
        cancelToken: cancel,
      );
      return result;
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.badResponse) {
        //throw CoreError(e.message, statusCode: e.response?.statusCode ?? 0);
        return e.response!;
      } else {
        throw CoreError("发送HEAD请求失败");
      }
    }
  }
}
