import 'package:dio/dio.dart';

/// 统一解析 LLM 请求异常并提供中文诊断与可重试判断。
class LlmErrorMapper {
  /// 是否为临时性网络/服务抖动（可重试）。
  static bool isTransient(Object error) {
    if (error is DioException) {
      if (error.type == DioExceptionType.cancel) return false;
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError) {
        return true;
      }
      final status = error.response?.statusCode;
      if (status != null) {
        // 429 限频、5xx 服务器错误可重试
        if (status == 429 || (status >= 500 && status < 600)) {
          return true;
        }
      }
    }
    return false;
  }

  /// 转换为对医生友好的排错说明。
  static String describe(Object error) {
    if (error is DioException) {
      if (error.type == DioExceptionType.cancel) return '已取消生成';
      if (error.type == DioExceptionType.connectionTimeout) {
        return '连接大模型服务器超时，请检查网络或代理';
      }
      if (error.type == DioExceptionType.receiveTimeout) {
        return '模型响应超时（超过等待时限），模型可能正在高负荷运算';
      }
      if (error.type == DioExceptionType.connectionError) {
        return '网络连接失败，请检查手机网络或接口地址设置';
      }

      final status = error.response?.statusCode;
      final serverMsg = _extractServerMessage(error.response?.data);

      switch (status) {
        case 401:
          return 'API Key 无效或已过期，请前往「设置」更新';
        case 403:
          return '无权访问该模型，请检查账户权限或模型名称';
        case 404:
          return '模型未找到或接口地址错误，请核对 Base URL 与 Model 名称';
        case 429:
          return '触发请求频率限制 (429 Rate Limit)，请稍候重试';
        case 500:
        case 502:
        case 503:
        case 504:
          return '模型服务提供方内部错误 (HTTP $status)${serverMsg.isNotEmpty ? ": $serverMsg" : "，请稍后重试"}';
        default:
          if (status != null) {
            return '请求失败 (HTTP $status)${serverMsg.isNotEmpty ? ": $serverMsg" : ""}';
          }
      }
      return '网络请求异常: ${error.message ?? error.toString()}';
    }
    return error.toString();
  }

  static String _extractServerMessage(dynamic data) {
    if (data == null) return '';
    try {
      if (data is Map) {
        final err = data['error'];
        if (err is Map && err['message'] != null) {
          return err['message'].toString();
        }
        if (err is String) return err;
        if (data['message'] != null) return data['message'].toString();
      }
    } catch (_) {}
    return '';
  }
}
