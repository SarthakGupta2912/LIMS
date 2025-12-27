import 'dart:convert';
import 'dart:io';

import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:flutter/material.dart';

import '../../Functions/Functions.dart';
import '../../Widgets/Widgets.dart';

class InvoiceTemplate {
  String id;
  String organizationName;
  String? logoPath;
  String? currency;
  bool isSelected;

  InvoiceTemplate({
    required this.id,
    required this.organizationName,
    this.logoPath,
    this.currency,
    this.isSelected = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'organizationName': organizationName,
      'logoPath': logoPath,
      'currency': currency,
      'isSelected': isSelected,
    };
  }

  factory InvoiceTemplate.fromMap(Map<String, dynamic> map) {
    return InvoiceTemplate(
      id: map['id'],
      organizationName: map['organizationName'],
      logoPath: map['logoPath'],
      currency: map['currency'],
      isSelected: map['isSelected'] ?? false,
    );
  }
}

class InvoiceDesign extends StatefulWidget {
  final String? savePath;
  const InvoiceDesign({super.key, this.savePath});

  @override
  State<InvoiceDesign> createState() => _InvoiceDesignState();
}

class _InvoiceDesignState extends State<InvoiceDesign> {
  List<InvoiceTemplate> templates = [];
  final int templateLimit = 5;
  Size media = Size(0, 0);

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    if (widget.savePath == null || widget.savePath!.isEmpty) return;
    final file = File('${widget.savePath}/invoice_templates.json');
    if (await file.exists()) {
      try {
        final String templatesJson = await file.readAsString();
        final List<dynamic> decoded = jsonDecode(templatesJson);
        setState(() {
          templates = decoded.map((e) => InvoiceTemplate.fromMap(e)).toList();
          // If only 1 template, select it by default
          if (templates.length == 1 && !templates[0].isSelected) {
            templates[0].isSelected = true;
            _saveTemplates();
          }
        });
      } catch (e) {
        debugPrint("Error loading templates: $e");
      }
    }
  }

  Future<void> _saveTemplates() async {
    if (widget.savePath == null || widget.savePath!.isEmpty) return;
    final file = File('${widget.savePath}/invoice_templates.json');
    try {
      final String encoded = jsonEncode(
        templates.map((e) => e.toMap()).toList(),
      );
      await file.writeAsString(encoded);
    } catch (e) {
      debugPrint("Error saving templates: $e");
    }
  }

  Future<void> _pickLogo(TextEditingController controller) async {
    final List<String> availableDrives = ['C:\\', 'D:\\', 'E:\\'];
    final List<FilesystemPickerShortcut> driveShortcuts = availableDrives.map((
      drive,
    ) {
      return FilesystemPickerShortcut(
        name: drive,
        path: Directory(drive),
        icon: Icons.storage,
      );
    }).toList();

    String? path = await FilesystemPicker.open(
      title: 'Select Logo',
      context: context,
      fsType: FilesystemType.file,
      pickText: 'Select this image',
      folderIconColor: Colors.teal,
      allowedExtensions: ['.png', '.jpg', '.jpeg'],
      shortcuts: driveShortcuts,
    );

    if (path != null) {
      setState(() {
        controller.text = path;
      });
    }
  }

  void _selectTemplate(int index) {
    setState(() {
      for (var i = 0; i < templates.length; i++) {
        templates[i].isSelected = i == index;
      }
    });
    _saveTemplates();
  }

  void _showTemplateDialog({InvoiceTemplate? existingTemplate, int? index}) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(
      text: existingTemplate?.organizationName ?? '',
    );
    final logoController = TextEditingController(
      text: existingTemplate?.logoPath ?? '',
    );
    final currencyController = TextEditingController(
      text: existingTemplate?.currency ?? '',
    );

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(media.height * 0.02),
          ),
          child: Container(
            width: media.width * 0.5,
            padding: EdgeInsets.all(media.width * 0.03),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MyTextWidget(
                    text: existingTemplate == null
                        ? "Create Template"
                        : "Edit Template",
                    textType: "Heading",
                  ),
                  SizedBox(height: media.height * 0.03),
                  TextFormField(
                    controller: nameController,
                    decoration: customInputDecoration(
                      label: "Organization Name",
                      hint: "Enter your organization name",
                    ),
                    style: myInputFieldTextStyle(),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return "Required";
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: media.height * 0.02),
                  TextFormField(
                    controller: currencyController,
                    decoration: customInputDecoration(
                      label: "Currency Symbol/Text",
                      hint: "e.g. \$, USD, ₹",
                    ),
                    maxLength: 10,
                    style: myInputFieldTextStyle(),
                    validator: (value) {
                      if (value != null && value.length > 10) {
                        return "Max 10 characters";
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: media.height * 0.02),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: logoController,
                          readOnly: true,
                          decoration: customInputDecoration(
                            label: "Logo Path",
                            hint: "Select a logo image",
                          ),
                          style: myInputFieldTextStyle(),
                        ),
                      ),
                      SizedBox(width: 10),
                      IconButton(
                        onPressed: () => _pickLogo(logoController),
                        icon: Icon(Icons.image, size: 30, color: Colors.blue),
                        tooltip: "Pick Image",
                      ),
                    ],
                  ),
                  SizedBox(height: media.height * 0.03),
                  Button(
                    text: "Save",
                    color: Colors.amber,
                    textcolor: Colors.white,
                    height: media.height * 0.07,
                    width: media.width * 0.2,
                    onTap: () async {
                      if (formKey.currentState!.validate()) {
                        final newTemplate = InvoiceTemplate(
                          id:
                              existingTemplate?.id ??
                              DateTime.now().millisecondsSinceEpoch.toString(),
                          organizationName: nameController.text.trim(),
                          logoPath: logoController.text.trim().isEmpty
                              ? null
                              : logoController.text.trim(),
                          currency: currencyController.text.trim().isEmpty
                              ? null
                              : currencyController.text.trim(),
                          isSelected: existingTemplate?.isSelected ?? false,
                        );

                        setState(() {
                          if (existingTemplate == null) {
                            templates.add(newTemplate);
                            // Auto-select if it's the first one
                            if (templates.length == 1) {
                              templates[0].isSelected = true;
                            }
                          } else {
                            templates[index!] = newTemplate;
                          }
                        });
                        await _saveTemplates();
                        pop(context);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    media = MediaQuery.of(context).size;
    return Scaffold(
      appBar: MyAppbar(appBarTitle: 'Invoice Design', isFirstPage: false),
      body: Padding(
        padding: EdgeInsets.all(media.width * 0.02),
        child: Column(
          children: [
            if (templates.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.design_services_outlined,
                        size: media.height * 0.1,
                        color: Colors.grey,
                      ),
                      SizedBox(height: media.height * 0.02),
                      MyTextWidget(
                        text: "No templates created yet.",
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: media.height * 0.02),
                      IconButton(
                        style: IconButton.styleFrom(
                          splashFactory: NoSplash.splashFactory,
                          highlightColor: Colors.transparent,
                          hoverColor: Colors.transparent,
                        ),
                        tooltip: 'Add',
                        icon: const Icon(Icons.add),
                        onPressed: () {
                          _showTemplateDialog();
                        },
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: templates.length,
                  itemBuilder: (context, index) {
                    final template = templates[index];
                    return Card(
                      elevation: 4,
                      margin: EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: template.isSelected
                            ? BorderSide(color: Colors.green, width: 2)
                            : BorderSide.none,
                      ),
                      child: ListTile(
                        onTap: () => _selectTemplate(index),
                        leading:
                            template.logoPath != null &&
                                File(template.logoPath!).existsSync()
                            ? Image.file(
                                File(template.logoPath!),
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                              )
                            : Icon(Icons.business, size: 40),
                        title: Row(
                          children: [
                            MyTextWidget(text: template.organizationName),
                            if (template.isSelected) ...[
                              SizedBox(width: 10),
                              Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 20,
                              ),
                            ],
                          ],
                        ),
                        subtitle: MyTextWidget(
                          text: "Template ID: ${template.id}",
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit, color: Colors.blue),
                              onPressed: () {
                                _showTemplateDialog(
                                  existingTemplate: template,
                                  index: index,
                                );
                              },
                            ),
                            IconButton(
                              icon: Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                DeleteConfirmationDialog.show(
                                  context: context,
                                  productName: template.organizationName,
                                  onConfirm: () async {
                                    setState(() {
                                      templates.removeAt(index);
                                    });
                                    await _saveTemplates();
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      floatingActionButton:
          templates.isNotEmpty && templates.length < templateLimit
          ? FloatingActionButton(
              onPressed: () {
                _showTemplateDialog();
              },
              backgroundColor: Colors.blue,
              child: Icon(Icons.add, color: Colors.white),
              tooltip: "Add Template",
            )
          : null,
    );
  }
}
