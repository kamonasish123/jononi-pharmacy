// main.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:jononipharmacy/CompanyDetailPage.dart';
import 'package:jononipharmacy/Homepage.dart';
import 'package:jononipharmacy/MedicineAdd.dart';
import 'package:jononipharmacy/SellPage.dart';
import 'package:jononipharmacy/companylistpage.dart';
import 'CustomerDueListPage.dart';
import 'LowStockPage.dart';
import 'loginpage.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // <-- IMPORTANT (keeps your config)
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jononi Pharmacy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
      ),
      // RootDecider will listen to Firebase auth state and show the right first screen.
      home: const RootDecider(),
    );
  }
}

/// Shows a splash while Firebase restores auth, then navigates to HomePage if
/// a user exists, otherwise shows the login page.
class RootDecider extends StatelessWidget {
  const RootDecider({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // While waiting for Firebase to restore the user session, show a spinner.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: const Color(0xFF01684D),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        // If there's a signed-in user, go to HomePage (persisted session).
        if (snapshot.hasData && snapshot.data != null) {
          return const HomePage();
        }

        // Otherwise show login page.
        return loginpage();
      },
    );
  }
}
