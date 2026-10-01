/// 应用级常量。
class AppConstants {
  const AppConstants._();

  static const String appName = '鸣潮声骸评分';

  /// GitHub 仓库地址（侧栏「跳转至 GitHub 仓库链接」使用）。
  static const String repositoryUrl =
      'https://github.com/HMSDido/mingchao_echo_scorer';

  /// 仓库内社区共享配置目录的名称。
  static const String sharedProfilesFolder = '共享角色系数配置文件';

  /// 社区共享配置目录的 GitHub 页面地址（角色系数配置页的提示横幅使用）。
  static final String sharedProfilesUrl =
      '$repositoryUrl/tree/main/${Uri.encodeComponent(sharedProfilesFolder)}';

  /// 与 pubspec.yaml 的 `version` 保持一致。
  static const String version = '1.0.0+1';

  /// 窄屏断点：小于该宽度时导航栏与文件栏收进抽屉。
  static const double compactWidthBreakpoint = 900;

  /// 文件栏宽度。
  static const double filePanelWidth = 252;

  /// 展开状态下的导航栏宽度。
  static const double navRailExpandedWidth = 196;

  /// 收起状态下的导航栏宽度。
  static const double navRailCollapsedWidth = 56;
}
