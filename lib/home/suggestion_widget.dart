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
    if (predictions.isEmpty) {
      return SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 1,
            offset: Offset(0, 3),
          ),
        ],
      ),
      margin: EdgeInsets.only(top: 4, bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ListView.separated(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: predictions.length,
            separatorBuilder: (context, index) =>
                Divider(height: 1, thickness: 0.5, indent: 56),
            itemBuilder: (context, index) {
              final prediction = predictions[index];

              // Choose icon based on prediction type
              IconData iconData;
              Color itemIconColor;

              if (prediction.isSearchMore) {
                iconData = Icons.search;
                itemIconColor = Colors.blue;
              } else if (prediction.isRecent) {
                iconData = Icons.history;
                itemIconColor = Colors.grey.shade600;
              } else if (prediction.isOnlineResult) {
                iconData = Icons.public;
                itemIconColor = iconColor;
              } else {
                iconData = Icons.location_on_outlined;
                itemIconColor = iconColor;
              }

              return InkWell(
                onTap: () => onTap(prediction),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  child: Row(
                    children: [
                      SizedBox(width: 8),
                      Icon(iconData, color: itemIconColor, size: 22),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              prediction.mainText,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: prediction.isSearchMore
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: prediction.isSearchMore
                                      ? Colors.blue
                                      : Colors.black.withOpacity(0.85)),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              prediction.secondaryText,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                      // Add an arrow for the search more option
                      if (prediction.isSearchMore)
                        Icon(Icons.arrow_forward_ios,
                            color: Colors.blue, size: 14),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
