import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

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
        return linux;
      default:
        return linux;
    }
  }

  static const FirebaseOptions linux = FirebaseOptions(
    apiKey: 'AIzaSyBEQIxa-aF6aZMg3e5_JWbdLz-sjuy_B1I',
    appId: '1:678021288122:web:812643b939ce755e87b283',
    messagingSenderId: '678021288122',
    projectId: 'backupdb-39790',
    authDomain: 'backupdb-39790.firebaseapp.com',
    storageBucket: 'backupdb-39790.firebasestorage.app',
    measurementId: 'G-P96SPWL91H',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBEQIxa-aF6aZMg3e5_JWbdLz-sjuy_B1I',
    appId: '1:678021288122:web:812643b939ce755e87b283',
    messagingSenderId: '678021288122',
    projectId: 'backupdb-39790',
    authDomain: 'backupdb-39790.firebaseapp.com',
    storageBucket: 'backupdb-39790.firebasestorage.app',
    measurementId: 'G-P96SPWL91H',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBEQIxa-aF6aZMg3e5_JWbdLz-sjuy_B1I',
    appId: '1:678021288122:android:812643b939ce755e87b283',
    messagingSenderId: '678021288122',
    projectId: 'backupdb-39790',
    storageBucket: 'backupdb-39790.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBEQIxa-aF6aZMg3e5_JWbdLz-sjuy_B1I',
    appId: '1:678021288122:ios:812643b939ce755e87b283',
    messagingSenderId: '678021288122',
    projectId: 'backupdb-39790',
    storageBucket: 'backupdb-39790.firebasestorage.app',
    iosBundleId: 'com.ottoscents.smartshelf',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBEQIxa-aF6aZMg3e5_JWbdLz-sjuy_B1I',
    appId: '1:678021288122:ios:812643b939ce755e87b283',
    messagingSenderId: '678021288122',
    projectId: 'backupdb-39790',
    storageBucket: 'backupdb-39790.firebasestorage.app',
    iosBundleId: 'com.ottoscents.smartshelf',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyBEQIxa-aF6aZMg3e5_JWbdLz-sjuy_B1I',
    appId: '1:678021288122:web:812643b939ce755e87b283',
    messagingSenderId: '678021288122',
    projectId: 'backupdb-39790',
    authDomain: 'backupdb-39790.firebaseapp.com',
    storageBucket: 'backupdb-39790.firebasestorage.app',
    measurementId: 'G-P96SPWL91H',
  );
}
