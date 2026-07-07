// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DownloadResponse _$DownloadResponseFromJson(Map<String, dynamic> json) =>
    DownloadResponse(
      link: json['link'] as String,
      fileName: json['file_name'] as String?,
      requests: (json['requests'] as num?)?.toInt(),
      remaining: (json['remaining'] as num?)?.toInt(),
      message: json['message'] as String?,
      resetTime: json['reset_time'] as String?,
    );

Map<String, dynamic> _$DownloadResponseToJson(DownloadResponse instance) =>
    <String, dynamic>{
      'link': instance.link,
      'file_name': instance.fileName,
      'requests': instance.requests,
      'remaining': instance.remaining,
      'message': instance.message,
      'reset_time': instance.resetTime,
    };
