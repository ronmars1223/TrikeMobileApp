import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'local_prediction.dart';

class LocationSearchService {
  // Default coordinates for Cagayan de Oro
  static const LatLng defaultCoordinates = LatLng(8.4542, 124.6319);

  // Search for locations using Nominatim (OpenStreetMap) API
  static Future<List<LocalPrediction>> searchLocations(String query) async {
    List<LocalPrediction> results = [];

    try {
      final String encodedQuery = Uri.encodeComponent(query);

      // Using Nominatim (OpenStreetMap) API which is free
      final String url =
          'https://nominatim.openstreetmap.org/search?q=$encodedQuery+philippines&format=json&countrycodes=ph&limit=5';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'RideShareApp', // Required by Nominatim's policy
          'Accept-Language': 'en', // Get results in English
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;

        if (data.isNotEmpty) {
          for (final place in data) {
            String name = place['name'] ?? '';
            if (name.isEmpty) {
              final displayNameParts = place['display_name'].toString().split(
                ',',
              );
              name = displayNameParts.first.trim();
            }

            // Extract a cleaner secondary text from display_name
            final displayNameParts = place['display_name'].toString().split(
              ',',
            );
            String secondaryText =
                displayNameParts.length > 1
                    ? displayNameParts.sublist(1).take(3).join(', ').trim()
                    : "Philippines";

            results.add(
              LocalPrediction(
                placeId: place['place_id'].toString(),
                mainText: name,
                secondaryText: secondaryText,
                description: place['display_name'].toString(),
                coordinates: LatLng(
                  double.parse(place['lat'].toString()),
                  double.parse(place['lon'].toString()),
                ),
                isOnlineResult: true,
              ),
            );
          }
        }
      }
    } catch (e) {
      print("❌ Error searching with Nominatim: $e");
    }

    return results;
  }

  // Geocode an address to get coordinates
  static Future<LatLng?> geocodeAddress(String address) async {
    try {
      // Using Nominatim API first
      final String encodedAddress = Uri.encodeComponent(address);
      final String url =
          'https://nominatim.openstreetmap.org/search?q=$encodedAddress+philippines&format=json&limit=1&countrycodes=ph';

      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'RideShareApp'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;

        if (data.isNotEmpty) {
          final place = data.first;
          final lat = double.parse(place['lat'].toString());
          final lng = double.parse(place['lon'].toString());

          return LatLng(lat, lng);
        }
      }

      // Fallback to built-in geocoding if Nominatim fails
      List<Location> locations = await locationFromAddress(
        "$address, Philippines",
      );
      if (locations.isNotEmpty) {
        return LatLng(locations[0].latitude, locations[0].longitude);
      }
    } catch (e) {
      print("Error geocoding address: $e");

      // Try built-in geocoding as fallback
      try {
        List<Location> locations = await locationFromAddress(
          "$address, Philippines",
        );
        if (locations.isNotEmpty) {
          return LatLng(locations[0].latitude, locations[0].longitude);
        }
      } catch (e2) {
        print("Error with fallback geocoding: $e2");
      }
    }

    // Return null if geocoding fails
    return null;
  }

  // Try to match text input with existing predictions
  static LatLng? matchTextWithPredictions(
    String input,
    List<LocalPrediction> predictions,
  ) {
    final lowercaseInput = input.toLowerCase();

    // Check exact matches first
    for (final place in predictions) {
      final fullDescription =
          "${place.mainText}, ${place.secondaryText}".toLowerCase();
      if (fullDescription == lowercaseInput ||
          place.mainText.toLowerCase() == lowercaseInput) {
        return place.coordinates;
      }
    }

    // Then check partial matches
    for (final place in predictions) {
      final fullDescription =
          "${place.mainText}, ${place.secondaryText}".toLowerCase();
      if (fullDescription.contains(lowercaseInput) ||
          lowercaseInput.contains(place.mainText.toLowerCase())) {
        return place.coordinates;
      }
    }

    // No match found
    return null;
  }
}
