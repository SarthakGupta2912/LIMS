import 'dart:io';
import 'dart:convert';

import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:invoice_management_system/Pages/Billing/BillingMode.dart';
import 'package:invoice_management_system/Pages/InvoiceDesign/InvoiceDesign.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:invoice_management_system/Widgets/Widgets.dart';
import '../../Functions/Functions.dart';
import '../../Modals.dart';

String? _saveLocation;

class ProductPage extends StatefulWidget {
  const ProductPage({super.key});

  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  final ScrollController _scrollController = ScrollController();
  final Set<Product> _selectedProducts = {};

  @override
  void initState() {
    super.initState();
    _loadSaveLocation();
  }

  /// Load saved location once on startup
  Future<void> _loadSaveLocation() async {
    final prefs = await SharedPreferences.getInstance();
    // prefs.clear();
    setState(() {
      _saveLocation = prefs.getString('save_location') ?? '';
    });
    _loadProductsFromFile();
    debugPrint("Saved location:- $_saveLocation");
  }

  /// Save when user chooses a location
  Future<void> _setSaveLocation(String newLocation) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('save_location', newLocation);
    setState(() {
      _saveLocation = newLocation;
    });
    // save current products into the new location
    await _saveProductsToFile();
  }

  /// Load products list from file in save location
  Future<void> _loadProductsFromFile() async {
    if (_saveLocation == null || _saveLocation!.isEmpty) return;
    try {
      final file = File("${_saveLocation!}/$dataFileName");
      if (await file.exists()) {
        final contents = await file.readAsString();
        if (contents.isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(contents);
          setState(() {
            products.clear();
            for (var item in jsonList) {
              final mapItem = Map<String, dynamic>.from(item);
              products.add(Product.fromMap(mapItem));
            }
          });
          debugPrint("Products loaded successfully!");
        }
      }
    } catch (e) {
      debugPrint("Error loading products from file: $e");
    }
  }

  /// Save current products list to file in save location
  Future<void> _saveProductsToFile() async {
    if (_saveLocation == null || _saveLocation!.isEmpty) return;
    try {
      final dir = Directory(_saveLocation!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File("${dir.path}/$dataFileName");

      // This turns each Product into a Map<String, dynamic> like you want
      final List<Map<String, dynamic>> jsonList = products
          .map((p) => {'name': p.name, 'id': p.id, 'price': p.price})
          .toList();

      final String content = jsonEncode(jsonList);
      await file.writeAsString(content);

      // Optionally print/log path and content for debugging on Windows
      debugPrint("Saving products file at: ${file.path}");
      debugPrint("Content: $content");
    } catch (e) {
      debugPrint("Error saving products to file: $e");
    }
  }

  //Choosing file path
  Future<String?>? chooseFolderToSaveProducts() async {
    // List of available drives
    final List<String> availableDrives = [
      'C:\\',
      'D:\\',
      'E:\\',
    ]; // Add other drives as needed

    // Create a list of shortcuts for the available drives
    final List<FilesystemPickerShortcut> driveShortcuts = availableDrives.map((
      drive,
    ) {
      return FilesystemPickerShortcut(
        name: drive,
        path: Directory(drive),
        icon: Icons.storage,
      );
    }).toList();

    // Open the file picker dialog
    return await FilesystemPicker.open(
      title: 'Select folder to save data',
      context: context,
      fsType: FilesystemType.folder,
      pickText: 'Select this folder',
      shortcuts: driveShortcuts,
    );
  }

  /// Deletes the saved file if it exists.
  Future<void> deleteSavedFile(String filePath) async {
    final file = File(filePath);
    try {
      if (await file.exists()) {
        await file.delete();
        debugPrint('File deleted: $filePath');
      } else {
        debugPrint('No file found at: $filePath');
      }
    } catch (e) {
      debugPrint('Error deleting file: $e');
    }
  }

  /// Popup to add / edit product
  Widget addProductPopup(
    BuildContext context, {
    Product? existingProduct,
    int? index,
  }) {
    final formKey = GlobalKey<FormState>();

    final TextEditingController nameController = TextEditingController(
      text: existingProduct?.name ?? '',
    );
    final TextEditingController idController = TextEditingController(
      text: existingProduct?.id ?? '',
    );
    final TextEditingController priceController = TextEditingController(
      text: existingProduct?.price.toString() ?? '',
    );

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(media.height * 0.02),
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.all(media.width * 0.03),
            child: Theme(
              data: Theme.of(context).copyWith(
                textSelectionTheme: const TextSelectionThemeData(
                  cursorColor: Colors.black,
                  selectionColor: Colors.black26,
                  selectionHandleColor: Colors.black,
                ),
              ),
              child: Form(
                key: formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MyTextWidget(
                      text: existingProduct == null
                          ? "Add Product"
                          : "Edit Product",
                      textType: "Heading",
                    ),
                    SizedBox(height: media.height * 0.02),

                    // Product Name
                    TextFormField(
                      controller: nameController,
                      cursorColor: Colors.black,
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'^\s+')),
                      ],
                      decoration: customInputDecoration(
                        label: "Product Name",
                        hint: "Enter product name",
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

                    // Product ID
                    TextFormField(
                      controller: idController,
                      cursorColor: Colors.black,
                      style: myInputFieldTextStyle(),
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'^\s+')),
                      ],
                      decoration: customInputDecoration(
                        label: "Product ID / Number",
                        hint: "Enter product id",
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return "Required";
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: media.height * 0.02),

                    // Price
                    TextFormField(
                      controller: priceController,
                      cursorColor: Colors.black,
                      style: myInputFieldTextStyle(),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        LengthLimitingTextInputFormatter(10),
                      ],
                      decoration: customInputDecoration(
                        label: "Price",
                        hint: "Enter product price",
                      ),
                      onChanged: (value) {
                        if (value.startsWith('.') && value.length > 1) {
                          final newValue = '0$value';
                          priceController.value = TextEditingValue(
                            text: newValue,
                            selection: TextSelection.collapsed(
                              offset: newValue.length,
                            ),
                          );
                        }
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "Required";
                        }
                        if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(value)) {
                          return "Enter a valid number";
                        }
                        return null;
                      },
                    ),

                    SizedBox(height: media.height * 0.03),
                    Button(
                      text: existingProduct == null ? "Save" : "Update",
                      color: Colors.amber,
                      textcolor: Colors.white,
                      height: media.height * 0.08,
                      width: media.width * 0.3,
                      onTap: () async {
                        if (formKey.currentState!.validate()) {
                          setState(() {
                            // 🔹 Reset selection to avoid stale state
                            _selectedProducts.clear();

                            if (existingProduct == null) {
                              products.add(
                                Product(
                                  name: nameController.text.trim(),
                                  id: idController.text.trim(),
                                  price: double.parse(priceController.text),
                                ),
                              );
                              Future.delayed(
                                const Duration(milliseconds: 300),
                                () {
                                  _scrollController.animateTo(
                                    _scrollController.position.maxScrollExtent,
                                    duration: const Duration(milliseconds: 400),
                                    curve: Curves.easeOut,
                                  );
                                },
                              );
                            } else {
                              products[index!] = Product(
                                name: nameController.text.trim(),
                                id: idController.text.trim(),
                                price: double.parse(priceController.text),
                              );
                            }
                          });
                          await _saveProductsToFile();
                          pop(context);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 🔴 Close button top-right
          Positioned(
            top: 2,
            right: 2,
            child: Tooltip(
              message: "Close",
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(color: Colors.white),
              child: GestureDetector(
                onTap: () => pop(context),
                child: CircleAvatar(
                  backgroundColor: Colors.red,
                  radius: media.width * 0.012,
                  child: Icon(
                    Icons.close,
                    color: Colors.white,
                    size: media.height * 0.025,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleSelection(Product product) {
    setState(() {
      if (_selectedProducts.contains(product)) {
        _selectedProducts.remove(product);
      } else {
        _selectedProducts.add(product);
      }
    });
  }

  void _selectAll(bool? select) {
    setState(() {
      if (select == true) {
        _selectedProducts.addAll(products);
      } else {
        _selectedProducts.clear();
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedProducts.isEmpty) return;

    DeleteConfirmationDialog.show(
      context: context,
      productName: "${_selectedProducts.length} items",
      onConfirm: () async {
        setState(() {
          products.removeWhere((p) => _selectedProducts.contains(p));
          _selectedProducts.clear();
        });
        await _saveProductsToFile();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MyAppbar(appBarTitle: 'Products', isFirstPage: true),
      drawer: Drawer(
        width: media.width * 0.4,
        backgroundColor: Colors.white,
        child: SingleChildScrollView(
          child: Column(
            children: [
              MyTextWidget(text: "Save Location:", textType: "Heading"),
              MyTextWidget(
                text: (_saveLocation != null && _saveLocation!.isNotEmpty)
                    ? _saveLocation!
                    : "Not set",
                maxLines: 2,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: media.height * 0.02),
              DrawerCard(
                onTap: () async {
                  await changeSaveLocation();
                },
                label: "Change Save Location",
                icon: Icons.save_as_rounded,
                color: const Color.fromARGB(255, 131, 248, 135),
              ),
              DrawerCard(
                onTap: () async {
                  pop(context);
                  if (products.isEmpty) {
                    showToast(
                      'Please add a product to start billing mode',
                      context,
                    );
                    return;
                  }
                  push(context, BillingMode(saveFileLocation: _saveLocation));
                },
                label: "Billing Mode",
                icon: Icons.attach_money_rounded,
                color: const Color.fromARGB(255, 227, 138, 242),
              ),
              DrawerCard(
                onTap: () async {
                  pop(context);
                  push(context, InvoiceDesign(savePath: _saveLocation));
                },
                label: "Invoice Design",
                icon: Icons.design_services_rounded,
                color: Colors.orange,
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blue,
        onPressed: () async {
          // If save location not set, ask user to pick folder first
          if (_saveLocation == null || _saveLocation!.isEmpty) {
            // Open the file picker dialog
            final String? picked = await chooseFolderToSaveProducts();

            if (picked != null && picked.isNotEmpty) {
              debugPrint('Picked location:- $picked');
              await _setSaveLocation(picked);
              // At this point save location is set
              showDialog(
                context: context,
                builder: (context) => addProductPopup(context),
              );
            } else {
              // User cancelled: don't open product popup
              return;
            }
          } else {
            // At this point save location is set
            showDialog(
              context: context,
              builder: (context) => addProductPopup(context),
            );
          }
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 🔹 Bulk Actions Header
            if (products.isNotEmpty)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.grey.shade100,
                child: Row(
                  children: [
                    Checkbox(
                      value:
                          products.isNotEmpty &&
                          _selectedProducts.length == products.length,
                      onChanged: _selectAll,
                    ),
                    Text(
                      "Select All (${_selectedProducts.length}/${products.length})",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Spacer(),
                    if (_selectedProducts.length == 1)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade50,
                            foregroundColor: Colors.blue,
                          ),
                          onPressed: () {
                            final product = _selectedProducts.first;
                            final index = products.indexOf(product);
                            showDialog(
                              context: context,
                              builder: (context) => addProductPopup(
                                context,
                                existingProduct: product,
                                index: index,
                              ),
                            );
                          },
                          icon: Icon(Icons.edit_outlined, size: 20),
                          label: Text("Edit"),
                        ),
                      ),
                    if (_selectedProducts.isNotEmpty)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade50,
                          foregroundColor: Colors.red,
                        ),
                        onPressed: _deleteSelected,
                        icon: Icon(Icons.delete_outline, size: 20),
                        label: Text("Delete (${_selectedProducts.length})"),
                      ),
                  ],
                ),
              ),

            if (products.isEmpty) ...[
              MyTextWidget(
                text: 'No product Found!\nPlease add a product to start',
                textAlign: TextAlign.center,
              ),
            ] else ...[
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.only(bottom: 20), // Prevent FAB overlap
                  controller: _scrollController,
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    final isSelected = _selectedProducts.contains(product);
                    return ListTile(
                      onTap: () => _toggleSelection(product),
                      leading: Checkbox(
                        value: isSelected,
                        onChanged: (val) => _toggleSelection(product),
                      ),
                      title: MyTextWidget(text: product.name),
                      subtitle: MyTextWidget(
                        text: "ID: ${product.id} | Price: ${product.price}",
                      ),
                      // trailing: IconButton(
                      //   tooltip: "Edit",
                      //   icon: const Icon(Icons.edit, color: Colors.blue),
                      //   onPressed: () {
                      //     showDialog(
                      //       context: context,
                      //       builder: (context) => addProductPopup(
                      //         context,
                      //         existingProduct: product,
                      //         index: index,
                      //       ),
                      //     );
                      //   },
                      // ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Helper to set save location and immediately load + save products
  Future<void> changeSaveLocation() async {
    // Open the file picker dialog
    final String? pickedRaw = await chooseFolderToSaveProducts();
    if (pickedRaw != null && pickedRaw.isNotEmpty) {
      // 🔹 Append App Directory
      final String newLocation = "$pickedRaw/invoice_management_system"
          .replaceAll('\\', '/');
      final Directory newDir = Directory(newLocation);
      if (!await newDir.exists()) {
        await newDir.create(recursive: true);
      }

      // 🔹 Create Invoices Subdirectory
      final Directory invoicesDir = Directory("$newLocation/invoices");
      if (!await invoicesDir.exists()) {
        await invoicesDir.create(recursive: true);
      }

      debugPrint('Previous location:- $_saveLocation');
      debugPrint('New location:- $newLocation');

      if (_saveLocation != null && _saveLocation!.isNotEmpty) {
        // 🔹 Migration Logic: Copy existing templates to new location
        final oldTemplatesFile = File('$_saveLocation/invoice_templates.json');
        if (await oldTemplatesFile.exists()) {
          try {
            await oldTemplatesFile.copy('$newLocation/invoice_templates.json');
            debugPrint('Migrated invoice_templates.json to new location');
          } catch (e) {
            debugPrint('Error migrating templates: $e');
          }
        }

        // Also migrate products if you want to keep data seamlessly,
        // though _saveProductsToFile called later will re-save current memory state.
        // It is safer to re-save from memory as done below via _saveProductsToFile (implicit in flow).

        // Now safe to delete old files
        await deleteSavedFile('$_saveLocation/products_data.json');
        await deleteSavedFile('$_saveLocation/invoice_templates.json');
      }

      await _setSaveLocation(newLocation);
      await _loadProductsFromFile();
    }
  }
}
