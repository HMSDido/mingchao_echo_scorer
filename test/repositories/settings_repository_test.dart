import 'package:flutter_test/flutter_test.dart';
import 'package:mingchao_echo_scorer/data/repositories/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsRepository settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsRepository(await SharedPreferences.getInstance());
  });

  test('默认值', () {
    expect(settings.customStorageRoot, isNull);
    expect(settings.seedColor, SettingsRepository.defaultSeedColor);
    expect(settings.themeMode, ThemeModeSetting.system);
    expect(settings.navExpanded, isTrue);
    expect(settings.lastOpenFileIds, isEmpty);
    expect(settings.backgroundImagePath, isNull);
  });

  test('存储位置读写，空串视为恢复默认', () async {
    await settings.setCustomStorageRoot(r'D:\鸣潮评分');
    expect(settings.customStorageRoot, r'D:\鸣潮评分');

    await settings.setCustomStorageRoot('   ');
    expect(settings.customStorageRoot, isNull);

    await settings.setCustomStorageRoot(r'E:\data');
    await settings.setCustomStorageRoot(null);
    expect(settings.customStorageRoot, isNull);
  });

  test('主题色读写', () async {
    await settings.setSeedColor(0xFF00FF00);
    expect(settings.seedColor, 0xFF00FF00);
  });

  test('主题模式读写，未知取值回退到跟随系统', () async {
    await settings.setThemeMode(ThemeModeSetting.dark);
    expect(settings.themeMode, ThemeModeSetting.dark);

    SharedPreferences.setMockInitialValues({'theme.mode': '不认识的值'});
    final reloaded = SettingsRepository(await SharedPreferences.getInstance());
    expect(reloaded.themeMode, ThemeModeSetting.system);
  });

  test('伸缩栏折叠状态读写', () async {
    await settings.setNavExpanded(false);
    expect(settings.navExpanded, isFalse);
  });

  test('背景图路径读写，空串/空白视为恢复默认', () async {
    await settings.setBackgroundImagePath(r'D:\app\background\bg-1.png');
    expect(settings.backgroundImagePath, r'D:\app\background\bg-1.png');

    // 换一张：路径切换。
    await settings.setBackgroundImagePath(r'D:\app\background\bg-2.jpg');
    expect(settings.backgroundImagePath, r'D:\app\background\bg-2.jpg');

    // 空白串视为清除。
    await settings.setBackgroundImagePath('   ');
    expect(settings.backgroundImagePath, isNull);

    // 显式清除。
    await settings.setBackgroundImagePath(r'D:\app\background\bg-3.webp');
    await settings.setBackgroundImagePath(null);
    expect(settings.backgroundImagePath, isNull);
  });

  test('上次打开的文件 id 列表读写', () async {
    await settings.setLastOpenFileIds(['a', 'b', 'c']);
    expect(settings.lastOpenFileIds, ['a', 'b', 'c']);

    await settings.setLastOpenFileIds([]);
    expect(settings.lastOpenFileIds, isEmpty);
  });
}
