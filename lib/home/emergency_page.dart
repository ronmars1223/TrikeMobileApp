import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trike/home/emergency_record.dart';

class EmergencyDialog {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  // Using the provided database URL
  static final FirebaseDatabase _database = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL:
        'https://capstone-33ff5-default-rtdb.asia-southeast1.firebasedatabase.app/',
  );

  // Semaphore SMS API credentials
  static const String apiKey = "ebced0ed69d67b826ef466fda6bd533b";
  static const String senderName = "Trike";
  static const String apiUrl = "https://semaphore.co/api/v4/messages";
  static AudioRecorder _recorder = AudioRecorder();
  static Timer? _recordingTimer;
  static bool _recordingAutoStopped = false;

  // Anti-spam protection: track alert status
  static DateTime? _lastAlertTime;
  static bool _isAlertInProgress = false;
  static const int _cooldownPeriodSeconds = 120; // 2-minute cooldown

  /// Save alert timestamp to shared preferences for persistence
  static Future<void> _saveAlertTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'last_emergency_alert_time',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      print("❌ Error saving alert timestamp: $e");
    }
  }

  /// NEW FUNCTION: Save emergency alert to ride_history
  static Future<void> _saveEmergencyAlertToRideHistory(
    Position? position,
    Map<String, String> userInfo,
    Map<String, dynamic> smsResult,
  ) async {
    User? user = _auth.currentUser;

    if (user != null) {
      try {
        final now = DateTime.now();
        
        // Generate a unique emergency alert ID
        final emergencyId = '-${now.millisecondsSinceEpoch.toString()}${user.uid.substring(0, 6)}';

        // Create reference to ride_history node
        DatabaseReference rideHistoryRef = _database.ref(
          'ride_history/$emergencyId',
        );

        // Create Google Maps URL if position is available
        String? mapsUrl;
        if (position != null) {
          mapsUrl = "https://maps.google.com/maps?q=${position.latitude},${position.longitude}";
        }

        // Process contact numbers that were notified
        List<Map<String, dynamic>> notifiedContacts = [];
        List<Map<String, dynamic>> failedContacts = [];
        
        if (smsResult['messages'] != null && smsResult['messages'] is List) {
          for (var message in smsResult['messages']) {
            Map<String, dynamic> contactInfo = {
              'name': message['name'] ?? 'Unknown',
              'phone': message['phone'] ?? '',
              'isAdmin': message['isAdmin'] ?? false,
              'status': message['status'] ?? 'unknown',
              'message': message['message'] ?? '',
              'timestamp': now.millisecondsSinceEpoch,
            };
            
            if (message['status'] == 'sent') {
              notifiedContacts.add(contactInfo);
            } else {
              failedContacts.add(contactInfo);
            }
          }
        }

        // Create the emergency alert data for ride_history
        Map<String, dynamic> emergencyAlertData = {
          'uid': user.uid,
          'type': 'emergency_alert', // Distinguish from regular rides
          'status': 'completed', // Mark as completed since alert was sent
          'timestamp': ServerValue.timestamp,
          'datetime': "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}",
          
          // User information
          'user': {
            'uid': user.uid,
            'email': user.email,
            'phone': user.phoneNumber,
            'firstName': userInfo['firstName'] ?? '',
            'lastName': userInfo['lastName'] ?? '',
            'fullName': userInfo['fullName'] ?? '',
          },
          
          // Location information (if available)
          'location': position != null ? {
            'latitude': position.latitude,
            'longitude': position.longitude,
            'accuracy': position.accuracy,
            'altitude': position.altitude,
            'speed': position.speed,
            'speedAccuracy': position.speedAccuracy,
            'heading': position.heading,
            'timestamp': position.timestamp?.millisecondsSinceEpoch,
            'maps_url': mapsUrl,
          } : null,
          
          // SMS alert results with detailed contact information
          'sms_results': {
            'success': smsResult['success'],
            'sent_count': smsResult['sent'],
            'total_contacts': smsResult['total'],
            'messages': smsResult['messages'], // Keep original message details
          },
          
          // NEW: Detailed contact tracking
          'contacts_notified': {
            'successful': notifiedContacts,
            'failed': failedContacts,
            'summary': {
              'total_attempted': smsResult['total'] ?? 0,
              'successfully_notified': notifiedContacts.length,
              'failed_notifications': failedContacts.length,
              'admin_contacts_notified': notifiedContacts.where((c) => c['isAdmin'] == true).length,
              'personal_contacts_notified': notifiedContacts.where((c) => c['isAdmin'] == false).length,
            }
          },
          
          // Emergency-specific fields
          'emergency_details': {
            'alert_sent_at': ServerValue.timestamp,
            'contacts_notified': smsResult['sent'],
            'location_shared': position != null,
            'recording_started': true, // Assuming recording is always started
            'alert_method': 'enhanced_dialog', // Track which method was used
          },
          
          // Additional metadata for consistency with ride_history structure
          'created_at': ServerValue.timestamp,
          'updated_at': ServerValue.timestamp,
        };

        // Save to ride_history
        await rideHistoryRef.set(emergencyAlertData);

        print('✅ Emergency alert logged to ride_history/$emergencyId');
        print('✅ Contacts notified: ${notifiedContacts.length} successful, ${failedContacts.length} failed');
        
        // Also update user's recent activity if needed
        DatabaseReference recentActivityRef = _database.ref(
          'recent_activity/${user.uid}/$emergencyId',
        );
        
        await recentActivityRef.set({
          'type': 'emergency_alert',
          'timestamp': ServerValue.timestamp,
          'datetime': "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}",
          'status': 'completed',
          'contacts_notified': smsResult['sent'],
          'location_shared': position != null,
          'successful_contacts': notifiedContacts.map((c) => {
            'name': c['name'],
            'phone': c['phone'],
            'isAdmin': c['isAdmin'],
          }).toList(),
        });

        print('✅ Emergency alert also logged to recent_activity with contact details');
        
      } catch (e) {
        print('❌ Error saving emergency alert to ride_history: $e');
      }
    }
  }

  static Future<void> _saveEmergencyLocationToFirebase(
    Position position,
    Map<String, String> userInfo,
  ) async {
    User? user = _auth.currentUser;

    if (user != null && position != null) {
      try {
        // Generate a unique ID for this emergency
        final now = DateTime.now();
        final emergencyId = '${user.uid}_${now.millisecondsSinceEpoch}';

        // Create a reference to admin_emergency node in Realtime Database
        DatabaseReference emergencyRef = _database.ref(
          'admin_emergency/$emergencyId',
        );

        // Create the emergency data
        Map<String, dynamic> emergencyData = {
          'uid': user.uid,
          'timestamp': ServerValue.timestamp, // Firebase server timestamp
          'datetime':
              "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}",
          'location': {
            'latitude': position.latitude,
            'longitude': position.longitude,
            'accuracy': position.accuracy,
            'altitude': position.altitude,
            'speed': position.speed,
            'speedAccuracy': position.speedAccuracy,
            'heading': position.heading,
            'timestamp': position.timestamp?.millisecondsSinceEpoch,
          },
          'user': {
            'uid': user.uid,
            'email': user.email,
            'phone': user.phoneNumber,
            'firstName': userInfo['firstName'] ?? '',
            'lastName': userInfo['lastName'] ?? '',
            'fullName': userInfo['fullName'] ?? '',
          },
          'status':
              'pending', // For admin management (pending, processing, resolved)
          'notes': '', // For admin notes
        };

        // Save the emergency data to Realtime Database
        await emergencyRef.set(emergencyData);

        // Create Google Maps URL for easy access
        String mapsUrl =
            "https://maps.google.com/maps?q=${position.latitude},${position.longitude}";

        // Create a separate entry with just the essential information for quicker access
        DatabaseReference emergencyQuickRef = _database.ref(
          'admin_emergency_quick/$emergencyId',
        );
        await emergencyQuickRef.set({
          'uid': user.uid,
          'name': userInfo['fullName'] ?? 'App User',
          'latitude': position.latitude,
          'longitude': position.longitude,
          'maps_url': mapsUrl,
          'timestamp': ServerValue.timestamp,
          'datetime':
              "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}",
          'status': 'pending',
        });

        // Update user's current location with emergency flag
        DatabaseReference userLocationRef = _database.ref(
          'users/${user.uid}/current_location',
        );

        // Merge emergency data with current location
        Map<String, dynamic> userLocationUpdate = {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'timestamp': ServerValue.timestamp,
          'emergency': true,
          'emergencyId': emergencyId,
          'maps_url': mapsUrl,
          'lastUpdated':
              "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}",
        };

        // Keep any existing user data in the current_location
        if (userInfo['firstName']?.isNotEmpty ?? false) {
          userLocationUpdate['firstName'] = userInfo['firstName'];
        }

        if (userInfo['lastName']?.isNotEmpty ?? false) {
          userLocationUpdate['lastName'] = userInfo['lastName'];
        }

        // Update the user's current location in Realtime Database
        await userLocationRef.update(userLocationUpdate);

        print('✅ Emergency location saved to admin_emergency/$emergencyId');
        print(
          '✅ Quick access data saved to admin_emergency_quick/$emergencyId',
        );
      } catch (e) {
        print(
          '❌ Error saving emergency location to Firebase Realtime Database: $e',
        );
      }
    }
  }

  /// Load last alert timestamp from shared preferences
  static Future<void> _loadLastAlertTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastTimestamp = prefs.getInt('last_emergency_alert_time');

      if (lastTimestamp != null) {
        _lastAlertTime = DateTime.fromMillisecondsSinceEpoch(lastTimestamp);
        print("📅 Loaded last alert time: $_lastAlertTime");
      }
    } catch (e) {
      print("❌ Error loading alert timestamp: $e");
    }
  }

  /// Check if an alert can be sent based on cooldown period
  static Future<bool> _canSendAlert() async {
    // Load the last alert time from persistent storage
    await _loadLastAlertTime();

    // If an alert is currently in progress, prevent sending a new one
    if (_isAlertInProgress) {
      print("⚠️ Alert sending already in progress");
      return false;
    }

    // Check if we've attempted to send an alert recently
    final now = DateTime.now();
    if (_lastAlertTime != null) {
      final timeSince = now.difference(_lastAlertTime!);
      if (timeSince.inSeconds < _cooldownPeriodSeconds) {
        print("⚠️ Last alert was sent only ${timeSince.inSeconds} seconds ago");
        return false;
      }
    }

    return true;
  }

  /// NEW FUNCTION: Get admin contact information for SMS message
  static Future<String> _getAdminContactInfo() async {
    try {
      // Reference to admin_contacts in Firebase
      DatabaseReference adminContactsRef = _database.ref("admin_contacts");
      final snapshot = await adminContactsRef.get();

      if (!snapshot.exists) {
        return "";
      }

      List<String> adminNumbers = [];
      Map<dynamic, dynamic>? contactsMap = snapshot.value as Map<dynamic, dynamic>?;

      if (contactsMap != null) {
        contactsMap.forEach((contactKey, contactValue) {
          // Case 1: When contact is stored as a map
          if (contactValue is Map<dynamic, dynamic>) {
            if (contactValue.containsKey('phone')) {
              String phone = contactValue['phone'] ?? '';
              if (phone.isNotEmpty) {
                adminNumbers.add(phone);
              }
            }
          }
          // Case 2: Direct key-value pairs
          else if (contactKey is String && contactValue is String) {
            // If the value appears to be a phone number
            if (contactValue.startsWith('0') ||
                contactValue.startsWith('+') ||
                contactValue.startsWith('63')) {
              adminNumbers.add(contactValue);
            }
          }
        });
      }

      // Format the admin contact message
      if (adminNumbers.isNotEmpty) {
        if (adminNumbers.length == 1) {
          return "For emergency assistance, please contact the Barangay at ${adminNumbers[0]}.";
        } else {
          String numbersList = adminNumbers.join(", ");
          return "For emergency assistance, please contact the Barangay at: $numbersList.";
        }
      }

      return "";
    } catch (e) {
      print("Error getting admin contact info: $e");
      return "";
    }
  }

  /// Fetch emergency contacts from Firebase - UPDATED to use UID structure
  static Future<List<Map<String, dynamic>>> _fetchEmergencyContacts() async {
    List<Map<String, dynamic>> emergencyContacts = [];
    User? user = _auth.currentUser;

    if (user != null) {
      try {
        // Updated reference to use direct UID path
        DatabaseReference contactsRef = _database.ref(
          "emergency_contacts/${user.uid}",
        );
        final snapshot = await contactsRef.get();

        if (snapshot.exists) {
          Map<dynamic, dynamic>? contactsMap =
              snapshot.value as Map<dynamic, dynamic>?;

          if (contactsMap != null) {
            // Directly process contacts under the user's UID
            contactsMap.forEach((contactKey, contactValue) {
              if (contactValue is Map<dynamic, dynamic>) {
                if (contactValue.containsKey('name') &&
                    contactValue.containsKey('phone') &&
                    contactValue['status_activate'] != false) {
                  emergencyContacts.add({
                    'name': contactValue['name'] ?? 'Unknown',
                    'phone': contactValue['phone'] ?? '',
                    'isAdmin': false,
                  });
                }
              }
            });
          }
        }

        // If no contacts found using the direct path, try the old structure as fallback
        if (emergencyContacts.isEmpty) {
          final rootRef = _database.ref("emergency_contacts");
          final rootSnapshot = await rootRef.get();

          if (rootSnapshot.exists) {
            Map<dynamic, dynamic>? rootContactsMap =
                rootSnapshot.value as Map<dynamic, dynamic>?;

            if (rootContactsMap != null) {
              rootContactsMap.forEach((contactGroupKey, contactGroupValue) {
                if (contactGroupValue is Map<dynamic, dynamic>) {
                  contactGroupValue.forEach((contactKey, contactValue) {
                    if (contactValue is Map<dynamic, dynamic>) {
                      if (contactValue.containsKey('name') &&
                          contactValue.containsKey('phone') &&
                          contactValue.containsKey('uid') &&
                          contactValue['uid'] == user.uid &&
                          contactValue['status_activate'] != false) {
                        emergencyContacts.add({
                          'name': contactValue['name'] ?? 'Unknown',
                          'phone': contactValue['phone'] ?? '',
                          'isAdmin': false,
                        });
                      }
                    }
                  });
                }
              });
            }
          }
        }

        // Log found contacts for debugging
        print("Found ${emergencyContacts.length} emergency contacts");
        for (var contact in emergencyContacts) {
          print("Contact: ${contact['name']} - ${contact['phone']}");
        }
      } catch (e) {
        print("Error fetching emergency contacts: $e");
      }
    }

    return emergencyContacts;
  }

  /// NEW FUNCTION: Fetch admin contacts from Firebase
  static Future<List<Map<String, dynamic>>> _fetchAdminContacts() async {
    List<Map<String, dynamic>> adminContacts = [];

    try {
      // Reference to admin_contacts in Firebase
      DatabaseReference adminContactsRef = _database.ref("admin_contacts");
      final snapshot = await adminContactsRef.get();

      if (snapshot.exists) {
        Map<dynamic, dynamic>? contactsMap =
            snapshot.value as Map<dynamic, dynamic>?;

        if (contactsMap != null) {
          contactsMap.forEach((contactKey, contactValue) {
            // Case 1: When contact is stored as a map
            if (contactValue is Map<dynamic, dynamic>) {
              if (contactValue.containsKey('phone')) {
                adminContacts.add({
                  'name': contactValue['name'] ?? 'Admin',
                  'phone': contactValue['phone'] ?? '',
                  'isAdmin': true,
                });
              }
            }
            // Case 2: Direct key-value pairs like in the image
            else if (contactKey is String && contactValue is String) {
              // If the value appears to be a phone number
              if (contactValue.startsWith('0') ||
                  contactValue.startsWith('+') ||
                  contactValue.startsWith('63')) {
                adminContacts.add({
                  'name': 'Admin',
                  'phone': contactValue,
                  'isAdmin': true,
                });
              }
            }
          });
        }
      }

      print("Found ${adminContacts.length} admin contacts");
      for (var contact in adminContacts) {
        print("Admin Contact: ${contact['name']} - ${contact['phone']}");
      }
    } catch (e) {
      print("Error fetching admin contacts: $e");
    }

    return adminContacts;
  }

  /// Fetch user information from Firebase to get the full name
  static Future<Map<String, String>> _getUserInfo() async {
    Map<String, String> userInfo = {
      'firstName': '',
      'lastName': '',
      'fullName': '',
    };

    User? user = _auth.currentUser;

    if (user != null) {
      try {
        // First try to get the name from the user profile if available
        if (user.displayName != null && user.displayName!.isNotEmpty) {
          userInfo['fullName'] = user.displayName!;

          // Try to split display name into first and last
          List<String> nameParts = user.displayName!.split(' ');
          if (nameParts.isNotEmpty) {
            userInfo['firstName'] = nameParts[0];
            if (nameParts.length > 1) {
              userInfo['lastName'] = nameParts.sublist(1).join(' ');
            }
          }
        } else {
          // Fetch user details from Firebase Database
          DatabaseReference userRef = _database.ref("users/${user.uid}");
          final snapshot = await userRef.get();

          if (snapshot.exists) {
            Map<dynamic, dynamic>? userData =
                snapshot.value as Map<dynamic, dynamic>?;

            if (userData != null) {
              // Check for current_location node which has firstName and lastName
              if (userData.containsKey('current_location')) {
                var currentLocation = userData['current_location'];

                if (currentLocation is Map) {
                  String firstName = currentLocation['firstName'] ?? '';
                  String lastName = currentLocation['lastName'] ?? '';

                  userInfo['firstName'] = firstName;
                  userInfo['lastName'] = lastName;

                  if (firstName.isNotEmpty) {
                    userInfo['fullName'] = firstName;
                    if (lastName.isNotEmpty) {
                      userInfo['fullName'] =
                          "${userInfo['fullName']} $lastName";
                    }
                  }
                }
              }

              // If name not found in current_location, try to look elsewhere
              if (userInfo['fullName']!.isEmpty) {
                if (userData.containsKey('name')) {
                  userInfo['fullName'] = userData['name'] ?? '';
                } else if (userData.containsKey('firstName')) {
                  String firstName = userData['firstName'] ?? '';
                  String lastName = userData['lastName'] ?? '';

                  userInfo['firstName'] = firstName;
                  userInfo['lastName'] = lastName;

                  if (firstName.isNotEmpty) {
                    userInfo['fullName'] = firstName;
                    if (lastName.isNotEmpty) {
                      userInfo['fullName'] =
                          "${userInfo['fullName']} $lastName";
                    }
                  }
                }
              }
            }
          }
        }

        // If still no name, use email or phone
        if (userInfo['fullName']!.isEmpty) {
          userInfo['fullName'] = user.email ?? user.phoneNumber ?? 'App User';
        }

        // Log user info for debugging
        print("User info: ${userInfo['fullName']}");
      } catch (e) {
        print("Error fetching user info: $e");
        // Set a default name if there's an error
        userInfo['fullName'] = 'App User';
      }
    }

    return userInfo;
  }

  /// Get current location
  static Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled
      print("Location services not enabled");
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied
        print("Location permission denied");
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are permanently denied
      print("Location permission permanently denied");
      return null;
    }

    // Get the current position
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      print("Location retrieved: ${position.latitude}, ${position.longitude}");
      return position;
    } catch (e) {
      print("Error getting location: $e");
      return null;
    }
  }

  /// Send SMS alerts to emergency contacts - IMPROVED with deduplication and admin contact info
  static Future<Map<String, dynamic>> _sendSmsAlerts(
    List<Map<String, dynamic>> contacts,
    Position? position,
  ) async {
    Map<String, dynamic> result = {
      'success': false,
      'sent': 0,
      'total': 0, // Will update this after deduplication
      'messages': [],
    };

    if (contacts.isEmpty) {
      print("No contacts available to send alerts");
      return result;
    }

    // Create a Set to track unique phone numbers to prevent duplicate messages
    final Set<String> processedPhones = {};

    // Filter for unique contacts only to prevent spamming
    final uniqueContacts =
        contacts.where((contact) {
          final phone = contact['phone'].toString();
          final formattedPhone = _formatPhoneNumber(phone);

          if (formattedPhone.isEmpty) {
            print("❌ Invalid phone format for ${contact['name']}: $phone");
            return false;
          }

          // If this phone number already exists in our set, skip it
          if (processedPhones.contains(formattedPhone)) {
            print(
              "⚠️ Skipping duplicate contact: ${contact['name']} ($formattedPhone)",
            );
            return false;
          }

          // Otherwise add it to our set and keep it
          processedPhones.add(formattedPhone);
          return true;
        }).toList();

    // Update total with deduplicated count
    result['total'] = uniqueContacts.length;

    if (uniqueContacts.isEmpty) {
      print("No valid contacts after deduplication");
      return result;
    }

    // Get the user's full name and info
    Map<String, String> userInfo = await _getUserInfo();
    String fullName = userInfo['fullName'] ?? 'App User';

    // Generate the Google Maps URL with the current location if available
    String locationText = 'Location unavailable';
    if (position != null) {
      String mapsUrl =
          "https://maps.google.com/maps?q=${position.latitude},${position.longitude}";
      locationText = "Location: $mapsUrl";
    }

    // Get admin contact numbers for emergency message
    String adminContactInfo = await _getAdminContactInfo();

    // Create the message with the user's full name and admin contact info
    String message = "$fullName needs immediate help! $locationText";
    if (adminContactInfo.isNotEmpty) {
      message += " $adminContactInfo";
    }
    
    print("Message content: $message");

    // Process each unique contact individually
    int successCount = 0;

    for (var contact in uniqueContacts) {
      String phone = contact['phone'];
      String contactName = contact['name'];
      bool isAdmin = contact['isAdmin'] ?? false;

      try {
        // Format the phone number
        String formattedPhone = _formatPhoneNumber(phone);

        if (formattedPhone.isEmpty) {
          print("Invalid phone format for $contactName: $phone");
          result['messages'].add({
            'name': contactName,
            'phone': phone,
            'status': 'error',
            'message': 'Invalid phone number format',
            'isAdmin': isAdmin,
          });
          continue;
        }

        // Send individual SMS for better reliability
        var response = await _sendSingleSms(formattedPhone, message);

        if (response['success']) {
          successCount++;
          result['messages'].add({
            'name': contactName,
            'phone': formattedPhone,
            'status': 'sent',
            'message': 'Message sent successfully',
            'isAdmin': isAdmin,
          });
        } else {
          result['messages'].add({
            'name': contactName,
            'phone': formattedPhone,
            'status': 'error',
            'message': response['error'] ?? 'Failed to send message',
            'isAdmin': isAdmin,
          });
        }
      } catch (e) {
        print("Error sending SMS to $contactName: $e");
        result['messages'].add({
          'name': contactName,
          'phone': phone,
          'status': 'error',
          'message': e.toString(),
          'isAdmin': isAdmin,
        });
      }
    }

    result['sent'] = successCount;
    result['success'] = successCount > 0;

    return result;
  }

  /// Format phone number according to Semaphore guidelines
  static String _formatPhoneNumber(String phone) {
    // Strip any non-numeric characters
    phone = phone.replaceAll(RegExp(r'\D'), '');

    // If empty after stripping, return empty
    if (phone.isEmpty) {
      return '';
    }

    // Check if it's a Philippine number and format correctly
    if (phone.startsWith("0")) {
      // Convert 09XXXXXXXXX to 639XXXXXXXXX (without + symbol)
      phone = "63" + phone.substring(1);
    } else if (phone.startsWith("9") && phone.length == 10) {
      // Convert 9XXXXXXXXX to 639XXXXXXXXX
      phone = "63" + phone;
    } else if (phone.startsWith("+63")) {
      // Remove the + symbol
      phone = phone.substring(1);
    } else if (phone.startsWith("63") && phone.length >= 12) {
      // Already in correct format
    } else if (phone.length == 11 && phone.startsWith("0")) {
      // Convert 09XXXXXXXXX to 639XXXXXXXXX
      phone = "63" + phone.substring(1);
    } else {
      // If it doesn't match any known pattern, try to make a best guess
      if (phone.length == 10) {
        // Assume it's a 10-digit number missing the country code
        phone = "63" + phone;
      } else if (phone.length == 11 && !phone.startsWith("0")) {
        // Some other 11-digit format
        phone = "63" + phone.substring(phone.length - 10);
      }
    }

    // Validate that it seems like a proper phone number format
    if ((phone.startsWith("63") && phone.length >= 12) ||
        (!phone.startsWith("63") && phone.length >= 10)) {
      return phone;
    }

    return '';
  }

  /// Send a single SMS using the Semaphore API
  static Future<Map<String, dynamic>> _sendSingleSms(
    String phoneNumber,
    String message,
  ) async {
    try {
      print("Sending SMS to: $phoneNumber");

      // Create form data
      var formData = {
        'apikey': apiKey,
        'number': phoneNumber,
        'message': message,
        'sendername': senderName,
      };

      // Make the HTTP POST request
      final response = await http.post(Uri.parse(apiUrl), body: formData);

      print("SMS API Response code: ${response.statusCode}");
      print("SMS API Response body: ${response.body}");

      if (response.statusCode == 200) {
        try {
          List<dynamic> responseList = json.decode(response.body);
          if (responseList.isNotEmpty) {
            var msgResponse = responseList[0];
            if (msgResponse is Map<String, dynamic>) {
              String status = msgResponse['status'] ?? 'unknown';
              if (status.toLowerCase() == 'pending' ||
                  status.toLowerCase() == 'success') {
                return {'success': true};
              } else {
                return {
                  'success': false,
                  'error': 'Message status: ${status.toLowerCase()}',
                };
              }
            }
          }
          // If we can't determine status from response, assume success
          return {'success': true};
        } catch (e) {
          print("Error parsing API response: $e");
          // If response is 200 but parsing fails, assume success
          return {'success': true};
        }
      } else {
        return {
          'success': false,
          'error': 'HTTP Error ${response.statusCode}: ${response.body}',
        };
      }
    } catch (e) {
      print("Exception sending SMS: $e");
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Shows an emergency alert dialog with confirmation options
  /// Returns true if the alert was sent, false otherwise
  static Future<bool> show(BuildContext context) async {
    // Check if it's allowed to send an alert (cooldown period)
    bool canSend = await _canSendAlert();
    if (!canSend) {
      // Show cooldown message to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.timer, color: Colors.white),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Please wait before sending another emergency alert',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
      return false;
    }

    bool alertSent = false;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
              SizedBox(width: 10),
              Text(
                'Emergency Alert',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade700,
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to send an emergency alert?',
            style: TextStyle(fontSize: 16),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              child: Text(
                'Send Alert',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                // Set alert in progress flag
                _isAlertInProgress = true;

                try {
                  // Show loading dialog
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (BuildContext context) {
                      return Dialog(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(width: 20),
                              Text("Sending alerts..."),
                            ],
                          ),
                        ),
                      );
                    },
                  );

                  // Get user info first
                  final userInfo = await _getUserInfo();

                  // Get emergency contacts and admin contacts
                  final userContacts = await _fetchEmergencyContacts();
                  final adminContacts = await _fetchAdminContacts();

                  // Combine both lists
                  final allContacts = [...userContacts, ...adminContacts];

                  // Get current location
                  final position = await _getCurrentLocation();

                  // Send SMS alerts to all contacts
                  final result = await _sendSmsAlerts(allContacts, position);

                  // IMPORTANT: Save emergency location to Firebase first
                  if (position != null) {
                    await _saveEmergencyLocationToFirebase(position, userInfo);
                  }

                  // NEW: Save emergency alert to ride_history
                  await _saveEmergencyAlertToRideHistory(position, userInfo, result);

                  // Close loading dialog
                  Navigator.of(context).pop();

                  // Close the dialog
                  Navigator.of(context).pop();

                  // Set flag and show confirmation
                  alertSent = result['success'];

                  // If sent successfully, save the timestamp
                  if (alertSent) {
                    _lastAlertTime = DateTime.now();
                    await _saveAlertTimestamp();
                  }

                  // Show confirmation or error snackbar based on success
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(
                            result['success']
                                ? Icons.check_circle
                                : Icons.warning,
                            color: Colors.white,
                          ),
                          SizedBox(width: 10),
                          Text(
                            result['success']
                                ? 'Emergency Alert Sent to ${result['sent']} of ${result['total']} contacts'
                                : 'Error sending alerts. Please try again.',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      backgroundColor:
                          result['success']
                              ? Colors.green.shade700
                              : Colors.orange.shade700,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      margin: EdgeInsets.all(10),
                      duration: Duration(seconds: 3),
                    ),
                  );
                } finally {
                  // Always release the lock
                  _isAlertInProgress = false;
                }
              },
            ),
          ],
          actionsPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        );
      },
    );

    // Return whether the alert was sent or not
    return alertSent;
  }

  /// Shows an enhanced emergency alert dialog with SMS functionality and anti-spam protection
  /// Returns true if the alert was sent, false otherwise
  static Future<bool> showEnhanced(BuildContext context) async {
    // Check if it's allowed to send an alert (cooldown period)
    bool canSend = await _canSendAlert();
    if (!canSend) {
      // Calculate remaining cooldown time
      int remainingSeconds = _cooldownPeriodSeconds;
      if (_lastAlertTime != null) {
        remainingSeconds =
            _cooldownPeriodSeconds -
            DateTime.now().difference(_lastAlertTime!).inSeconds;
        if (remainingSeconds < 0) remainingSeconds = 0;
      }

      // Format remaining time
      String timeText =
          remainingSeconds > 60
              ? "${(remainingSeconds / 60).ceil()} minutes"
              : "$remainingSeconds seconds";

      // Show cooldown message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.timer, color: Colors.white),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Please wait $timeText before sending another alert',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
      return false;
    }

    bool alertSent = false;
    bool isLoading = false;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.red.shade700,
                            size: 24,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Emergency Alert',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 20),

                    // Main content
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade100),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.my_location,
                                size: 18,
                                color: Colors.red.shade700,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Your current location will be shared',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.red.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.notifications_active,
                                size: 18,
                                color: Colors.red.shade700,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Emergency and admin contacts will be notified via SMS with Barangay contact info',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.red.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 24),

                    // Buttons
                    isLoading
                        ? Center(
                          child: Column(
                            children: [
                              CircularProgressIndicator(
                                color: Colors.red.shade700,
                              ),
                              SizedBox(height: 12),
                              Text(
                                "Sending emergency alerts...",
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        )
                        : Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: Colors.grey.shade400),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade700,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  elevation: 2,
                                ),
                                child: Text(
                                  'Send Alert',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),

                                // Enhanced onPressed method with ride_history logging
                                onPressed: () async {
                                  setState(() {
                                    isLoading = true;
                                  });

                                  _isAlertInProgress = true;
                                  String? recordedPath;

                                  try {
                                    // Initialize the recording helper with the public directory
                                    await AudioRecorderHelper.initializePublicDirectory();

                                    // Start recording with MP3 format and a custom emergency-related filename with date/time
                                    final now = DateTime.now();
                                    final dateStr =
                                        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
                                    final timeStr =
                                        "${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}";

                                    recordedPath =
                                        await AudioRecorderHelper.startRecording(
                                          durationMinutes: 3,
                                          completeFullDuration:
                                              true, // Ensure it runs for the full 3 minutes
                                          format:
                                              AudioFormat.mp3, // Use MP3 format
                                          customFilename:
                                              'emergency_${dateStr}_${timeStr}', // Custom filename with date and time
                                        );

                                    // Get user info first
                                    final userInfo = await _getUserInfo();

                                    // Get user's current location
                                    final position =
                                        await _getCurrentLocation();

                                    // IMPORTANT: First save emergency location to the Realtime Database
                                    // This ensures the location is recorded even if sending SMS fails
                                    if (position != null) {
                                      await _saveEmergencyLocationToFirebase(
                                        position,
                                        userInfo,
                                      );
                                    } else {
                                      // If we couldn't get the location, log the error but continue with the alert
                                      print(
                                        '⚠️ Warning: Unable to get current location for emergency alert',
                                      );
                                    }

                                    // Fetch all contacts
                                    final userContacts =
                                        await _fetchEmergencyContacts();
                                    final adminContacts =
                                        await _fetchAdminContacts();
                                    final allContacts = [
                                      ...userContacts,
                                      ...adminContacts,
                                    ];

                                    // Send SMS alerts
                                    final result = await _sendSmsAlerts(
                                      allContacts,
                                      position,
                                    );

                                    // NEW: Save emergency alert to ride_history
                                    await _saveEmergencyAlertToRideHistory(
                                      position,
                                      userInfo,
                                      result,
                                    );

                                    alertSent = result['success'];
                                    if (alertSent) {
                                      _lastAlertTime = DateTime.now();
                                      await _saveAlertTimestamp();
                                    }

                                    // Dismiss the dialog
                                    Navigator.of(context).pop();

                                    // Show confirmation message
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Row(
                                          children: [
                                            Icon(
                                              result['success']
                                                  ? Icons.check_circle
                                                  : Icons.warning,
                                              color: Colors.white,
                                            ),
                                            SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    result['success']
                                                        ? 'Emergency Alert Sent'
                                                        : 'Alert Sent with Errors',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  Text(
                                                    '${result['sent']} of ${result['total']} contacts notified with Barangay info',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  // This additional message confirms the location was saved
                                                  Text(
                                                    position != null
                                                        ? 'Your location was shared with emergency services'
                                                        : 'Unable to share your location',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  // NEW: Confirm ride_history logging
                                                  Text(
                                                    'Emergency alert logged to history',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  FutureBuilder<bool>(
                                                    future:
                                                        AudioRecorderHelper.isRecording(),
                                                    builder: (
                                                      context,
                                                      snapshot,
                                                    ) {
                                                      if (snapshot.data ==
                                                          true) {
                                                        return Text(
                                                          'Recording in progress (saved to Recordings folder)',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                          ),
                                                        );
                                                      }
                                                      return SizedBox.shrink();
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        backgroundColor:
                                            result['success']
                                                ? Colors.green.shade700
                                                : Colors.orange.shade700,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        margin: EdgeInsets.all(10),
                                        duration: Duration(seconds: 4),
                                      ),
                                    );
                                  } catch (e) {
                                    print('Error during alert: $e');

                                    // Close the dialog even if there was an error
                                    Navigator.of(context).pop();

                                    // Show error message
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Row(
                                          children: [
                                            Icon(
                                              Icons.error,
                                              color: Colors.white,
                                            ),
                                            SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                'Error sending emergency alert: ${e.toString()}',
                                              ),
                                            ),
                                          ],
                                        ),
                                        backgroundColor: Colors.red.shade700,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );

                                    // Stop recording only if there was an error with the alert process
                                    if (await AudioRecorderHelper.isRecording()) {
                                      await AudioRecorderHelper.forceStopRecording();
                                    }
                                  } finally {
                                    // Notice we're NOT stopping the recording here, letting it complete the full 3 minutes
                                    _isAlertInProgress = false;

                                    // Reset loading state if the dialog is still showing
                                    setState(() {
                                      isLoading = false;
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    return alertSent;
  }
}