import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAHByOKX0GXyI8J1cMwG3tUsaKtLU-6dBQ',
    appId: '1:118396784932:web:d2694be607a7bc80b623b1',
    messagingSenderId: '118396784932',
    projectId: 'capstone-33ff5',
    authDomain: 'capstone-33ff5.firebaseapp.com',
    storageBucket: 'capstone-33ff5.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDQ_cQL_sPHvOJD7ChzwKO2TQNsD2YKQGY',
    appId: '1:118396784932:android:bb0738de58e64ec8b623b1',
    messagingSenderId: '118396784932',
    projectId: 'capstone-33ff5',
    storageBucket: 'capstone-33ff5.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAEpGwqi9_rvczSKWDV_xIB7ymDpcY6ilY',
    appId: '1:118396784932:ios:a705ba033801de29b623b1',
    messagingSenderId: '118396784932',
    projectId: 'capstone-33ff5',
    storageBucket: 'capstone-33ff5.firebasestorage.app',
    iosBundleId: 'com.example.capstoneProject',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAEpGwqi9_rvczSKWDV_xIB7ymDpcY6ilY',
    appId: '1:118396784932:ios:a705ba033801de29b623b1',
    messagingSenderId: '118396784932',
    projectId: 'capstone-33ff5',
    storageBucket: 'capstone-33ff5.firebasestorage.app',
    iosBundleId: 'com.example.capstoneProject',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAHByOKX0GXyI8J1cMwG3tUsaKtLU-6dBQ',
    appId: '1:118396784932:web:edf7e60491f96030b623b1',
    messagingSenderId: '118396784932',
    projectId: 'capstone-33ff5',
    authDomain: 'capstone-33ff5.firebaseapp.com',
    storageBucket: 'capstone-33ff5.firebasestorage.app',
  );
}
