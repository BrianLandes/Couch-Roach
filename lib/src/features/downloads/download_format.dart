import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Human-readable byte size, e.g. `1.4 GB`. Pure + tested.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// Download speed, e.g. `3.2 MB/s`. Zero renders as an em dash.
String formatSpeed(int bytesPerSecond) {
  if (bytesPerSecond <= 0) return '—';
  return '${formatBytes(bytesPerSecond)}/s';
}

/// Estimated time left from a seconds count, e.g. `4m 12s`, `2h 5m`, `3d 4h`.
/// Null (unknown) renders as an em dash. Pure + tested.
String formatEta(int? seconds) {
  if (seconds == null || seconds <= 0) return '—';
  final d = seconds ~/ 86400;
  final h = (seconds % 86400) ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (d > 0) return '${d}d ${h}h';
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

/// A friendly label + accent color for a raw qBittorrent state string.
({String label, Color color}) describeTorrentState(String state) {
  switch (state) {
    case 'downloading':
    case 'forcedDL':
    case 'metaDL':
    case 'allocating':
      return (label: 'Downloading', color: AppColors.secondary);
    case 'stalledDL':
      return (label: 'Stalled', color: AppColors.warning);
    case 'queuedDL':
      return (label: 'Queued', color: AppColors.textSecondary);
    case 'checkingDL':
    case 'checkingUP':
    case 'checkingResumeData':
    case 'moving':
      return (label: 'Checking', color: AppColors.textSecondary);
    case 'pausedDL':
    case 'stoppedDL':
      return (label: 'Paused', color: AppColors.textTertiary);
    case 'uploading':
    case 'forcedUP':
    case 'stalledUP':
    case 'queuedUP':
    case 'pausedUP':
    case 'stoppedUP':
    case 'checkedUP':
      return (label: 'Complete', color: AppColors.success);
    case 'error':
    case 'missingFiles':
      return (label: 'Error', color: AppColors.danger);
    default:
      return (label: state.isEmpty ? 'Unknown' : state, color: AppColors.textSecondary);
  }
}
