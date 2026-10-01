/// 一次批量读取的结果：成功项 + 可读性错误描述。
///
/// 单个文件损坏不应导致整个列表加载失败，因此错误被收集起来交给界面提示，
/// 而不是抛异常中断。
class LoadResult<T> {
  const LoadResult({required this.items, required this.errors});

  final List<T> items;

  /// 人类可读的错误描述（含出错路径），用于 SnackBar 提示。
  final List<String> errors;

  bool get hasErrors => errors.isNotEmpty;
}
