import 'package:flutter/material.dart';
import 'package:invoice_management_system/Functions/Functions.dart';
import 'package:invoice_management_system/Pages/Common/ProductPage.dart';
import 'package:invoice_management_system/Widgets/Widgets.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    route();
  }

  route() async {
    await Future.delayed(const Duration(seconds: 3));
    pushAndRemovePreviousRoutes(context, ProductPage());
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(child: MyTextWidget(text: 'Sarthak')),
    );
  }
}
