import 'dart:io';

import 'package:flutter/material.dart';

/// 应用背景层：在最底层铺一张自定义背景图，并压一层黑色半透明遮罩保证可读性。
///
/// [imagePath] 为空时直接返回 [child]，界面与原来完全一致（默认纯色主题背景）。
/// 有背景图时，[child]（外壳 Scaffold）需把自身背景设为透明，图片才能透出来；
/// 侧边栏、文件栏、工具栏与卡片仍是各自的不透明表面，文字与语义色不受影响。
///
/// 图片只解码一次并由 Flutter 的图片缓存复用；[cacheWidth] 把解码宽度限制在约
/// 2K，避免超大图导致内存溢出或卡顿。
class AppBackground extends StatelessWidget {
  const AppBackground({
    required this.imagePath,
    required this.child,
    super.key,
  });

  /// 背景图本地路径；null / 空串表示使用默认背景。
  final String? imagePath;

  final Widget child;

  /// 解码宽度下限（逻辑像素 × dpr 太小则放大到此值，保证清晰）。
  static const int _minDecodeWidth = 720;

  /// 解码宽度上限（约 2K），限制超大图的内存占用。
  static const int _maxDecodeWidth = 2560;

  @override
  Widget build(BuildContext context) {
    final path = imagePath?.trim() ?? '';
    if (path.isEmpty) return child;

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          File(path),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: _decodeWidth(context),
          errorBuilder: (context, error, stackTrace) =>
              const ColoredBox(color: Colors.black),
        ),
        // 约 45% 的黑色遮罩：压住背景图的杂乱底色，保证上层文字与按钮清晰。
        const ColoredBox(color: Color.fromRGBO(0, 0, 0, 0.45)),
        child,
      ],
    );
  }

  int _decodeWidth(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final target = (size.longestSide * dpr).round();
    if (target < _minDecodeWidth) return _minDecodeWidth;
    if (target > _maxDecodeWidth) return _maxDecodeWidth;
    return target;
  }
}
