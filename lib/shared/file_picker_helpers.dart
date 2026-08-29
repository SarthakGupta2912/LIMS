import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

Future<String?> pickFolderPath({
  required BuildContext context,
  required String title,
  required String pickText,
}) async {
  return FilePicker.getDirectoryPath(
    dialogTitle: title,
    windowsOptions: const WindowsOptions(lockParentWindow: true),
    linuxOptions: const LinuxOptions(lockParentWindow: true),
  );
}

Future<String?> pickImagePath({
  required BuildContext context,
  required String title,
  required String pickText,
}) async {
  final result = await FilePicker.pickFile(
    dialogTitle: title,
    type: FileType.image,
    windowsOptions: const WindowsOptions(lockParentWindow: true),
    linuxOptions: const LinuxOptions(lockParentWindow: true),
  );
  return result?.path;
}
