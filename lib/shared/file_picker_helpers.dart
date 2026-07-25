import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

Future<String?> pickFolderPath({
  required BuildContext context,
  required String title,
  required String pickText,
}) async {
  return FilePicker.platform.getDirectoryPath(
    dialogTitle: title,
    lockParentWindow: true,
  );
}

Future<String?> pickImagePath({
  required BuildContext context,
  required String title,
  required String pickText,
}) async {
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: title,
    type: FileType.image,
    allowMultiple: false,
    lockParentWindow: true,
  );
  return result?.files.single.path;
}
