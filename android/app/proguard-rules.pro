# Flutter 引擎与插件注册入口的保留规则。
# 插件的 Dart↔Java 调用走 MethodChannel + 生成式 Registrant，不依赖反射，
# 但引擎与嵌入层仍有少量按名称查找的类，统一保留 io.flutter 包树最稳妥。
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# 引擎的 deferred-components 路径引用了 Play Core，而本应用不使用 deferred
# components、也不带该依赖；R8 报 missing class 时按官方做法 dontwarn。
-dontwarn com.google.android.play.core.**
