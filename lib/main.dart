import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'Authentication/login_screen.dart';
import 'home/user_homepage.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // Use correct options
  );

  // Initialize Google Maps with Hybrid Composition
  final GoogleMapsFlutterPlatform mapsImplementation =
      GoogleMapsFlutterPlatform.instance;
  if (mapsImplementation is GoogleMapsFlutterAndroid) {
    mapsImplementation.useAndroidViewSurface = true;
  }

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Firebase Auth',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: AuthChecker(), // Auth state checker
      routes: {
        '/login': (context) => LoginPage(),
        '/home': (context) => HomePage(),
      },
    );
  }
}

class AuthChecker extends StatelessWidget {
  final DatabaseReference _database =
      FirebaseDatabase.instanceFor(
        app: FirebaseDatabase.instance.app,
        databaseURL:
            "https://capstone-33ff5-default-rtdb.asia-southeast1.firebasedatabase.app/",
      ).ref();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          return FutureBuilder<DataSnapshot>(
            future: _database.child("users/${snapshot.data!.uid}").get(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (userSnapshot.hasData && userSnapshot.data!.value != null) {
                var userData =
                    userSnapshot.data!.value as Map<dynamic, dynamic>;
                String userType = userData["type"] ?? "user";

                if (userType == "admin") {
                  return _showAdminAccessDenied(context);
                } else {
                  return HomePage();
                }
              }
              return LoginPage();
            },
          );
        } else {
          return LoginPage();
        }
      },
    );
  }

  Widget _showAdminAccessDenied(BuildContext context) {
    return Scaffold(
      body: Center(
        child: AlertDialog(
          title: Text("Access Denied"),
          content: Text("Admin access is not available on this platform."),
          actions: [
            TextButton(
              onPressed:
                  () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => LoginPage()),
                  ),
              child: Text("OK"),
            ),
          ],
        ),
      ),
    );
  }
}
