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

  LocalPrediction({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
    required this.description,
    required this.coordinates,
    this.isRecent = false,
    this.isOnlineResult = false,
    this.isSearchMore = false,
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
      LocalPrediction(
        placeId: "3",
        mainText: "Gaisano Mall",
        secondaryText: "JP Laurel Ave, Davao City",
        description: "Gaisano Mall, JP Laurel Ave, Davao City",
        coordinates: LatLng(7.0906, 125.6156),
      ),
      LocalPrediction(
        placeId: "4",
        mainText: "NCCC Mall",
        secondaryText: "Maa Road, Davao City",
        description: "NCCC Mall, Maa Road, Davao City",
        coordinates: LatLng(7.0661, 125.6136),
      ),
      LocalPrediction(
        placeId: "5",
        mainText: "People's Park",
        secondaryText: "Davao City",
        description: "People's Park, Davao City",
        coordinates: LatLng(7.0682, 125.6095),
      ),
      LocalPrediction(
        placeId: "6",
        mainText: "Francisco Bangoy International Airport",
        secondaryText: "Davao City",
        description: "Francisco Bangoy International Airport, Davao City",
        coordinates: LatLng(7.1254, 125.6481),
      ),
      LocalPrediction(
        placeId: "7",
        mainText: "Davao Crocodile Park",
        secondaryText: "Diversion Road, Davao City",
        description: "Davao Crocodile Park, Diversion Road, Davao City",
        coordinates: LatLng(7.0531, 125.5642),
      ),
      LocalPrediction(
        placeId: "8",
        mainText: "Philippine Eagle Center",
        secondaryText: "Malagos, Davao City",
        description: "Philippine Eagle Center, Malagos, Davao City",
        coordinates: LatLng(7.1905, 125.4513),
      ),
      LocalPrediction(
        placeId: "9",
        mainText: "Samal Island",
        secondaryText: "Davao del Norte",
        description: "Samal Island, Davao del Norte",
        coordinates: LatLng(7.0983, 125.7104),
      ),
      LocalPrediction(
        placeId: "10",
        mainText: "Eden Nature Park",
        secondaryText: "Toril, Davao City",
        description: "Eden Nature Park, Toril, Davao City",
        coordinates: LatLng(7.0216, 125.5084),
      ),
      LocalPrediction(
        placeId: "11",
        mainText: "Victoria Plaza",
        secondaryText: "JP Laurel Ave, Davao City",
        description: "Victoria Plaza, JP Laurel Ave, Davao City",
        coordinates: LatLng(7.0849, 125.6108),
      ),
      LocalPrediction(
        placeId: "12",
        mainText: "Roxas Night Market",
        secondaryText: "Roxas Ave, Davao City",
        description: "Roxas Night Market, Roxas Ave, Davao City",
        coordinates: LatLng(7.0663, 125.6073),
      ),
      LocalPrediction(
        placeId: "13",
        mainText: "University of the Philippines Mindanao",
        secondaryText: "Mintal, Davao City",
        description:
            "University of the Philippines Mindanao, Mintal, Davao City",
        coordinates: LatLng(7.0566, 125.5049),
      ),
      LocalPrediction(
        placeId: "14",
        mainText: "Ateneo de Davao University",
        secondaryText: "E. Jacinto St, Davao City",
        description: "Ateneo de Davao University, E. Jacinto St, Davao City",
        coordinates: LatLng(7.0708, 125.6094),
      ),
      LocalPrediction(
        placeId: "15",
        mainText: "Tagum City",
        secondaryText: "Davao del Norte",
        description: "Tagum City, Davao del Norte",
        coordinates: LatLng(7.4478, 125.8089),
      ),
      LocalPrediction(
        placeId: "16",
        mainText: "Digos City",
        secondaryText: "Davao del Sur",
        description: "Digos City, Davao del Sur",
        coordinates: LatLng(6.7495, 125.3572),
      ),
      LocalPrediction(
        placeId: "17",
        mainText: "Mati City",
        secondaryText: "Davao Oriental",
        description: "Mati City, Davao Oriental",
        coordinates: LatLng(6.9589, 126.2193),
      ),
      LocalPrediction(
        placeId: "18",
        mainText: "Panabo City",
        secondaryText: "Davao del Norte",
        description: "Panabo City, Davao del Norte",
        coordinates: LatLng(7.3056, 125.6839),
      ),
      LocalPrediction(
        placeId: "19",
        mainText: "Pearl Farm Beach Resort",
        secondaryText: "Samal Island, Davao",
        description: "Pearl Farm Beach Resort, Samal Island, Davao",
        coordinates: LatLng(7.0523, 125.7689),
      ),
      LocalPrediction(
        placeId: "20",
        mainText: "Davao City Hall",
        secondaryText: "San Pedro St, Davao City",
        description: "Davao City Hall, San Pedro St, Davao City",
        coordinates: LatLng(7.0642, 125.6083),
      ),
    ];
  }

  // Default recent places for Davao - using popular Davao locations
  static List<LocalPrediction> getDefaultRecentPlaces() {
    return [
      LocalPrediction(
        placeId: "r1",
        mainText: "SM City Davao",
        secondaryText: "Quimpo Boulevard, Davao City",
        description: "SM City Davao, Quimpo Boulevard, Davao City",
        coordinates: LatLng(7.0530, 125.5957),
        isRecent: true,
      ),
      LocalPrediction(
        placeId: "r2",
        mainText: "Davao Doctors Hospital",
        secondaryText: "E. Quirino Ave, Davao City",
        description: "Davao Doctors Hospital, E. Quirino Ave, Davao City",
        coordinates: LatLng(7.0671, 125.6030),
        isRecent: true,
      ),
    ];
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
