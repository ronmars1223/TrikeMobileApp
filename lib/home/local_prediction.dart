import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Model for location predictions
class LocalPrediction {
  final String placeId;
  final String mainText;
  final String secondaryText;
  final String description;
  final LatLng coordinates;
  final bool isRecent;
  final bool isOnlineResult;
  final bool isSearchMore;
  final Map<String, dynamic>? recent_history;

  LocalPrediction({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
    required this.description,
    required this.coordinates,
    this.isRecent = false,
    this.isOnlineResult = false,
    this.isSearchMore = false,
    this.recent_history,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is LocalPrediction &&
        other.placeId == placeId &&
        other.mainText == mainText &&
        other.secondaryText == secondaryText &&
        other.coordinates.latitude == coordinates.latitude &&
        other.coordinates.longitude == coordinates.longitude;
  }

  @override
  int get hashCode =>
      placeId.hashCode ^ mainText.hashCode ^ coordinates.hashCode;
}

// Saved Location Model
class SavedLocationModel {
  final String placeId;
  final String address;
  final double latitude;
  final double longitude;
  final String name;
  final bool isFavorite;
  final String type;
  final int timestamp;

  SavedLocationModel({
    required this.placeId,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.name,
    this.isFavorite = false,
    this.type = 'other',
    required this.timestamp,
  });

  // Convert Firebase snapshot to SavedLocationModel
  factory SavedLocationModel.fromFirebaseSnapshot(
    MapEntry<String, dynamic> entry,
  ) {
    final value = Map<String, dynamic>.from(entry.value);
    return SavedLocationModel(
      placeId: entry.key,
      address: value['address']?.toString() ?? '',
      latitude: value['latitude']?.toDouble() ?? 0.0,
      longitude: value['longitude']?.toDouble() ?? 0.0,
      name: value['name']?.toString() ?? 'Unnamed Location',
      isFavorite: value['isFavorite'] ?? false,
      type: value['type']?.toString() ?? 'other',
      timestamp: value['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  // Convert to LatLng for map usage
  LatLng toLatLng() => LatLng(latitude, longitude);

  // Convert to LocalPrediction for compatibility
  LocalPrediction toLocalPrediction() {
    return LocalPrediction(
      placeId: placeId,
      mainText: name,
      secondaryText: address,
      description: "$name, $address",
      coordinates: toLatLng(),
      isRecent: false,
      recent_history: {
        "source": "saved_location",
        "type": type,
        "latitude": latitude,
        "longitude": longitude,
        "address": address,
        "name": name,
        "timestamp": timestamp,
        "isFavorite": isFavorite,
      },
    );
  }
}

// Saved Locations Service
class SavedLocationsService {
  // Fetch saved locations for current user
  static Future<List<SavedLocationModel>> getSavedLocations() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return [];

    try {
      final db = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL:
            'https://capstone-33ff5-default-rtdb.asia-southeast1.firebasedatabase.app/',
      );

      final savedRef = db.ref('saved_locations/${currentUser.uid}');
      final snapshot = await savedRef.get().timeout(Duration(seconds: 5));

      if (!snapshot.exists || snapshot.value == null) return [];

      final data = Map<String, dynamic>.from(snapshot.value as Map);

      return data.entries
          .map((entry) => SavedLocationModel.fromFirebaseSnapshot(entry))
          .toList();
    } catch (e) {
      print("❌ Failed to fetch saved locations: $e");
      return [];
    }
  }

  // Add a new saved location
  static Future<bool> addSavedLocation({
    required String name,
    required String address,
    required double latitude,
    required double longitude,
    String type = 'other',
    bool isFavorite = false,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;

    try {
      final db = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL:
            'https://capstone-33ff5-default-rtdb.asia-southeast1.firebasedatabase.app/',
      );

      final savedRef = db.ref('saved_locations/${currentUser.uid}');

      // Create a new child with a unique key
      final newLocationRef = savedRef.push();

      await newLocationRef.set({
        'name': name,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'type': type,
        'isFavorite': isFavorite,
        'timestamp': ServerValue.timestamp,
      });

      return true;
    } catch (e) {
      print("❌ Failed to add saved location: $e");
      return false;
    }
  }

  // Update an existing saved location
  static Future<bool> updateSavedLocation({
    required String placeId,
    String? name,
    String? address,
    double? latitude,
    double? longitude,
    String? type,
    bool? isFavorite,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;

    try {
      final db = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL:
            'https://capstone-33ff5-default-rtdb.asia-southeast1.firebasedatabase.app/',
      );

      final locationRef = db.ref('saved_locations/${currentUser.uid}/$placeId');

      // Prepare update map with only non-null values
      final updateData = <String, dynamic>{};
      if (name != null) updateData['name'] = name;
      if (address != null) updateData['address'] = address;
      if (latitude != null) updateData['latitude'] = latitude;
      if (longitude != null) updateData['longitude'] = longitude;
      if (type != null) updateData['type'] = type;
      if (isFavorite != null) updateData['isFavorite'] = isFavorite;

      await locationRef.update(updateData);
      return true;
    } catch (e) {
      print("❌ Failed to update saved location: $e");
      return false;
    }
  }

  // Delete a saved location
  static Future<bool> deleteSavedLocation(String placeId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;

    try {
      final db = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL:
            'https://capstone-33ff5-default-rtdb.asia-southeast1.firebasedatabase.app/',
      );

      final locationRef = db.ref('saved_locations/${currentUser.uid}/$placeId');
      await locationRef.remove();
      return true;
    } catch (e) {
      print("❌ Failed to delete saved location: $e");
      return false;
    }
  }

  // Get favorite saved locations
  static Future<List<SavedLocationModel>> getFavoriteSavedLocations() async {
    final savedLocations = await getSavedLocations();
    return savedLocations.where((location) => location.isFavorite).toList();
  }
}

// Service for managing location suggestions
class LocationSuggestionService {
  // Default coordinates for Davao City
  static const LatLng defaultCoordinates = LatLng(7.0707, 125.6087);

  // Popular places in Davao Region only
  static List<LocalPrediction> getPopularPlaces() {
    return [
      LocalPrediction(
        placeId: "1",
        mainText: "SM Lanang Premier",
        secondaryText: "JP Laurel Ave, Davao City",
        description: "SM Lanang Premier, JP Laurel Ave, Davao City",
        coordinates: LatLng(7.1008, 125.6344),
      ),
      LocalPrediction(
        placeId: "2",
        mainText: "Abreeza Mall",
        secondaryText: "JP Laurel Ave, Davao City",
        description: "Abreeza Mall, JP Laurel Ave, Davao City",
        coordinates: LatLng(7.0861, 125.6130),
      ),
      // ... (rest of the popular places remain the same)
    ];
  }

  // Default recent places for Davao - using popular Davao locations with ride history
  static List<LocalPrediction> getDefaultRecentPlaces() {
    return [];
  }

  // Create a "Search More" prediction
  static LocalPrediction getSearchMoreOption() {
    return LocalPrediction(
      placeId: "search_more",
      mainText: "Search for more places",
      secondaryText: "Find specific locations in Davao",
      description: "Search for more places in Davao",
      coordinates: LatLng(0, 0),
      isSearchMore: true,
    );
  }

  // Filter local suggestions based on query
  static List<LocalPrediction> filterLocalSuggestions(
    String query,
    List<LocalPrediction> recentPlaces,
    List<LocalPrediction> popularPlaces,
  ) {
    final lowercaseQuery = query.toLowerCase();
    List<LocalPrediction> results = [];

    // First check recents (higher priority)
    results.addAll(
      recentPlaces.where(
        (place) =>
            place.mainText.toLowerCase().contains(lowercaseQuery) ||
            place.secondaryText.toLowerCase().contains(lowercaseQuery),
      ),
    );

    // Then add from popular places
    results.addAll(
      popularPlaces.where(
        (place) =>
            place.mainText.toLowerCase().contains(lowercaseQuery) ||
            place.secondaryText.toLowerCase().contains(lowercaseQuery),
      ),
    );

    // Remove duplicates and limit to top results
    results = results.toSet().toList();

    return results;
  }
}

// Helper function to fetch saved locations from Firebase
Future<List<LocalPrediction>> getSavedLocationsFromFirebase() async {
  try {
    // Fetch saved locations using the SavedLocationsService
    final savedLocations = await SavedLocationsService.getSavedLocations();

    // Convert saved locations to LocalPrediction
    return savedLocations
        .map((location) => location.toLocalPrediction())
        .toList();
  } catch (e) {
    print("❌ Failed to fetch saved locations: $e");
    return [];
  }
}
