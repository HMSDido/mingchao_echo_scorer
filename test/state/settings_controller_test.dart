import 'package:flutter_test/flutter_test.dart';
import 'package:mingchao_echo_scorer/state/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('setBackgroundImagePath 写入偏好并通知监听者', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = SettingsController(
      await SharedPreferences.getInstance(),
    );
    var notifications = 0;
    controller.addListener(() => notifications++);

    expect(controller.backgroundImagePath, isNull);

    await controller.setBackgroundImagePath('/app/background/bg-1.png');
    expect(controller.backgroundImagePath, '/app/background/bg-1.png');
    // 控制器与底层偏好保持一致。
    expect(
      controller.repository.backgroundImagePath,
      '/app/background/bg-1.png',
    );
    expect(notifications, 1);

    // 切换路径同样触发通知。
    await controller.setBackgroundImagePath('/app/background/bg-2.jpg');
    expect(controller.backgroundImagePath, '/app/background/bg-2.jpg');
    expect(notifications, 2);

    // 清除。
    await controller.setBackgroundImagePath(null);
    expect(controller.backgroundImagePath, isNull);
    expect(controller.repository.backgroundImagePath, isNull);
    expect(notifications, 3);
  });

  test('启动时从偏好恢复已保存的背景图路径', () async {
    SharedPreferences.setMockInitialValues({
      'theme.backgroundImage': '/app/background/restored.png',
    });
    final controller = SettingsController(
      await SharedPreferences.getInstance(),
    );
    expect(controller.backgroundImagePath, '/app/background/restored.png');
  });
}
