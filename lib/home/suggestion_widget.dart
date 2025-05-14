import 'package:flutter/material.dart';
import 'local_prediction.dart';

class LocationSuggestionWidget extends StatelessWidget {
  final List<LocalPrediction> predictions;
  final Function(LocalPrediction) onTap;
  final Color iconColor;

  const LocationSuggestionWidget({
    Key? key,
    required this.predictions,
    required this.onTap,
    required this.iconColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: predictions.length,
        itemBuilder: (context, index) {
          final prediction = predictions[index];

          // Determine icon based on location type
          IconData leadingIcon;
          Color? iconColorOverride;

          if (prediction.isSearchMore) {
            leadingIcon = Icons.search;
          } else if (prediction.recent_history != null &&
              prediction.recent_history!['source'] == 'saved_location') {
            // Check for saved location types
            final locationType =
                prediction.recent_history!['type']?.toString() ?? 'other';
            final isFavorite = prediction.recent_history!['isFavorite'] == true;

            if (isFavorite) {
              leadingIcon = Icons.favorite;
              iconColorOverride = Colors.red;
            } else {
              switch (locationType) {
                case 'home':
                  leadingIcon = Icons.home;
                  break;
                case 'work':
                  leadingIcon = Icons.work;
                  break;
                default:
                  leadingIcon = Icons.star;
              }
            }
          } else if (prediction.isRecent) {
            leadingIcon = Icons.history;
          } else {
            leadingIcon = Icons.location_on;
          }

          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onTap(prediction),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Row(
                  children: [
                    Icon(
                      leadingIcon,
                      color: iconColorOverride ?? iconColor,
                      size: 20,
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            prediction.mainText,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 4),
                          Text(
                            prediction.secondaryText,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Add a trailing icon for saved locations
                    if (prediction.recent_history != null &&
                        prediction.recent_history!['source'] ==
                            'saved_location')
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: Icon(
                          Icons.bookmark,
                          size: 16,
                          color: Colors.grey.shade400,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
