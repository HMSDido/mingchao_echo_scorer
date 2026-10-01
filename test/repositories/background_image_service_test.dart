import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mingchao_echo_scorer/data/repositories/background_image_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;
  late Directory storeDir;
  late BackgroundImageService service;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('echo_scorer_bg');
    storeDir = Directory(p.join(tempRoot.path, 'background'));
    service = BackgroundImageService(storeDir);
  });

  tearDown(() async {
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  Future<File> fakeImage(String name) async {
    final file = File(p.join(tempRoot.path, name));
    await file.writeAsBytes(const [1, 2, 3, 4]);
    return file;
  }

  test('isAllowedPath 只接受 jpg/jpeg/png/webp', () {
    expect(BackgroundImageService.isAllowedPath('a.png'), isTrue);
    expect(BackgroundImageService.isAllowedPath('a.JPG'), isTrue);
    expect(BackgroundImageService.isAllowedPath('a.jpeg'), isTrue);
    expect(BackgroundImageService.isAllowedPath('a.webp'), isTrue);
    expect(BackgroundImageService.isAllowedPath('a.gif'), isFalse);
    expect(BackgroundImageService.isAllowedPath('a.txt'), isFalse);
    expect(BackgroundImageService.isAllowedPath('无扩展名'), isFalse);
    expect(BackgroundImageService.isAllowedPath(null), isFalse);
  });

  test('import 把图片复制进私有目录并返回新路径，源文件保留', () async {
    final source = await fakeImage('wallpaper.png');
    final stored = await service.import(source);

    expect(p.dirname(stored), storeDir.path);
    expect(p.extension(stored), '.png');
    expect(await File(stored).exists(), isTrue);
    expect(await source.exists(), isTrue, reason: '导入是复制，不应删掉原图');
  });

  test('import 用唯一文件名，替换时删除上一张背景', () async {
    final first = await fakeImage('one.png');
    final second = await fakeImage('two.jpg');

    final pathA = await service.import(first);
    // 保证时间戳不同，避免同毫秒命名冲突。
    await Future<void>.delayed(const Duration(milliseconds: 2));
    final pathB = await service.import(second, previousPath: pathA);

    expect(pathA, isNot(pathB));
    expect(p.extension(pathB), '.jpg');
    expect(await File(pathB).exists(), isTrue);
    expect(await File(pathA).exists(), isFalse, reason: '旧背景应被删除');
  });

  test('未知扩展名回落为 .png', () async {
    final source = await fakeImage('odd.bmp');
    final stored = await service.import(source);
    expect(p.extension(stored), '.png');
    expect(await File(stored).exists(), isTrue);
  });

  test('delete 移除背景文件，对不存在/空路径静默', () async {
    final source = await fakeImage('todelete.webp');
    final stored = await service.import(source);
    expect(await File(stored).exists(), isTrue);

    await service.delete(stored);
    expect(await File(stored).exists(), isFalse);

    // 再次删除、删除 null / 空串都不应抛异常。
    await service.delete(stored);
    await service.delete(null);
    await service.delete('   ');
  });
}
